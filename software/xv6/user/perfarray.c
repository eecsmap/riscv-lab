// MC-PERF array: fixed total work = PERF_CHILDREN x (size passes over a private 128 KiB uint64 array, stride 7 as in b0array).
// Memory traffic through each hart's TLB to the shared backend; each child owns its own array (independent address space).
// size (passes per child) defaults to 128; argv[1] overrides (short sims).
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "perflib.h"
#define N 16384
#define STRIDE 7
static uint64 a[N];
static unsigned long work(int idx, unsigned long passes) {
  int i, idx2 = 0; unsigned long p; uint64 sum = 0;
  for (i = 0; i < N; i++) a[i] = (uint64)i * 2654435761ULL + (uint64)idx;
  for (p = 0; p < passes; p++) for (i = 0; i < N; i++) { sum += a[idx2]; a[idx2] ^= sum >> 3; idx2 = (idx2 + STRIDE) % N; }
  return sum;
}
int main(int argc, char **argv) {
  unsigned long size = argc > 1 ? (unsigned long)atoi(argv[1]) : 128UL;
  exit(perf_run("PERF-ARRAY", size, work));
}
