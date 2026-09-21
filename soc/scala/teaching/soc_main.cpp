// M1-a: Verilator main for zynq.TestHarness (the legacy fpga-zynq simulation harness).
// Same structure as testchipip/csrc/verilator-harness.cc, but it includes the generated model header
// itself instead of relying on -include (Verilator 5's precompiled headers conflict with that flag).
#include "VTestHarness.h"
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
bool verbose = false;       // referenced by PRINTF_COND
bool done_reset = false;    // referenced by PRINTF_COND / STOP_COND

double sc_time_stamp() { return trace_count; }
static void handle_sigterm(int sig) { if (tsi) tsi->stop(); }

int main(int argc, char** argv) {
  unsigned random_seed = (unsigned)time(NULL) ^ (unsigned)getpid();
  uint64_t max_cycles = (uint64_t)-1;
  for (int i = 1; i < argc; i++) {
    if (!strncmp(argv[i], "+max-cycles=", 12)) max_cycles = atoll(argv[i] + 12);
    else if (!strcmp(argv[i], "+verbose")) verbose = true;
    else if (!strncmp(argv[i], "-s", 2)) random_seed = atoi(argv[i] + 2);
  }
  srand(random_seed); srand48(random_seed);
  Verilated::randReset(2);
  Verilated::commandArgs(argc, argv);   // SimSerial.cc reads the target ELF and +blkdev= from here
  VTestHarness* tile = new VTestHarness;
  signal(SIGTERM, handle_sigterm);

  // Assertions are gated on Verilated::assertOn() (STOP_COND): keep them off while reset is held, exactly
  // what rocket-chip's done_reset flag does. Using the Verilator API avoids an extra -include, which
  // Verilator 5's precompiled header rejects.
  Verilated::assertOn(false);
  for (int i = 0; i < 10; i++) { tile->reset = 1; tile->clock = 0; tile->eval(); tile->clock = 1; tile->eval(); }
  tile->reset = 0; done_reset = true;
  Verilated::assertOn(true);

  while ((!tsi || !tsi->done()) && !tile->io_success && trace_count < max_cycles) {
    tile->clock = 0; tile->eval();
    tile->clock = 1; tile->eval();
    trace_count++;
  }
  tile->final();

  int ret = 0;
  if (tsi && tsi->exit_code()) {
    fprintf(stderr, "*** FAILED *** (code = %d, seed %u) after %ld cycles\n", tsi->exit_code(), random_seed, (long)trace_count);
    ret = tsi->exit_code();
  } else if (trace_count >= max_cycles) {
    fprintf(stderr, "*** FAILED *** (timeout, seed %u) after %ld cycles\n", random_seed, (long)trace_count);
    ret = 2;
  } else {
    fprintf(stderr, "Completed after %ld cycles\n", (long)trace_count);
  }
  delete tile;
  return ret;
}
