// B0 application workload: computation. No syscalls in the measured part, no memory beyond a few
// registers' worth of state, fixed iteration count, and a checksum printed at the end so that a run
// which did not compute what it was supposed to cannot be timed as if it had.
//
// The arithmetic is deliberately integer-only and dependency-chained: each step needs the previous
// result, so the loop cannot be reordered away and the work is the same every run.
#include "kernel/types.h"
#include "user/user.h"

#define ITERS 200000

int
main(void)
{
  uint64 x = 88172645463325252ULL;     // a fixed seed; nothing here is random
  for (int i = 0; i < ITERS; i++) {
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    x += (uint64)i;
  }
  printf("B0-COMPUTE-CHECKSUM=%lx\n", (unsigned long)x);
  printf("B0-COMPUTE-DONE\n");
  exit(0);
}
