//
// HTIF console for xv6 on a Rocket Chip core reached over testchipip's TSI
// link (fpga-zynq / PYNQ-Z1).
//
// Drop-in replacement for uart.c: this Rocket configuration has no NS16550
// at 0x10000000. The only console is the HTIF channel that fesvr-zynq
// already polls on the ARM side, so console traffic rides that instead.
//
// Protocol (see riscv-fesvr fesvr/htif.cc and fesvr/device.cc):
//
//   tohost   = (device << 56) | (cmd << 48) | payload
//
//   The *host* signals it consumed a command by writing 0 back to tohost,
//   so the target waits for tohost == 0 rather than for a fromhost reply.
//   That distinction matters: bcd_t::handle_write() never calls respond(),
//   so a console write produces NO fromhost reply. Waiting on fromhost
//   after a putc would hang forever.
//
//   The host writes fromhost only when it reads as 0, so the target must
//   zero it after consuming a reply or the host stalls.
//
//   device 1 (bcd) cmd 1 = write, payload = character
//   device 1 (bcd) cmd 0 = read, reply arrives in fromhost as (0x100 | ch)
//
#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "spinlock.h"
#include "proc.h"
#include "defs.h"

// fesvr locates these two by symbol name in the kernel ELF. They must keep
// these exact names and must live in memory the host can reach: xv6's kernel
// mapping is an identity map of KERNBASE upward, so a kernel global's virtual
// address equals its physical address, which is what HTIF needs.
volatile uint64 tohost __attribute__((aligned(64)));
volatile uint64 fromhost __attribute__((aligned(64)));

#define HTIF_DEV_BCD   1UL
#define HTIF_CMD_READ  0UL
#define HTIF_CMD_WRITE 1UL

static struct spinlock htif_tx_lock;
#ifdef TEACHING_HTIF_RACE_TEST
volatile int htif_race_readers, htif_race_consumed, htif_race_window;   // see htif_race_test() below
#endif

// Is a console read request already outstanding? Only one HTIF command may
// be in flight at a time, so we must not queue a second read before the
// first is answered.
static int read_pending;

static void
htif_send(uint64 dev, uint64 cmd, uint64 payload)
{
  // Wait for any previous command to be consumed by the host.
  while (tohost != 0)
    ;
  tohost = (dev << 56) | (cmd << 48) | (payload & 0xffffffffffffUL);
  // Wait for this one to be consumed too, so callers get simple ordering.
  while (tohost != 0)
    ;
}

void
uartinit(void)
{
  initlock(&htif_tx_lock, "htif");
  read_pending = 0;
}

// Blocking, lock-free single character out. Used by printk and by the
// console for echo, including from panic paths where locks may be held.
void
uartputc_sync(int c)
{
  htif_send(HTIF_DEV_BCD, HTIF_CMD_WRITE, (uint64)(c & 0xff));
}

// xv6 has no interrupt-driven path here: HTIF has no interrupt line, so
// there is no "async" mode to defer to. Writing straight through keeps the
// console correct at the cost of being slow, which is fine for bring-up.
void
uartwrite(char buf[], int n)
{
  acquire(&htif_tx_lock);
  for (int i = 0; i < n; i++)
    htif_send(HTIF_DEV_BCD, HTIF_CMD_WRITE, (uint64)(buf[i] & 0xff));
  release(&htif_tx_lock);
}

// Non-blocking: returns -1 when no character is ready.
//
// Issues a read request and picks up the answer on a later call, so this
// never blocks the caller waiting on a human.
static int
htif_getc(void)
{
  uint64 fh = fromhost;

  if (fh != 0) {
#ifdef TEACHING_HTIF_RACE_TEST
    if (htif_race_window) {      // test only: hold the word between the read and the clear
      __sync_fetch_and_add(&htif_race_readers, 1);
      for (volatile int i = 0; i < 4000; i++)
        ;
    }
#endif
    fromhost = 0;               // let the host queue the next reply
    read_pending = 0;
#ifdef TEACHING_HTIF_RACE_TEST
    if (fh == (0x100 | 0x15))
      __sync_fetch_and_add(&htif_race_consumed, 1);
#endif
    if (fh & 0x100)             // 0x100 marks a valid character
      return (int)(fh & 0xff);
    return -1;
  }

  if (!read_pending) {
    htif_send(HTIF_DEV_BCD, HTIF_CMD_READ, 0);
    read_pending = 1;
  }
  return -1;
}

// Called from the timer tick (see trap.c) rather than from a device
// interrupt, since HTIF cannot raise one.
void
uartintr(void)
{
  int c;

  while ((c = htif_getc()) != -1) {
    consoleintr(c);
  }
}

// MC-M3: the ONE consumer of fromhost. Every hart's timer tick calls this; only hart 0 polls. Callers hold
// interrupts off (a trap handler), which cpuid() requires.
void
htif_poll(void)
{
  if (cpuid() == 0)
    uartintr();
}

#ifdef TEACHING_HTIF_RACE_TEST
// A controlled input race, run once at boot by BOTH harts (see main.c), on a TEST kernel only.
//   hart 0 plants a character in fromhost (Ctrl-U, which consoleintr handles without leaving anything in
//   the input buffer) and opens a window in htif_getc between the read and the clear; both harts arrive at a
//   barrier and then run the poll path under test in the same window. The number of harts that saw the
//   planted word and the number that consumed it are counted.
//   Fixed path (htif_poll): only hart 0 polls -> consumed = 1 whatever the window.
//   TEACHING_HTIF_RACE_NEG: every hart polls (the old scheme) -> both read the word inside the window ->
//   consumed = 2. The negative build proves the window is real and the test can see a double consumption.
static volatile int race_arrive, race_done;
void
htif_race_test(void)
{
  int id = cpuid();
  if (id == 0) {
    htif_race_window = 1;
    fromhost = 0x100 | 0x15;
    __sync_synchronize();
  }
  __sync_fetch_and_add(&race_arrive, 1);
  while (race_arrive < 2)
    ;
#ifdef TEACHING_HTIF_RACE_NEG
  uartintr();                     // the OLD scheme: every hart polls
#else
  htif_poll();                    // the fixed scheme: one consumer
#endif
  __sync_fetch_and_add(&race_done, 1);
  while (race_done < 2)
    ;
  if (id == 0) {
    htif_race_window = 0;
    printk("HTIF-RACE-TEST readers=%d consumed=%d expected=1 %s\n", htif_race_readers, htif_race_consumed,
           htif_race_consumed == 1 ? "OK" : "FAIL");
  }
}
#endif
