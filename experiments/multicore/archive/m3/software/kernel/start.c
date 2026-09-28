#include "types.h"
#include "param.h"
#include "memlayout.h"
#include "riscv.h"
#include "defs.h"

void main();
void timerinit();

// entry.S needs one stack per CPU.
__attribute__((aligned(16))) char stack0[4096 * NCPU];

// Rocket port: a scratch area per CPU for machine-mode timer interrupts.
uint64 timer_scratch[NCPU][6];

// assembly code in kernelvec.S for machine-mode timer interrupt.
extern void timervec();

// entry.S jumps here in machine mode on stack0.
void
start()
{
  // set M Previous Privilege mode to Supervisor, for mret.
  unsigned long x = r_mstatus();
  x &= ~MSTATUS_MPP_MASK;
  x |= MSTATUS_MPP_S;
  w_mstatus(x);

  // set M Exception Program Counter to main, for mret.
  // requires gcc -mcmodel=medany
  w_mepc((uint64)main);

  // disable paging for now.
  w_satp(0);

  // delegate all interrupts and exceptions to supervisor mode.
  w_medeleg(0xffff);
  w_mideleg(0xffff);
  // SIE_SSIE is needed on this port: timervec reflects the machine-mode
  // timer interrupt down as a supervisor *software* interrupt.
  w_sie(r_sie() | SIE_SEIE | SIE_STIE | SIE_SSIE);

  // configure Physical Memory Protection to give supervisor mode
  // access to all of physical memory.
#ifndef TEACHING_NO_PMP
  w_pmpaddr0(0x3fffffffffffffull);
  w_pmpcfg0(0xf);
#else
  // TEACHING_NO_PMP: the teaching core implements no PMP at all (zero entries),
  // so pmpaddr0/pmpcfg0 are illegal instructions there. With no PMP entries the
  // RISC-V privileged spec gives S and U full access to physical memory, which is
  // exactly what these two writes are asking for -- so omitting them changes no
  // permission, and nothing else in the port depends on them.
#endif

  // NOTE: upstream sets MENVCFG_ADUE here to get hardware updates of the
  // page-table A/D bits. This Rocket core has no menvcfg CSR at all (writing
  // it traps as an illegal instruction), so that is omitted -- see the
  // comment in timerinit() below.

  // ask for clock interrupts.
  timerinit();

  // keep each CPU's hartid in its tp register, for cpuid().
  int id = r_mhartid();
  w_tp(id);

  // switch to supervisor mode and jump to main().
  asm volatile("mret");
}

// Arrange to receive timer interrupts.
//
// Rocket port: upstream uses the Sstc extension (stimecmp) so timer
// interrupts arrive directly in supervisor mode. This core predates
// Sstc *and* menvcfg -- neither CSR exists, and writing one traps as an
// illegal instruction. So this is upstream's pre-92e60dd scheme: take the
// timer interrupt in machine mode at timervec (kernelvec.S), which rearms
// the CLINT and reflects it down as a supervisor software interrupt for
// devintr() in trap.c.
void
timerinit()
{
  // each CPU has a separate source of timer interrupts.
  int id = r_mhartid();

  // ask the CLINT for a timer interrupt.
  //
  // Rocket port: upstream uses 1000000, which is ~0.1s against QEMU's 10MHz
  // timebase. This SoC's CLINT runs at 1MHz (DTSTimebase in rocket-chip's
  // system Configs.scala), so 1000000 would be one tick per SECOND. That is
  // not just slow scheduling: uartintr() is driven off the tick here, and the
  // HTIF console allows only one outstanding read, so it also caps console
  // input at one keystroke per second.
  //
  // Measured: this SoC's CLINT mtime runs at 250kHz (the 25MHz Rocket clock
  // divided by 100), NOT the 1MHz that rocket-chip's DTSTimebase advertises
  // and not QEMU's 10MHz. 25000 cycles therefore gives ~10Hz.
  //
  // uartintr() is driven off this tick and each poll costs an HTIF round
  // trip, so the tick rate also sets the console input rate.
  int interval = 25000; // cycles -> ~10Hz at 250kHz
  *(uint64 *)CLINT_MTIMECMP(id) = *(uint64 *)CLINT_MTIME + interval;

  // prepare information in scratch[] for timervec.
  // scratch[0..2] : space for timervec to save registers.
  // scratch[3] : address of CLINT MTIMECMP register.
  // scratch[4] : desired interval (in cycles) between timer interrupts.
  // scratch[5] : address of CLINT MTIME (Rocket port: timervec rearms from
  //              the current time, not from the old compare value).
  uint64 *scratch = &timer_scratch[id][0];
  scratch[3] = CLINT_MTIMECMP(id);
  scratch[4] = interval;
  scratch[5] = CLINT_MTIME;
  w_mscratch((uint64)scratch);

  // set the machine-mode trap handler.
  w_mtvec((uint64)timervec);

  // enable machine-mode interrupts.
  w_mstatus(r_mstatus() | MSTATUS_MIE);

  // enable machine-mode timer interrupts.
  w_mie(r_mie() | MIE_MTIE);
}
