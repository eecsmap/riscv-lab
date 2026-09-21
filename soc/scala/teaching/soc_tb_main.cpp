// M1 integration: Verilator main for teaching.TeachingSocHarness (done / failed straight out).
// exit 0 = done && !failed; 1 = done && failed; 2 = timeout. Chisel assertions abort on their own (SIGABRT).
#include "VTeachingSocHarness.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  long max_cycles = 4000000;
  for (int i = 1; i < argc; i++)
    if (!strncmp(argv[i], "+max-cycles=", 12)) max_cycles = atol(argv[i] + 12);
  VTeachingSocHarness top;
  top.reset = 1; top.clock = 0;
  for (int i = 0; i < 20; i++) { top.clock = !top.clock; top.eval(); }
  top.reset = 0;
  long cycles = 0;
  // io_done is a pulse (the tester re-uses a small counter), so latch the observation rather than sampling it
  // again after the loop -- reading it later reports a spurious timeout.
  bool saw_done = false, saw_failed = false;
  while (!Verilated::gotFinish() && cycles < max_cycles) {
    top.clock = 1; top.eval();
    top.clock = 0; top.eval();
    cycles++;
    if (top.io_done) { saw_done = true; if (top.io_failed) saw_failed = true; break; }
  }
  // let the done-cycle printfs retire
  for (int i = 0; i < 8; i++) {
    top.clock = 1; top.eval(); top.clock = 0; top.eval();
    if (top.io_done) { saw_done = true; if (top.io_failed) saw_failed = true; }
  }
  top.final();
  if (!saw_done) { printf("SOCTB TIMEOUT after %ld cycles\n", cycles); return 2; }
  if (saw_failed) { printf("SOCTB FAILED after %ld cycles\n", cycles); return 1; }
  printf("SOCTB PASS after %ld cycles\n", cycles);
  return 0;
}
