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

// Rocket port: set while kinit() populates the free list; see kfree().
static int kinit_freeing;

// Rocket port: upstream poisons every page on free (with 1) and again on
// allocation (with 5), to catch dangling and uninitialised references. On this
// SoC each of those is a 4KB DRAM write from a 25MHz core across the FPGA
// fabric, and the measured write throughput is ~4.7 MB/s. Between them and
// uvmalloc()'s mandatory zeroing, one alloc+free round trip writes 12KB for a
// 4KB page.
//
// That is not academic: usertests' countfree() walks the entire free list one
// sbrk() at a time, twice per run, which at PHYSTOP=128MB is ~32000 pages and
// therefore ~768MB of memset -- 162 seconds by the numbers above, and 164.5s
// measured. It dominated every usertests invocation regardless of which test
// was selected.
//
// Set to 1 to restore upstream's behaviour when chasing a memory bug.
#define KFREE_POISON 0

struct {
  struct spinlock lock;
  struct run *freelist;
} kmem;

void
kinit()
{
  initlock(&kmem.lock, "kmem");
  kinit_freeing = 1;
  freerange(end, (void *)PHYSTOP);
  kinit_freeing = 0;
}

void
freerange(void *pa_start, void *pa_end)
{
  char *p;
  p = (char *)PGROUNDUP((uint64)pa_start);
  for (; p + PGSIZE <= (char *)pa_end; p += PGSIZE)
    kfree(p);
}

// Free the page of physical memory pointed at by pa,
// which normally should have been returned by a
// call to kalloc().  (The exception is when
// initializing the allocator; see kinit above.)
void
kfree(void *pa)
{
  struct run *r;

  if (((uint64)pa % PGSIZE) != 0 || (char *)pa < end || (uint64)pa >= PHYSTOP)
    panic("kfree");

  // Fill with junk to catch dangling refs. See KFREE_POISON above; also
  // always skipped while kinit() builds the initial free list, since those
  // pages have never been allocated and so cannot be dangling references.
  if (KFREE_POISON && !kinit_freeing)
    memset(pa, 1, PGSIZE);

  r = (struct run *)pa;

  acquire(&kmem.lock);
  r->next = kmem.freelist;
  kmem.freelist = r;
  release(&kmem.lock);
}

// Allocate one 4096-byte page of physical memory.
// Returns a pointer that the kernel can use.
// Returns 0 if the memory cannot be allocated.
void *
kalloc(void)
{
  struct run *r;

  acquire(&kmem.lock);
  r = kmem.freelist;
  if (r)
    kmem.freelist = r->next;
  release(&kmem.lock);

  // Rocket port: upstream does memset((char *)r, 5, PGSIZE) here to catch
  // reads of uninitialised memory. It is dropped because it cannot actually
  // catch anything: every caller in this kernel overwrites the whole page
  // before reading it -- walk(), uvmcreate(), uvmalloc() and vmfault() all
  // memset(0) immediately, and uvmcopy() memmove()s over it. The poison is
  // destroyed before it can be observed, so it is pure DRAM traffic. See
  // KFREE_POISON above for the cost.
  return (void *)r;
}
