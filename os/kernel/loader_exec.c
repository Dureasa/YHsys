#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "spinlock.h"
#include "proc.h"
#include "defs.h"
#include "elf.h"

static int loadseg(pde_t *, uint32, struct inode *, uint, uint);
static int allocseg(pagetable_t, uint32, uint32, int);

static uint32 aslr_state = 0x9e3779b9;

static uint32
aslr_next(void)
{
  uint32 x;

  aslr_state ^= r_time() + 0x7f4a7c15;
  x = aslr_state;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  aslr_state = x;
  return x;
}

static uint32
aslr_pages(uint32 max_pages)
{
  if(max_pages == 0)
    return 0;
  return aslr_next() % (max_pages + 1);
}

static int
allocseg(pagetable_t pagetable, uint32 va, uint32 sz, int perm)
{
  uint32 a, last;
  char *mem;
  pte_t *pte;

  if(sz == 0)
    return 0;

  a = va;
  last = PGROUNDDOWN(va + sz - 1);
  for(;;){
    pte = walk(pagetable, a, 0);
    if(pte && (*pte & PTE_V)){
      *pte |= (PTE_R | PTE_U | perm);
      if(a == last)
        break;
      a += PGSIZE;
      continue;
    }

    mem = kalloc();
    if(mem == 0)
      return -1;
    memset(mem, 0, PGSIZE);
    if(mappages(pagetable, a, PGSIZE, (uint32)mem, PTE_R | PTE_U | perm) != 0){
      kfree(mem);
      return -1;
    }
    if(a == last)
      break;
    a += PGSIZE;
  }

  return 0;
}

// map ELF permissions to PTE permission bits.
int flags2perm(int flags)
{
    int perm = 0;
    if(flags & 0x1)
      perm = PTE_X;
    if(flags & 0x2)
      perm |= PTE_W;
    return perm;
}

//
// the implementation of the exec() system call
//
int
kexec(char *path, char **argv)
{
  char *s, *last;
  int i, off;
  uint32 argc, sz = 0, sp, ustack[MAXARG], stackbase;
  uint32 code_jitter;
  char *jitter_pages[ASLR_CODE_MAX_PAGES] = {0};
  struct elfhdr elf;
  struct inode *ip;
  struct proghdr ph;
  pagetable_t pagetable = 0;
  struct addr_space old_as, new_as;
  struct proc *p = myproc();
  memset(&old_as, 0, sizeof(old_as));
  memset(&new_as, 0, sizeof(new_as));

  begin_op();

  // Open the executable file.
  if((ip = namei(path)) == 0){
    end_op();
    return -1;
  }
  ilock(ip);

  // Read the ELF header.
  if(readi(ip, 0, (uint32)&elf, 0, sizeof(elf)) != sizeof(elf))
    goto bad;

  // Is this really an ELF file?
  if(elf.magic != ELF_MAGIC)
    goto bad;

  new_as = proc_addrspace_create(p);
  pagetable = new_as.pagetable;
  if(pagetable == 0)
    goto bad;

  // Randomize physical placement of code pages without breaking
  // fixed-link user binaries that assume a low virtual text base.
  code_jitter = aslr_pages(ASLR_CODE_MAX_PAGES);
  for(i = 0; i < code_jitter; i++){
    jitter_pages[i] = kalloc();
    if(jitter_pages[i] == 0)
      break;
  }

  // Load program into memory.
  for(i=0, off=elf.phoff; i<elf.phnum; i++, off+=sizeof(ph)){
    uint32 segva;
    uint32 segend;

    if(readi(ip, 0, (uint32)&ph, off, sizeof(ph)) != sizeof(ph))
      goto bad;
    if(ph.type != ELF_PROG_LOAD)
      continue;
    if(ph.memsz < ph.filesz)
      goto bad;
    segva = ph.vaddr;
    segend = segva + ph.memsz;
    if(segend < segva)
      goto bad;
    if(segend >= TRAPFRAME)
      goto bad;
    if(segva % PGSIZE != 0)
      goto bad;
    if(allocseg(pagetable, segva, ph.memsz, flags2perm(ph.flags)) < 0)
      goto bad;
    if(segend > sz)
      sz = segend;
    if(loadseg(pagetable, segva, ip, ph.off, ph.filesz) < 0)
      goto bad;
  }

  for(i = 0; i < ASLR_CODE_MAX_PAGES; i++){
    if(jitter_pages[i]){
      kfree(jitter_pages[i]);
      jitter_pages[i] = 0;
    }
  }

  iunlockput(ip);
  end_op();
  ip = 0;

  // Allocate some pages at the next page boundary.
  // Make the first inaccessible as a stack guard.
  // Use the rest as the user stack.
  uint32 text_end = PGROUNDUP(sz);
  uint32 stack_gap = aslr_pages(ASLR_STACK_GAP_MAX_PAGES) * PGSIZE;
  uint32 stack_end = text_end + stack_gap + (USERSTACK+1)*PGSIZE;
  uint32 stack_guard = stack_end - (USERSTACK+1)*PGSIZE;
  if(stack_end < text_end || stack_end >= TRAPFRAME)
    goto bad;

  uint32 sz1;
  if((sz1 = uvmalloc(&new_as, stack_guard, stack_end, PTE_W)) == 0)
    goto bad;
  uvmclear(pagetable, stack_guard);
  sp = sz1;
  stackbase = sp - USERSTACK*PGSIZE;

  uint32 heap_gap = aslr_pages(ASLR_HEAP_GAP_MAX_PAGES) * PGSIZE;
  uint32 heap_base = sz1 + heap_gap;
  if(heap_base < sz1 || heap_base >= TRAPFRAME)
    goto bad;

  if(as_add_region(&new_as, 0, text_end, MR_TEXT, PTE_R | PTE_W | PTE_X) < 0)
    goto bad;
  if(as_add_region(&new_as, stack_guard, sz1, MR_STACK, PTE_R | PTE_W) < 0)
    goto bad;
  if(as_add_region(&new_as, heap_base, heap_base, MR_HEAP, PTE_R | PTE_W) < 0)
    goto bad;

  // Copy argument strings into new stack, remember their
  // addresses in ustack[].
  for(argc = 0; argv[argc]; argc++) {
    if(argc >= MAXARG)
      goto bad;
    sp -= strlen(argv[argc]) + 1;
    sp -= sp % 16; // riscv sp must be 16-byte aligned
    if(sp < stackbase)
      goto bad;
    if(copyout(pagetable, sp, argv[argc], strlen(argv[argc]) + 1) < 0)
      goto bad;
    ustack[argc] = sp;
  }
  ustack[argc] = 0;

  // push a copy of ustack[], the array of argv[] pointers.
  sp -= (argc+1) * sizeof(uint32);
  sp -= sp % 16;
  if(sp < stackbase)
    goto bad;
  if(copyout(pagetable, sp, (char *)ustack, (argc+1)*sizeof(uint32)) < 0)
    goto bad;

  // a0 and a1 contain arguments to user main(argc, argv)
  // argc is returned via the system call return
  // value, which goes in a0.
  p->trapframe->a1 = sp;

  // Save program name for debugging.
  for(last=s=path; *s; s++)
    if(*s == '/')
      last = s+1;
  safestrcpy(p->name, last, sizeof(p->name));
    
  if(elf.entry >= TRAPFRAME)
    goto bad;

  // Commit to the user image.
  old_as = p->as;
  p->as = new_as;
  new_as.pagetable = 0;
  p->trapframe->epc = elf.entry;  // initial program counter = ulib.c:start()
  p->trapframe->sp = sp; // initial stack pointer
  as_destroy(&old_as);

  return argc; // this ends up in a0, the first argument to main(argc, argv)

 bad:
  for(i = 0; i < ASLR_CODE_MAX_PAGES; i++){
    if(jitter_pages[i]){
      kfree(jitter_pages[i]);
      jitter_pages[i] = 0;
    }
  }
  if(new_as.pagetable)
    as_destroy(&new_as);
  if(ip){
    iunlockput(ip);
    end_op();
  }
  return -1;
}

// Load an ELF program segment into pagetable at virtual address va.
// va must be page-aligned
// and the pages from va to va+sz must already be mapped.
// Returns 0 on success, -1 on failure.
static int
loadseg(pagetable_t pagetable, uint32 va, struct inode *ip, uint offset, uint sz)
{
  uint i, n;
  uint32 pa;

  for(i = 0; i < sz; i += PGSIZE){
    pa = walkaddr(pagetable, va + i);
    if(pa == 0)
      panic("loadseg: address should exist");
    if(sz - i < PGSIZE)
      n = sz - i;
    else
      n = PGSIZE;
    if(readi(ip, 0, (uint32)pa, offset+i, n) != n)
      return -1;
  }
  
  return 0;
}
