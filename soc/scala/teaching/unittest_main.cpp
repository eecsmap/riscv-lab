// M1-b: Verilator main for freechips.rocketchip.unittest.TestHarness (io_success only).
#include "VTestHarness.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
int main(int argc, char** argv) {
  Verilated::commandArgs(argc, argv);
  long max_cycles = 2000000;
  for (int i = 1; i < argc; i++)
    if (!strncmp(argv[i], "+max-cycles=", 12)) max_cycles = atol(argv[i] + 12);
  VTestHarness top;
  top.reset = 1; top.clock = 0;
  for (int i = 0; i < 20; i++) { top.clock = !top.clock; top.eval(); }
  top.reset = 0;
  long cycles = 0;
  while (!Verilated::gotFinish() && !top.io_success && cycles < max_cycles) {
    top.clock = 1; top.eval();
    top.clock = 0; top.eval();
    cycles++;
  }
  top.final();
  if (top.io_success) { printf("UNITTEST SUCCESS after %ld cycles\n", cycles); return 0; }
  if (Verilated::gotFinish()) { printf("UNITTEST STOPPED (assertion/$finish) after %ld cycles\n", cycles); return 1; }
  printf("UNITTEST TIMEOUT after %ld cycles\n", cycles); return 2;
}
