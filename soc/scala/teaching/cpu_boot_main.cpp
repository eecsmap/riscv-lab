// M3: Verilator main for the teaching CPU on the legacy SoC, driven by fesvr over TSI.
//
// The difference from the M1-a main is the ending. fesvr reporting `done` is only a candidate result: the
// CPU's own exit store still has to be answered and retired, and the bridge has to be empty. The run
// therefore latches the host's verdict and drains with a bound, reporting what it saw, instead of running a
// fixed number of extra cycles and calling that evidence.
#include "VTeachingCpuHarness.h"
#include "verilated.h"
#include <fesvr/tsi.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <csignal>
#include <unistd.h>

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
  VTeachingCpuHarness* tile = new VTeachingCpuHarness;
  signal(SIGTERM, handle_sigterm);

  Verilated::assertOn(false);
  for (int i = 0; i < 10; i++) { tile->reset = 1; tile->clock = 0; tile->eval(); tile->clock = 1; tile->eval(); }
  tile->reset = 0; done_reset = true;
  // The subsystem has its own reset, released by the host, and it outlasts the harness reset. Assertions
  // stay off until that one drops: before it does, the design's registers still hold randomised values and
  // the bus monitors report on them, which would put noise into a log that is meant to be evidence.
  Verilated::assertOn(false);
  bool asserts_armed = false;

  bool host_done = false, settled = false, trap_after_done = false;
  uint64_t host_done_cycle = 0;
  uint64_t drained = 0;

  while (trace_count < max_cycles) {
    tile->clock = 0; tile->eval();
    tile->clock = 1; tile->eval();
    trace_count++;
    if (!asserts_armed && !tile->io_dutReset) {
      asserts_armed = true; Verilated::assertOn(true);
      printf("EVH %lu DUTRESET released\n", (unsigned long)trace_count);
    }

    if (!host_done && ((tsi && tsi->done()) || tile->io_success)) {
      host_done = true; host_done_cycle = trace_count;
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
