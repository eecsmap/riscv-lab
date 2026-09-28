#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

volatile static int started = 0;
volatile int ncpus_started = 0;   // MC-M3: harts that reached the scheduler (bounds the test-only pin() syscall)
#ifdef TEACHING_HTIF_RACE_TEST
volatile static int race_ready = 0;
void htif_race_test(void);
#endif

// start() jumps here in supervisor mode on all CPUs.
void
main()
{
  if (cpuid() == 0) {
    consoleinit();
    printkinit();
    printk("\n");
    printk("xv6 kernel is booting\n");
    printk("\n");
#ifdef TEACHING_HTIF_RACE_TEST
    __atomic_store_n(&race_ready, 1, __ATOMIC_RELEASE);
    htif_race_test();
#endif
    kinit();            // physical page allocator
    kvminit();          // create kernel page table
    kvminithart();      // turn on paging
    procinit();         // process table
    trapinit();         // trap vectors
    trapinithart();     // install kernel trap vector
    plicinit();         // set up interrupt controller
    plicinithart();     // ask PLIC for device interrupts
    binit();            // buffer cache
    iinit();            // inode table
    fileinit();         // file table
    // Rocket port: there is no virtio device at VIRTIO0 (0x10001000) on this
    // SoC -- probing it would fault, since nothing answers on the TileLink
    // bus at that address. The disk is testchipip's block device at
    // 0x10015000, backed by fesvr-zynq's +blkdev= file. See blkdev.c.
    blkdev_init();      // testchipip block device
    userinit();         // first user process

    __sync_fetch_and_add(&ncpus_started, 1);
    __atomic_store_n(&started, 1, __ATOMIC_RELEASE);
  } else {
#ifdef TEACHING_HTIF_RACE_TEST
    while (__atomic_load_n(&race_ready, __ATOMIC_ACQUIRE) == 0)
      ;
    htif_race_test();
#endif
    while (__atomic_load_n(&started, __ATOMIC_ACQUIRE) == 0)
      ;

    printk("hart %d starting\n", cpuid());
    kvminithart();  // turn on paging
    trapinithart(); // install kernel trap vector
    plicinithart(); // ask PLIC for device interrupts
    __sync_fetch_and_add(&ncpus_started, 1);
  }

  scheduler();
}
