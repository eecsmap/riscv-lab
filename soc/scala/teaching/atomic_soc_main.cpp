// CPU-A stage 1: Verilator main for AtomicSocHarness (io_success only; +max-cycles). Same shape as unittest_main.cpp.
#include "VAtomicSocHarness.h"
#include "verilated.h"
#include <cstdio>
#include <cstring>
#include <cstdlib>
int main(int argc, char** argv) {
  long max_cycles = 1000000;
  for (int i = 1; i < argc; i++) if (!strncmp(argv[i], "+max-cycles=", 12)) max_cycles = atol(argv[i] + 12);
  Verilated::commandArgs(argc, argv);
  VAtomicSocHarness top;
  // printf/assert conditions are Verilated::assertOn() (as in the RD2 simulator): off during reset, on after
  Verilated::assertOn(false);
  top.reset = 1; top.clock = 0;
  for (int i = 0; i < 10; i++) { top.clock = 0; top.eval(); top.clock = 1; top.eval(); }
  top.reset = 0;
  Verilated::assertOn(true);
  long cycles = 0;
  while (!Verilated::gotFinish() && !top.io_success && cycles < max_cycles) {
    top.clock = 0; top.eval(); top.clock = 1; top.eval(); cycles++;
  }
  // a few more cycles so the harness's FINISHED line (printed on the edge after io_success rises) is emitted
  for (int i = 0; i < 4 && !Verilated::gotFinish(); i++) { top.clock = 0; top.eval(); top.clock = 1; top.eval(); }
  if (top.io_success) { printf("SOCTEST SUCCESS after %ld cycles\n", cycles); return 0; }
  if (Verilated::gotFinish()) { printf("SOCTEST STOPPED (assertion/$finish) after %ld cycles\n", cycles); return 1; }
  printf("SOCTEST TIMEOUT after %ld cycles\n", cycles); return 2;
}
