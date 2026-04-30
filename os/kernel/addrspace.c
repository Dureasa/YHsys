#include "param.h"
#include "types.h"
#include "memlayout.h"
#include "elf.h"
#include "riscv.h"
#include "defs.h"
#include "spinlock.h"
#include "proc.h"
#include "fs.h"

/*
 * the kernel's page table.
 */
pagetable_t kernel_pagetable;

extern char etext[];  // kernel.ld sets this to end of kernel code.

extern char trampoline[]; // trampoline.S

// Make a direct-map page table for the kernel.
pagetable_t
kvmmake(void)
{
  pagetable_t kpgtbl;

  kpgtbl = (pagetable_t) kalloc();
  memset(kpgtbl, 0, PGSIZE);

  // uart registers
  kvmmap(kpgtbl, UART0, UART0, PGSIZE, PTE_R | PTE_W);

  // virtio mmio disk interface
  kvmmap(kpgtbl, VIRTIO0, VIRTIO0, PGSIZE, PTE_R | PTE_W);

  // PLIC
  kvmmap(kpgtbl, PLIC, PLIC, 0x4000000, PTE_R | PTE_W);

  // map kernel text executable and read-only.
  kvmmap(kpgtbl, KERNBASE, KERNBASE, (uint32)etext-KERNBASE, PTE_R | PTE_X);

  // map kernel data and the physical RAM we'll make use of.
  kvmmap(kpgtbl, (uint32)etext, (uint32)etext, PHYSTOP-(uint32)etext, PTE_R | PTE_W);

  // map the trampoline for trap entry/exit to
  // the highest virtual address in the kernel.
  kvmmap(kpgtbl, TRAMPOLINE, (uint32)trampoline, PGSIZE, PTE_R | PTE_X);

  // allocate and map a kernel stack for each process.
  proc_mapstacks(kpgtbl);

  return kpgtbl;
}

// add a mapping to the kernel page table.
// only used when booting.
// does not flush TLB or enable paging.
void
kvmmap(pagetable_t kpgtbl, uint32 va, uint32 pa, uint32 sz, int perm)
{
  if(mappages(kpgtbl, va, sz, pa, perm) != 0)
    panic("kvmmap");
}

// Initialize the kernel_pagetable, shared by all CPUs.
void
kvminit(void)
{
  kernel_pagetable = kvmmake();
}

// Switch the current CPU's h/w page table register to
// the kernel's page table, and enable paging.
void
kvminithart()
{
  // wait for any previous writes to the page table memory to finish.
  sfence_vma();

  w_satp(MAKE_SATP(kernel_pagetable));

  // flush stale entries from the TLB.
  sfence_vma();
}

// Return the address of the PTE in page table pagetable
// that corresponds to virtual address va.  If alloc!=0,
// create any required page-table pages.
//
// The risc-v Sv32 scheme has two levels of page-table
// pages. A page-table page contains 1024 32-bit PTEs.
// A 32-bit virtual address is split into three fields:
//   20..31 -- 12 bits of level-1 index.
//   12..19 -- 8 bits of level-0 index.
//    0..11 -- 12 bits of byte offset within the page.
pte_t *
walk(pagetable_t pagetable, uint32 va, int alloc)
{
  if(va >= MAXVA)
    panic("walk");

  for(int level = 1; level > 0; level--) {
    pte_t *pte = &pagetable[PX(level, va)];
    if(*pte & PTE_V) {
      pagetable = (pagetable_t)PTE2PA(*pte);
    } else {
      if(!alloc || (pagetable = (pde_t*)kalloc()) == 0)
        return 0;
      memset(pagetable, 0, PGSIZE);
      *pte = PA2PTE(pagetable) | PTE_V;
    }
  }
  return &pagetable[PX(0, va)];
}

// Look up a virtual address, return the physical address,
// or 0 if not mapped.
// Can only be used to look up user pages.
uint32
walkaddr(pagetable_t pagetable, uint32 va)
{
  pte_t *pte;
  uint32 pa;

  if(va >= MAXVA)
    return 0;

  pte = walk(pagetable, va, 0);
  if(pte == 0)
    return 0;
  if((*pte & PTE_V) == 0)
    return 0;
  if((*pte & PTE_U) == 0)
    return 0;
  pa = PTE2PA(*pte);
  return pa;
}

// Create PTEs for virtual addresses starting at va that refer to
// physical addresses starting at pa.
// va and size MUST be page-aligned.
// Returns 0 on success, -1 if walk() couldn't
// allocate a needed page-table page.
int
mappages(pagetable_t pagetable, uint32 va, uint32 size, uint32 pa, int perm)
{
  uint32 a, last;
  pte_t *pte;

  if((va % PGSIZE) != 0)
    panic("mappages: va not aligned");

  if((size % PGSIZE) != 0)
    panic("mappages: size not aligned");

  if(size == 0)
    panic("mappages: size");

  a = va;
  last = va + size - PGSIZE;
  for(;;){
    if((pte = walk(pagetable, a, 1)) == 0)
      return -1;
    if(*pte & PTE_V)
      panic("mappages: remap");
    *pte = PA2PTE(pa) | perm | PTE_V;
    if(a == last)
      break;
    a += PGSIZE;
    pa += PGSIZE;
  }
  return 0;
}

// create an empty user page table.
// returns 0 if out of memory.
pagetable_t
uvmcreate()
{
  pagetable_t pagetable;
  pagetable = (pagetable_t) kalloc();
  if(pagetable == 0)
    return 0;
  memset(pagetable, 0, PGSIZE);
  return pagetable;
}

struct addr_space
as_create(void)
{
  struct addr_space as;
  memset(&as, 0, sizeof(as));
  as.pagetable = uvmcreate();
  return as;
}

static int
as_region_index(struct addr_space *as, int type)
{
  int i;

  for(i = 0; i < as->region_count; i++){
    if(as->regions[i].type == type)
      return i;
  }
  return -1;
}

static int
as_region_do_free(int type)
{
  return type != MR_MMIO && type != MR_TRAPFRAME && type != MR_TRAMPOLINE;
}

static uint32
as_region_map_start(struct mem_region *r)
{
  return PGROUNDDOWN(r->va_start);
}

static uint32
as_region_map_npages(struct mem_region *r)
{
  uint32 start, end;

  if(r->va_end <= r->va_start)
    return 0;
  start = PGROUNDDOWN(r->va_start);
  end = PGROUNDUP(r->va_end);
  return (end - start) / PGSIZE;
}

int
as_add_region(struct addr_space *as, uint32 va_start, uint32 va_end, int type, int perm)
{
  int i, ins;

  if(as == 0 || as->pagetable == 0)
    return -1;
  if((va_start % PGSIZE) != 0)
    return -1;
  if(type != MR_HEAP && (va_end % PGSIZE) != 0)
    return -1;
  if(va_end < va_start || va_end > TRAPFRAME)
    return -1;
  if(as->region_count >= MAX_MREGIONS)
    return -1;
  if(as_region_index(as, type) >= 0)
    return -1;

  for(i = 0; i < as->region_count; i++){
    struct mem_region *r = &as->regions[i];
    if(!(va_end <= r->va_start || va_start >= r->va_end))
      return -1;
  }

  ins = as->region_count;
  for(i = 0; i < as->region_count; i++){
    if(va_start < as->regions[i].va_start){
      ins = i;
      break;
    }
  }
  for(i = as->region_count; i > ins; i--)
    as->regions[i] = as->regions[i - 1];

  as->regions[ins].va_start = va_start;
  as->regions[ins].va_end = va_end;
  as->regions[ins].type = type;
  as->regions[ins].perm = perm;
  as->region_count++;
  return 0;
}

struct mem_region *
as_find_region(struct addr_space *as, uint32 va)
{
  int i;

  if(as == 0)
    return 0;
  for(i = 0; i < as->region_count; i++){
    struct mem_region *r = &as->regions[i];
    if(va >= r->va_start && va < r->va_end)
      return r;
  }
  return 0;
}

void
as_remove_region(struct addr_space *as, int type)
{
  int i, idx;
  struct mem_region r;

  if(as == 0 || as->pagetable == 0)
    return;

  idx = as_region_index(as, type);
  if(idx < 0)
    return;

  r = as->regions[idx];
  if(as_region_map_npages(&r) > 0)
    uvmunmap(as, as_region_map_start(&r), as_region_map_npages(&r), as_region_do_free(r.type));

  for(i = idx; i + 1 < as->region_count; i++)
    as->regions[i] = as->regions[i + 1];
  as->region_count--;
}

uint32
as_region_start(struct addr_space *as, int type)
{
  int idx;

  if(as == 0)
    return 0;
  idx = as_region_index(as, type);
  if(idx < 0)
    return 0;
  return as->regions[idx].va_start;
}

uint32
as_region_size(struct addr_space *as, int type)
{
  int idx;

  if(as == 0)
    return 0;
  idx = as_region_index(as, type);
  if(idx < 0)
    return 0;
  return as->regions[idx].va_end - as->regions[idx].va_start;
}

int
as_resize_region(struct addr_space *as, int type, uint32 new_end)
{
  int i, idx;
  uint32 va_start;

  if(as == 0)
    return -1;
  if(new_end > TRAPFRAME)
    return -1;

  idx = as_region_index(as, type);
  if(idx < 0)
    return -1;

  va_start = as->regions[idx].va_start;
  if(new_end < va_start)
    return -1;

  for(i = 0; i < as->region_count; i++){
    struct mem_region *r;
    if(i == idx)
      continue;
    r = &as->regions[i];
    if(!(new_end <= r->va_start || va_start >= r->va_end))
      return -1;
  }

  as->regions[idx].va_end = new_end;
  return 0;
}

void
as_print(struct addr_space *as)
{
  int i;

  if(as == 0){
    printf("addr_space: null\n");
    return;
  }

  printf("addr_space: pagetable=%p regions=%d\n", as->pagetable, as->region_count);
  for(i = 0; i < as->region_count; i++){
    struct mem_region *r = &as->regions[i];
    printf("  [%d] %x-%x type=%d perm=%x\n", i, r->va_start, r->va_end, r->type, r->perm);
  }
}

// Remove npages of mappings starting from va. va must be
// page-aligned. It's OK if the mappings don't exist.
// Optionally free the physical memory.
void
uvmunmap(struct addr_space *as, uint32 va, uint32 npages, int do_free)
{
  uint32 a;
  uint32 i;
  pte_t *pte;
  pagetable_t pagetable;

  if(as == 0 || as->pagetable == 0)
    panic("uvmunmap: as");

  pagetable = as->pagetable;

  if((va % PGSIZE) != 0)
    panic("uvmunmap: not aligned");

  a = va;
  for(i = 0; i < npages; i++, a += PGSIZE){
    if((pte = walk(pagetable, a, 0)) == 0) // leaf page table entry allocated?
      continue;
    if((*pte & PTE_V) == 0)  // has physical page been allocated?
      continue;
    if(do_free){
      uint32 pa = PTE2PA(*pte);
      kfree((void*)(uint32)pa);
    }
    *pte = 0;
  }
}

// Allocate PTEs and physical memory to grow a process from oldsz to
// newsz, which need not be page aligned.  Returns new size or 0 on error.
uint32
uvmalloc(struct addr_space *as, uint32 oldsz, uint32 newsz, int xperm)
{
  char *mem;
  uint32 a;
  pagetable_t pagetable;

  if(as == 0 || as->pagetable == 0)
    return 0;
  pagetable = as->pagetable;

  if(newsz < oldsz)
    return oldsz;

  oldsz = PGROUNDUP(oldsz);
  for(a = oldsz; a < newsz; a += PGSIZE){
    mem = kalloc();
    if(mem == 0){
      uvmdealloc(as, a, oldsz);
      return 0;
    }
    memset(mem, 0, PGSIZE);
    if(mappages(pagetable, a, PGSIZE, (uint32)mem, PTE_R|PTE_U|xperm) != 0){
      kfree(mem);
      uvmdealloc(as, a, oldsz);
      return 0;
    }
  }
  return newsz;
}

// Deallocate user pages to bring the process size from oldsz to
// newsz.  oldsz and newsz need not be page-aligned, nor does newsz
// need to be less than oldsz.  oldsz can be larger than the actual
// process size.  Returns the new process size.
uint32
uvmdealloc(struct addr_space *as, uint32 oldsz, uint32 newsz)
{
  if(newsz >= oldsz)
    return oldsz;

  if(PGROUNDUP(newsz) < PGROUNDUP(oldsz)){
    int npages = (PGROUNDUP(oldsz) - PGROUNDUP(newsz)) / PGSIZE;
    uvmunmap(as, PGROUNDUP(newsz), npages, 1);
  }

  return newsz;
}

// Recursively free page-table pages.
// All leaf mappings must already have been removed.
void
freewalk(pagetable_t pagetable)
{
  // there are 2^10 = 1024 PTEs in a page table (Sv32).
  for(int i = 0; i < 1024; i++){
    pte_t pte = pagetable[i];
    if((pte & PTE_V) && (pte & (PTE_R|PTE_W|PTE_X)) == 0){
      // this PTE points to a lower-level page table.
      uint32 child = PTE2PA(pte);
      freewalk((pagetable_t)child);
      pagetable[i] = 0;
    } else if(pte & PTE_V){
      panic("freewalk: leaf");
    }
  }
  kfree((void*)pagetable);
}

static void
freewalkall(pagetable_t pagetable)
{
  for(int i = 0; i < 1024; i++){
    pte_t pte = pagetable[i];
    if((pte & PTE_V) == 0)
      continue;
    if((pte & (PTE_R|PTE_W|PTE_X)) == 0){
      uint32 child = PTE2PA(pte);
      freewalkall((pagetable_t)child);
    } else {
      kfree((void*)PTE2PA(pte));
    }
    pagetable[i] = 0;
  }
  kfree((void*)pagetable);
}

// Free user memory pages,
// then free page-table pages.
void
uvmfree(struct addr_space *as)
{
  int i;

  if(as == 0 || as->pagetable == 0)
    return;

  for(i = 0; i < as->region_count; i++){
    struct mem_region *r = &as->regions[i];
    if(as_region_map_npages(r) > 0)
      uvmunmap(as, as_region_map_start(r), as_region_map_npages(r), as_region_do_free(r->type));
  }

  as->region_count = 0;
  freewalkall(as->pagetable);
  as->pagetable = 0;
}

void
as_destroy(struct addr_space *as)
{
  if(as == 0 || as->pagetable == 0){
    if(as)
      as->region_count = 0;
    return;
  }

  uvmunmap(as, TRAMPOLINE, 1, 0);
  uvmunmap(as, TRAPFRAME, 1, 0);
  uvmfree(as);
}

int
as_copy(struct addr_space *dst, struct addr_space *src)
{
  pte_t *pte;
  uint32 pa, va;
  uint flags;
  int i;

  if(dst == 0 || src == 0 || dst->pagetable == 0 || src->pagetable == 0)
    return -1;

  for(i = 0; i < dst->region_count; i++){
    struct mem_region *r = &dst->regions[i];
    if(as_region_map_npages(r) > 0)
      uvmunmap(dst, as_region_map_start(r), as_region_map_npages(r), as_region_do_free(r->type));
  }
  dst->region_count = 0;

  for(i = 0; i < src->region_count; i++){
    struct mem_region *r = &src->regions[i];
    if(as_add_region(dst, r->va_start, r->va_end, r->type, r->perm) < 0)
      goto err;

    for(va = PGROUNDDOWN(r->va_start); va < PGROUNDUP(r->va_end); va += PGSIZE){
      if((pte = walk(src->pagetable, va, 0)) == 0)
        continue;
      if((*pte & PTE_V) == 0)
        continue;

      pa = PTE2PA(*pte);
      flags = PTE_FLAGS(*pte);

      if(flags & PTE_W){
        flags = (flags & ~PTE_W) | PTE_COW;
        *pte = PA2PTE(pa) | flags;
      }

      kaddref(pa);
      if(mappages(dst->pagetable, va, PGSIZE, pa, flags) != 0){
        kfree((void*)pa);
        goto err;
      }
    }
  }

  sfence_vma();
  return 0;

 err:
  for(i = 0; i < dst->region_count; i++){
    struct mem_region *r = &dst->regions[i];
    if(as_region_map_npages(r) > 0)
      uvmunmap(dst, as_region_map_start(r), as_region_map_npages(r), as_region_do_free(r->type));
  }
  dst->region_count = 0;
  sfence_vma();
  return -1;
}

int
uvmcopy(struct addr_space *dst_as, struct addr_space *src_as)
{
  return as_copy(dst_as, src_as);
}

struct addr_space
proc_addrspace_create(struct proc *p)
{
  struct addr_space as;

  as = as_create();
  if(as.pagetable == 0)
    return as;

  if(mappages(as.pagetable, TRAMPOLINE, PGSIZE, (uint32)trampoline, PTE_R | PTE_X) < 0){
    as_destroy(&as);
    return as;
  }

  if(mappages(as.pagetable, TRAPFRAME, PGSIZE, (uint32)p->trapframe, PTE_R | PTE_W) < 0){
    as_destroy(&as);
    return as;
  }

  return as;
}

void
proc_addrspace_free(struct proc *p)
{
  as_destroy(&p->as);
}

// mark a PTE invalid for user access.
// used by exec for the user stack guard page.
void
uvmclear(pagetable_t pagetable, uint32 va)
{
  pte_t *pte;

  pte = walk(pagetable, va, 0);
  if(pte == 0)
    panic("uvmclear");
  *pte &= ~PTE_U;
}

// Copy from kernel to user.
// Copy len bytes from src to virtual address dstva in a given page table.
// Return 0 on success, -1 on error.
int
copyout(pagetable_t pagetable, uint32 dstva, char *src, uint32 len)
{
  uint32 n, va0, pa0;
  pte_t *pte;

  while(len > 0){
    va0 = PGROUNDDOWN(dstva);
    if(va0 >= MAXVA)
      return -1;

    pte = walk(pagetable, va0, 0);
    if(pte == 0 || (*pte & PTE_V) == 0 || (*pte & PTE_U) == 0) {
      if((pa0 = vmfault(pagetable, va0, 0)) == 0) {
        return -1;
      }
    } else if((*pte & PTE_COW) != 0) {
      if((pa0 = vmfault(pagetable, va0, 0)) == 0) {
        return -1;
      }
    } else {
      pa0 = PTE2PA(*pte);
    }

    pte = walk(pagetable, va0, 0);
    // forbid copyout over read-only user text pages.
    if((*pte & PTE_W) == 0)
      return -1;

    n = PGSIZE - (dstva - va0);
    if(n > len)
      n = len;
    memmove((void *)(uint32)(pa0 + (dstva - va0)), src, n);

    len -= n;
    src += n;
    dstva = va0 + PGSIZE;
  }
  return 0;
}

// Copy from user to kernel.
// Copy len bytes to dst from virtual address srcva in a given page table.
// Return 0 on success, -1 on error.
int
copyin(pagetable_t pagetable, char *dst, uint32 srcva, uint32 len)
{
  uint32 n, va0, pa0;

  while(len > 0){
    va0 = PGROUNDDOWN(srcva);
    pa0 = walkaddr(pagetable, va0);
    if(pa0 == 0) {
      if((pa0 = vmfault(pagetable, va0, 0)) == 0) {
        return -1;
      }
    }
    n = PGSIZE - (srcva - va0);
    if(n > len)
      n = len;
    memmove(dst, (void *)(uint32)(pa0 + (srcva - va0)), n);

    len -= n;
    dst += n;
    srcva = va0 + PGSIZE;
  }
  return 0;
}

// Copy a null-terminated string from user to kernel.
// Copy bytes to dst from virtual address srcva in a given page table,
// until a '\0', or max.
// Return 0 on success, -1 on error.
int
copyinstr(pagetable_t pagetable, char *dst, uint32 srcva, uint32 max)
{
  uint32 n, va0, pa0;
  int got_null = 0;

  while(got_null == 0 && max > 0){
    va0 = PGROUNDDOWN(srcva);
    pa0 = walkaddr(pagetable, va0);
    if(pa0 == 0)
      return -1;
    n = PGSIZE - (srcva - va0);
    if(n > max)
      n = max;

    char *p = (char *)(uint32)(pa0 + (srcva - va0));
    while(n > 0){
      if(*p == '\0'){
        *dst = '\0';
        got_null = 1;
        break;
      } else {
        *dst = *p;
      }
      --n;
      --max;
      p++;
      dst++;
    }

    srcva = va0 + PGSIZE;
  }
  if(got_null){
    return 0;
  } else {
    return -1;
  }
}

// allocate and map user memory if process is referencing a page
// that was lazily allocated in sys_sbrk().
// returns 0 if va is invalid or already mapped, or if
// out of physical memory, and physical address if successful.
uint32
vmfault(pagetable_t pagetable, uint32 va, int read)
{
  uint32 mem, pa;
  pte_t *pte;
  uint flags;
  uint32 heap_end;
  struct mem_region *r;
  struct proc *p = myproc();

  heap_end = as_region_start(&p->as, MR_HEAP) + as_region_size(&p->as, MR_HEAP);
  if(va >= heap_end)
    return 0;
  va = PGROUNDDOWN(va);

  pte = walk(pagetable, va, 0);
  if(pte && (*pte & PTE_V)){
    // Write fault on a COW page: allocate a private writable copy.
    if(((*pte & PTE_COW) == 0) || read)
      return 0;

    pa = PTE2PA(*pte);
    flags = PTE_FLAGS(*pte);

    mem = (uint32)kalloc();
    if(mem == 0)
      return 0;

    memmove((void*)mem, (void*)(uint32)pa, PGSIZE);
    *pte = PA2PTE(mem) | ((flags | PTE_W) & ~PTE_COW);
    sfence_vma();
    kfree((void*)pa);
    return mem;
  }

  if(ismapped(pagetable, va))
    return 0;

  r = as_find_region(&p->as, va);
  if(r == 0 || r->type != MR_HEAP)
    return 0;

  mem = (uint32)kalloc();
  if(mem == 0)
    return 0;
  memset((void *)mem, 0, PGSIZE);
  if(mappages(pagetable, va, PGSIZE, mem, PTE_U | r->perm) != 0){
    kfree((void *)mem);
    return 0;
  }
  return mem;
}

int
ismapped(pagetable_t pagetable, uint32 va)
{
  pte_t *pte = walk(pagetable, va, 0);
  if (pte == 0) {
    return 0;
  }
  if (*pte & PTE_V){
    return 1;
  }
  return 0;
}
