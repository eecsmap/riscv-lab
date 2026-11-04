// Step 5: Verilator main for the RD2 boot harness (RD2Harness.RD2BootConfig), driven by fesvr over TSI.
//
// The host (fesvr) loads the ELF into DRAM through the serial adapter, writes the CLINT's msip to wake the core
// out of the boot ROM's wfi loop, and serves the HTIF console: every byte the program sends through tohost is
// printed on stdout. The run ends when the program writes its exit code to tohost.
//   sim [+max-cycles=N] [+drain-limit=N] [-sSEED] prog.elf
#include "VRD2Harness.h"
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
static void handle_sigterm(int) { if (tsi) tsi->stop(); }

int main(int argc, char** argv) {
  unsigned random_seed = (unsigned)time(NULL) ^ (unsigned)getpid();
  uint64_t max_cycles = 3000000, drain_limit = 2000;
  for (int i = 1; i < argc; i++) {
    if (!strncmp(argv[i], "+max-cycles=", 12)) max_cycles = atoll(argv[i] + 12);
    else if (!strncmp(argv[i], "+drain-limit=", 13)) drain_limit = atoll(argv[i] + 13);
    else if (!strcmp(argv[i], "+verbose")) verbose = true;
    else if (!strncmp(argv[i], "-s", 2)) random_seed = atoi(argv[i] + 2);
  }
  srand(random_seed); srand48(random_seed);
  Verilated::randReset(2);
  Verilated::commandArgs(argc, argv);
  VRD2Harness* tile = new VRD2Harness;
  signal(SIGTERM, handle_sigterm);

  // harness reset with the bus monitors off: before it drops, registers hold random values
  Verilated::assertOn(false);
  for (int i = 0; i < 10; i++) { tile->reset = 1; tile->clock = 0; tile->eval(); tile->clock = 1; tile->eval(); }
  tile->reset = 0; done_reset = true;
  Verilated::assertOn(true);
  printf("EVH %lu ASSERTS armed\n", (unsigned long)trace_count + 1);

  bool host_done = false, settled = false;
  uint64_t host_done_cycle = 0, drained = 0;
  while (trace_count < max_cycles) {
    tile->clock = 0; tile->eval();
    tile->clock = 1; tile->eval();
    trace_count++;
    if (!host_done && ((tsi && tsi->done()) || tile->io_success)) {
      host_done = true; host_done_cycle = trace_count;
      printf("EVH %lu HOSTDONE exit_code=%d busy=%d\n", (unsigned long)trace_count,
             tsi ? tsi->exit_code() : -1, (int)tile->io_busy);
    }
    if (host_done) {
      // let the CPU finish what it has in flight (normally the exit store's response) before stopping
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
    fprintf(stderr, "*** FAILED *** (no host result after %lu cycles: the program never wrote its exit code)\n",
            (unsigned long)trace_count);
    ret = 2;
  } else if (!settled) {
    fprintf(stderr, "*** FAILED *** (a CPU transaction was still in flight %lu cycles after the host result)\n",
            (unsigned long)drained);
    ret = 3;
  } else if (tsi && tsi->exit_code()) {
    fprintf(stderr, "*** FAILED *** (exit code %d) after %lu cycles\n", tsi->exit_code(), (unsigned long)trace_count);
    ret = tsi->exit_code();
  } else {
    fprintf(stderr, "Completed after %lu cycles\n", (unsigned long)trace_count);
  }
  delete tile;
  return ret;
}
