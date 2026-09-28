// B0 application workload: array access. The point is memory traffic, so the array is larger than any
// structure the core could hold (it has no cache at all, but the size keeps the workload honest if one is
// ever added) and it is walked with a stride that does not revisit the same word.
//
// The checksum depends on every element, so a run that skipped part of the array cannot pass.
#include "kernel/types.h"
#include "user/user.h"

#define N      16384        // 128 KiB of uint64
#define PASSES 8
#define STRIDE 7            // coprime with N, so one pass visits every element exactly once

uint64 a[N];

int
main(void)
{
  for (int i = 0; i < N; i++)
    a[i] = (uint64)i * 2654435761ULL;

  uint64 sum = 0;
  int idx = 0;
  for (int p = 0; p < PASSES; p++) {
    for (int i = 0; i < N; i++) {
      sum += a[idx];
      a[idx] ^= sum >> 3;
      idx = (idx + STRIDE) % N;
    }
  }
  printf("B0-ARRAY-CHECKSUM=%lx\n", (unsigned long)sum);
  printf("B0-ARRAY-DONE\n");
  exit(0);
}
