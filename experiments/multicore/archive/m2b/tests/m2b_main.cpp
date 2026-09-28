// RD2: Verilator main for the experimental split-domain SoC, driven by fesvr over TSI.
//
// Derived verbatim from teaching/cpu_boot_main.cpp (which is left untouched) with two changes, both of them
// consequences of the split: the harness type is RD2Harness, and `io_dutReset` no longer means "the whole
// subsystem is in reset" -- it is the CPU's soft-reset request, while the fabric has been running on the
// cold reset since time zero. Assertions are therefore armed once the *cold* reset is released rather than
// waiting for sys_reset to drop, which is the point of the design: TSI loading happens while the CPU is
// held, so waiting for that signal would arm them too late.
// the harness type comes from the build, so the same main drives the split-domain harness and the
// legacy-reset comparison harness without a second copy
#ifndef HARNESS_HEADER
#define HARNESS_HEADER "VRD2Harness.h"
#define HARNESS_TYPE VRD2Harness
#endif
#include HARNESS_HEADER
#include "verilated.h"
// MC-M2b: this copy of rd2_boot_main.cpp (reset-drain/rd2/src, read-only) adds the per-hart evidence the
// dual harness exposes: retired instructions, traps, last cause, max A-wait, epoch -- per hart, printed at the
// end (HARTS ...) and in every PROGRESS line. M2B_NHARTS is the harness's hart count (from the build).
#ifndef M2B_NHARTS
#define M2B_NHARTS 1
#endif
#if M2B_NHARTS >= 2
#define M2B_H1(expr) expr
#else
#define M2B_H1(expr) 0
#endif
#include <fesvr/tsi.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <csignal>
#include <unistd.h>

// the host-side restart hook (see rd2_tsi.h): the simulation loop raises the request, fesvr performs the
// reload and the wake in its own context
extern volatile bool rd2_restart_request;
extern volatile int  rd2_restart_done;

extern tsi_t* tsi;          // created by testchipip/csrc/SimSerial.cc on the first DPI tick
static uint64_t trace_count = 0;
bool verbose = false;
bool done_reset = false;

double sc_time_stamp() { return trace_count; }
static void handle_sigterm(int sig) { if (tsi) tsi->stop(); }

int main(int argc, char** argv) {
  unsigned random_seed = (unsigned)time(NULL) ^ (unsigned)getpid();
  uint64_t max_cycles = (uint64_t)-1;
  uint64_t drain_limit = 2000;        // bounded, and a failure if it is not enough
  for (int i = 1; i < argc; i++) {
    if (!strncmp(argv[i], "+max-cycles=", 12)) max_cycles = atoll(argv[i] + 12);
    else if (!strncmp(argv[i], "+drain-limit=", 13)) drain_limit = atoll(argv[i] + 13);
    else if (!strcmp(argv[i], "+verbose")) verbose = true;
    else if (!strncmp(argv[i], "-s", 2)) random_seed = atoi(argv[i] + 2);
  }
  srand(random_seed); srand48(random_seed);
  Verilated::randReset(2);
  Verilated::commandArgs(argc, argv);
  HARNESS_TYPE* tile = new HARNESS_TYPE;
  signal(SIGTERM, handle_sigterm);

  Verilated::assertOn(false);
  for (int i = 0; i < 10; i++) { tile->reset = 1; tile->clock = 0; tile->eval(); tile->clock = 1; tile->eval(); }
  tile->reset = 0; done_reset = true;
  // The subsystem has its own reset, released by the host, and it outlasts the harness reset. Assertions
  // stay off until that one drops: before it does, the design's registers still hold randomised values and
  // the bus monitors report on them, which would put noise into a log that is meant to be evidence.
  Verilated::assertOn(false);
  bool asserts_armed = false;
  bool cpu_released = false;

  // ---- the restart protocol, driven from here exactly as the PS drives it on the board ---------------
  //   +rd2_restart_at=<cycle>    the cycle at which the first restart is started (0 = never)
  //   +rd2_restart_rounds=<n>    how many restarts to perform
  //   +rd2_restart_gap=<cycles>  how long to let the program run again before the next one
  // Order per round: assert the CPU's soft reset -> wait for the design to report CPU_RESTART_SAFE ->
  // release it -> ask the host to clear tohost/fromhost, reload the ELF and write msip. Nothing is
  // cold-reset, no simulator state is recreated, and the fabric, the DRAM model and the PS-side FIFOs keep
  // running throughout.
  long restart_at = 0, restart_rounds = 0, restart_gap = 4000, restart_when = 0;
  long progress_every = 0;
  unsigned long last_trap_count = 0, trap_head = 400;   // how many traps are printed in full
  for (int i = 1; i < argc; i++) {
    if (!strncmp(argv[i], "+rd2_restart_at=", 16)) restart_at = atoll(argv[i] + 16);
    else if (!strncmp(argv[i], "+rd2_restart_rounds=", 20)) restart_rounds = atoll(argv[i] + 20);
    else if (!strncmp(argv[i], "+rd2_restart_gap=", 17)) restart_gap = atoll(argv[i] + 17);
    // 0: at the cycle; 3: at the cycle *and* only once the block device has a request in flight, so the
    // reset lands on a master the CPU does not control
    else if (!strncmp(argv[i], "+rd2_restart_when=", 18)) restart_when = atoll(argv[i] + 18);
    else if (!strncmp(argv[i], "+rd2_progress=", 14)) progress_every = atoll(argv[i] + 14);
    else if (!strncmp(argv[i], "+rd2_trap_head=", 15)) trap_head = atoll(argv[i] + 15);
  }
  // +rd2_reload_after_inject=1: the *hardware* injector chooses the moment (it can watch conditions the
  // host cannot see, such as "a write is offered and not yet accepted"), and the host does its half --
  // reload and re-wake -- once that reset has been released. Without this, a scenario aimed at a precise
  // in-flight condition ends with the CPU parked in the ROM's wake loop and no result.
  // +rboot=1: the host waits for BOOT_RESTART_READY (bit 4) instead of CPU_RESTART_SAFE before releasing,
  // and stops -- never releases, never reloads -- if BOOT_RESTART_TIMEOUT is reported. See DESIGN.md.
  long rboot = 0; bool rboot_timeout_seen = false;
  for (int i = 1; i < argc; i++) if (!strncmp(argv[i], "+rboot=", 7)) rboot = atoll(argv[i] + 7);
  long reload_after_inject = 0;
  for (int i = 1; i < argc; i++)
    if (!strncmp(argv[i], "+rd2_reload_after_inject=", 25)) reload_after_inject = atoll(argv[i] + 25);
  unsigned prev_injections = 0;
  bool reload_pending = false;

  int restarts_started = 0;
  enum { R_IDLE, R_HELD, R_WAIT_HOST, R_FAILED } rstate = R_IDLE;
  uint64_t next_restart = restart_at;
  tile->io_hostSoftReset = 0;

  bool host_done = false, settled = false, trap_after_done = false;
  uint64_t host_done_cycle = 0;
  uint64_t drained = 0;

  while (trace_count < max_cycles) {
    tile->clock = 0; tile->eval();
    tile->clock = 1; tile->eval();
    trace_count++;
    // the fabric left cold reset before the loop started; arm immediately, and report the CPU's own
    // release separately so the log still shows when the host let the CPU go
    if (!asserts_armed) {
      asserts_armed = true; Verilated::assertOn(true);
      printf("EVH %lu ASSERTS armed (cold reset released; cpu soft reset=%d)\n",
             (unsigned long)trace_count, (int)tile->io_dutReset);
    }
    if (!cpu_released && !tile->io_dutReset) {
      cpu_released = true;
      printf("EVH %lu CPURESET released restart_safe=%d\n",
             (unsigned long)trace_count, (int)tile->io_restartSafe);
    }

    if (reload_after_inject) {
      unsigned inj = (unsigned)tile->io_injections;
      if (inj > prev_injections) { prev_injections = inj; reload_pending = true; }
      if (reload_pending && !tile->io_softResetEff && tile->io_restartSafeLevel == 0) {
        // the injector has released it and the CPU is running again on the ROM: put the program back
        reload_pending = false;
        rd2_restart_request = true;
        printf("RD2HOST %lu RELOAD_AFTER_INJECT injections=%u\n", (unsigned long)trace_count, inj);
      }
    }

    // ---- the restart state machine ------------------------------------------------------------------
    if (restart_rounds > 0 && !host_done) {
      // 3: the block device is busy -- a tracker mid-DMA counts even when it is waiting on the host and has
      // nothing on the bus, which is what a stuck device looks like
      // 5: a disk WRITE has been accepted by a tracker and has not completed. A read and a write both
      // make the device busy, so condition 3 cannot say which operation a restart lands on; this one can,
      // and the assertion below records the direction and sector it actually caught.
      // 6: the same for a READ -- used by the negative that shows a read cannot satisfy the write criterion.
      bool cond = (restart_when == 3) ? tile->io_bdevBusy
                : (restart_when == 4) ? (tile->io_bdevQueued != 0 && !tile->io_bdevOutstanding)
                : (restart_when == 5) ? (bool)tile->io_bdevWriteInflight
                : (restart_when == 6) ? (bool)tile->io_bdevReadInflight
                : true;
      if (rstate == R_IDLE && restarts_started < restart_rounds && next_restart &&
          trace_count >= next_restart && cond) {
        tile->io_hostSoftReset = 1; rstate = R_HELD;
        // the operation the hold actually caught, so "a write was in flight at the hold" is recorded
        // rather than assumed; restart_at is only the earliest cycle the arm may fire, not the hold time
        printf("RD2HOST %lu RESET_ASSERT round=%d bdev_busy=%d write_inflight=%d read_inflight=%d "
               "write_sector=%u arm_at=%ld\n",
               (unsigned long)trace_count, restarts_started + 1, (int)tile->io_bdevBusy,
               (int)tile->io_bdevWriteInflight, (int)tile->io_bdevReadInflight,
               (unsigned)tile->io_bdevWriteSector, next_restart);
      } else if (rstate == R_HELD && rboot && tile->io_bootRestartTimeout) {
        // latched on the host side too: from here on no READY, however late, releases or reloads anything
        rstate = R_FAILED; rboot_timeout_seen = true;
        printf("RD2HOST %lu RBOOT_TIMEOUT: the block device did not drain by the deadline; the reset stays "
               "held and the program is not reloaded -- recovery is a cold platform reset\n",
               (unsigned long)trace_count);
      } else if (rstate == R_FAILED) {
        if (tile->io_bootRestartReady) printf("RD2HOST %lu READY_AFTER_TIMEOUT_IGNORED\n", (unsigned long)trace_count);
      } else if (rstate == R_HELD && (rboot ? tile->io_bootRestartReady : tile->io_restartSafeLevel)) {
        // released only because the design says the CPU can be restarted -- no timer anywhere in here
        tile->io_hostSoftReset = 0; rstate = R_WAIT_HOST;
        rd2_restart_request = true;
        printf("RD2HOST %lu RESET_RELEASE round=%d restart_safe=%d boot_ready=%d pending_work=%d\n",
               (unsigned long)trace_count, restarts_started + 1, (int)tile->io_restartSafeLevel,
               (int)tile->io_bootRestartReady, (int)tile->io_pendingWork);
      } else if (rstate == R_WAIT_HOST && rd2_restart_done > restarts_started) {
        restarts_started++; rstate = R_IDLE;
        next_restart = trace_count + restart_gap;
        printf("RD2HOST %lu RELOADED round=%d (next at %lu)\n",
               (unsigned long)trace_count, restarts_started, (unsigned long)next_restart);
      }
    }

    // the trap history, capped: every trap for the first `trap_head` of them, then one in every 100000.
    // An OS that falls into a fault loop is diagnosed from the *first* trap of the loop and what preceded
    // it, which a periodic sample cannot show.
    if (progress_every) {
      unsigned long nt = (unsigned long)tile->io_obsTraps;
      if (nt != last_trap_count) {
        if (nt <= trap_head || (nt % 100000) == 0) {
          printf("EVH %lu TRAP n=%lu cause=0x%lx epc=0x%lx tval=0x%lx pc=0x%lx\n",
                 (unsigned long)trace_count, nt, (unsigned long)tile->io_obsTrapCause,
                 (unsigned long)tile->io_obsTrapEpc, (unsigned long)tile->io_obsTrapTval,
                 (unsigned long)tile->io_obsPc);
          fflush(stdout);
        }
        last_trap_count = nt;
      }
    }
    // +rd2_progress=N: every N cycles, one line with the CPU's PC and how many instructions have retired.
    // An OS boot runs for tens of millions of cycles, where a per-cycle trace is unusable; this keeps the
    // run diagnosable (where is it, is it still retiring?) at a few dozen bytes per million cycles.
    if (progress_every && trace_count && (trace_count % progress_every == 0)) {
      printf("EVH %lu PROGRESS pc=0x%lx retired=%lu busy=%d traps=%lu cause=0x%lx epc=0x%lx tval=0x%lx"
             " r0=%lu pc0=0x%lx r1=%lu pc1=0x%lx\n",
             (unsigned long)trace_count,
             (unsigned long)tile->io_obsPc, (unsigned long)tile->io_obsRetired, (int)tile->io_busy,
             (unsigned long)tile->io_obsTraps, (unsigned long)tile->io_obsTrapCause,
             (unsigned long)tile->io_obsTrapEpc, (unsigned long)tile->io_obsTrapTval,
             (unsigned long)tile->io_obsRetiredH_0, (unsigned long)tile->io_obsPcH_0,
             (unsigned long)M2B_H1(tile->io_obsRetiredH_1), (unsigned long)M2B_H1(tile->io_obsPcH_1));
      fflush(stdout);
    }
    if (!host_done && ((tsi && tsi->done()) || tile->io_success)) {
      host_done = true; host_done_cycle = trace_count;
      // which of the two ended the run, so "the host declared a result" is never ambiguous
      printf("EVH %lu HOSTDONE_WHY tsi_done=%d io_success=%d tsi_exit=%d\n",
             (unsigned long)trace_count, (int)(tsi && tsi->done()), (int)tile->io_success,
             tsi ? tsi->exit_code() : -1);
      // whether the CPU still had work in flight at the moment the host declared a result: this is what
      // separates "the host saw tohost" from "the CPU finished"
      printf("EVH %lu HOSTDONE exit_code=%d busy=%d\n", (unsigned long)trace_count,
             tsi ? tsi->exit_code() : -1, (int)tile->io_busy);
    }
    if (host_done) {
      // Drain until the CPU has nothing in flight. Instruction fetches that continue afterwards are normal
      // -- the program spins after its exit store -- so the condition is "no outstanding transaction", not
      // "the bus went quiet". The bound below is a safety net, not the evidence: whether the exit store was
      // answered and retired is read out of the event log by the checker.
      drained++;
      if (!tile->io_busy) { settled = true; printf("EVH %lu SETTLED after %lu cycles\n",
                                                   (unsigned long)trace_count, (unsigned long)drained); break; }
      if (drained >= drain_limit) break;
      if (tile->io_halted) { printf("EVH %lu HALTED\n", (unsigned long)trace_count); break; }
    }
  }
  fflush(stdout);
  tile->final();

  printf("AXI ar=%u r=%u rlast=%u aw=%u w=%u wlast=%u b=%u\n",
         tile->io_axi_ar, tile->io_axi_r, tile->io_axi_rlast,
         tile->io_axi_aw, tile->io_axi_w, tile->io_axi_wlast, tile->io_axi_b);
  printf("RD2HOST restarts_requested=%d restarts_completed=%d\n", restarts_started, rd2_restart_done);
  // the end-of-run state of the CPU master, so a claim like "this master was never back-pressured" is
  // measured when the run ends rather than at whatever cycle the last reset round happened to print
  printf("RD2HOST FINAL aWaits=%u aFires=%u dFires=%u epoch=%u injections=%u boot_ready=%d "
         "boot_timeout=%d bdev_queued=%u\n",
         (unsigned)tile->io_aWaits, (unsigned)tile->io_aFires, (unsigned)tile->io_dFires,
         (unsigned)tile->io_epoch, (unsigned)tile->io_injections, (int)tile->io_bootRestartReady,
         (int)tile->io_bootRestartTimeout, (unsigned)tile->io_bdevQueued);
  // MC-M2b: per-hart totals. "retired" counts commits seen by the harness on that hart's observation port.
  printf("HARTS n=%d retired0=%lu traps0=%lu cause0=0x%lx maxawait0=%u awaits0=%u epoch0=%u"
         " retired1=%lu traps1=%lu cause1=0x%lx maxawait1=%u awaits1=%u epoch1=%u\n", M2B_NHARTS,
         (unsigned long)tile->io_obsRetiredH_0, (unsigned long)tile->io_obsTrapsH_0, (unsigned long)tile->io_obsTrapCauseH_0,
         (unsigned)tile->io_maxAWaitH_0, (unsigned)tile->io_aWaitsH_0, (unsigned)tile->io_epochH_0,
         (unsigned long)M2B_H1(tile->io_obsRetiredH_1), (unsigned long)M2B_H1(tile->io_obsTrapsH_1), (unsigned long)M2B_H1(tile->io_obsTrapCauseH_1),
         (unsigned)M2B_H1(tile->io_maxAWaitH_1), (unsigned)M2B_H1(tile->io_aWaitsH_1), (unsigned)M2B_H1(tile->io_epochH_1));
  printf("CYCLES total=%lu host_done_at=%lu drained=%lu\n",
         (unsigned long)trace_count, (unsigned long)host_done_cycle, (unsigned long)drained);

  int ret = 0;
  if (!host_done) {
    fprintf(stderr, "*** FAILED *** (no host result, seed %u) after %ld cycles\n", random_seed, (long)trace_count);
    ret = 2;
  } else if (trap_after_done) {
    fprintf(stderr, "*** FAILED *** (a trap was taken after the host reported a result)\n");
    ret = 4;
  } else if (!settled) {
    fprintf(stderr, "*** FAILED *** (a CPU transaction was still in flight %lu cycles after the host result)\n",
            (unsigned long)drained);
    ret = 3;
  } else if (tsi && tsi->exit_code()) {
    fprintf(stderr, "*** FAILED *** (code = %d, seed %u) after %ld cycles\n", tsi->exit_code(), random_seed, (long)trace_count);
    ret = tsi->exit_code();
  } else {
    fprintf(stderr, "Completed after %ld cycles\n", (long)trace_count);
  }
  delete tile;
  return ret;
}
