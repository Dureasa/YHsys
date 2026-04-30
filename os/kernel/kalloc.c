// Physical memory allocator, for user processes,
// kernel stacks, page-table pages,
// and pipe buffers. Allocates whole 4096-byte pages.

#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "spinlock.h"
#include "riscv.h"
#include "defs.h"

void freerange(void *pa_start, void *pa_end);

extern char end[]; // first address after kernel.
                   // defined by kernel.ld.

struct run {
  struct run *next;
};

#define MAX_ORDER 15
#define NPAGES ((PHYSTOP - KERNBASE) / PGSIZE)
#define PG_BUDDY_FREE 1

struct free_area {
  struct run *freelist;
  uint32 nr_free;
};

struct {
  struct spinlock lock;
  struct free_area free_areas[MAX_ORDER + 1];
  uint16 refcnt[NPAGES];
} kmem;

static uint8 page_state[NPAGES];

static int
pa2idx(uint32 pa)
{
  return (pa - KERNBASE) / PGSIZE;
}

static uint32
idx2pa(int idx)
{
  return KERNBASE + (uint32)idx * PGSIZE;
}

static void
set_block_state(int idx, int order, uint8 state)
{
  int i;
  int npages;

  npages = 1 << order;
  for(i = 0; i < npages; i++)
    page_state[idx + i] = state;
}

static void
freelist_push(int order, struct run *r)
{
  r->next = kmem.free_areas[order].freelist;
  kmem.free_areas[order].freelist = r;
  kmem.free_areas[order].nr_free++;
}

static struct run *
freelist_pop(int order)
{
  struct run *r;

  r = kmem.free_areas[order].freelist;
  if(r){
    kmem.free_areas[order].freelist = r->next;
    kmem.free_areas[order].nr_free--;
  }
  return r;
}

static int
freelist_remove(int order, struct run *target)
{
  struct run *p;
  struct run *prev;

  prev = 0;
  for(p = kmem.free_areas[order].freelist; p; p = p->next){
    if(p == target){
      if(prev)
        prev->next = p->next;
      else
        kmem.free_areas[order].freelist = p->next;
      kmem.free_areas[order].nr_free--;
      return 1;
    }
    prev = p;
  }
  return 0;
}

static struct run *
buddy_alloc_order0(void)
{
  struct run *r;
  int order;
  int idx;
  int buddy_idx;

  for(order = 0; order <= MAX_ORDER; order++){
    if(kmem.free_areas[order].freelist)
      break;
  }
  if(order > MAX_ORDER)
    return 0;

  r = freelist_pop(order);
  idx = pa2idx((uint32)r);
  set_block_state(idx, order, 0);

  while(order > 0){
    order--;
    buddy_idx = idx + (1 << order);
    set_block_state(buddy_idx, order, PG_BUDDY_FREE);
    freelist_push(order, (struct run*)idx2pa(buddy_idx));
  }

  return (struct run*)idx2pa(idx);
}

static void
buddy_free_order0(int idx)
{
  int order;
  int buddy_idx;

  order = 0;
  set_block_state(idx, order, PG_BUDDY_FREE);

  while(order < MAX_ORDER){
    buddy_idx = idx ^ (1 << order);
    if(buddy_idx < 0 || buddy_idx >= NPAGES)
      break;
    if(page_state[buddy_idx] != PG_BUDDY_FREE)
      break;
    if(freelist_remove(order, (struct run*)idx2pa(buddy_idx)) == 0)
      break;

    set_block_state(idx, order, 0);
    set_block_state(buddy_idx, order, 0);
    if(buddy_idx < idx)
      idx = buddy_idx;
    order++;
    set_block_state(idx, order, PG_BUDDY_FREE);
  }

  freelist_push(order, (struct run*)idx2pa(idx));
}

void
kinit()
{
  initlock(&kmem.lock, "kmem");
  memset(kmem.free_areas, 0, sizeof(kmem.free_areas));
  memset(kmem.refcnt, 0, sizeof(kmem.refcnt));
  memset(page_state, 0, sizeof(page_state));
  freerange(end, (void*)PHYSTOP);
}

void
freerange(void *pa_start, void *pa_end)
{
  char *p;
  p = (char*)PGROUNDUP((uint32)pa_start);
  for(; p + PGSIZE <= (char*)pa_end; p += PGSIZE){
    kmem.refcnt[pa2idx((uint32)p)] = 1;
    kfree(p);
  }
}

void
kaddref(uint32 pa)
{
  int idx;

  if((pa % PGSIZE) != 0 || pa < KERNBASE || pa >= PHYSTOP)
    panic("kaddref");

  idx = pa2idx(pa);
  acquire(&kmem.lock);
  if(kmem.refcnt[idx] == 0)
    panic("kaddref: zero");
  kmem.refcnt[idx]++;
  release(&kmem.lock);
}

// Free the page of physical memory pointed at by pa,
// which normally should have been returned by a
// call to kalloc().  (The exception is when
// initializing the allocator; see kinit above.)
void
kfree(void *pa)
{
  int idx;

  if(((uint32)pa % PGSIZE) != 0 || (char*)pa < end || (uint32)pa >= PHYSTOP)
    panic("kfree");

  idx = pa2idx((uint32)pa);

  acquire(&kmem.lock);
  if(kmem.refcnt[idx] < 1)
    panic("kfree: ref");
  kmem.refcnt[idx]--;
  if(kmem.refcnt[idx] > 0){
    release(&kmem.lock);
    return;
  }

  // Fill with junk to catch dangling refs.
  memset(pa, 1, PGSIZE);
  buddy_free_order0(idx);
  release(&kmem.lock);
}

// Allocate one 4096-byte page of physical memory.
// Returns a pointer that the kernel can use.
// Returns 0 if the memory cannot be allocated.
void *
kalloc(void)
{
  struct run *r;
  int idx;

  acquire(&kmem.lock);
  r = buddy_alloc_order0();
  if(r){
    idx = pa2idx((uint32)r);
    kmem.refcnt[idx] = 1;
  }
  release(&kmem.lock);

  if(r)
    memset((char*)r, 5, PGSIZE); // fill with junk
  return (void*)r;
}
