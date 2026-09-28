// B0 application workload: file I/O. Writes a fixed number of fixed blocks, reads them all back, and
// checksums what it read -- so the read is really a read and not an optimisation.
//
// It removes its own file first and again at the end, because a workload that leaves state behind is a
// different workload the second time it runs. The disk reset policy is in benchmarks/metrics.md and the
// run manifest; this is the program's part of it.
#include "kernel/types.h"
#include "user/user.h"
#include "kernel/fcntl.h"

#define BLOCK  512
#define BLOCKS 64           // 32 KiB: bounded, and small enough for xv6's file size limits

char buf[BLOCK];

int
main(void)
{
  unlink("b0file.dat");

  int fd = open("b0file.dat", O_CREATE | O_WRONLY);
  if (fd < 0) { printf("B0-FILE-FAIL open-write\n"); exit(1); }
  for (int b = 0; b < BLOCKS; b++) {
    for (int i = 0; i < BLOCK; i++)
      buf[i] = (char)((b * 31 + i * 7) & 0xff);
    if (write(fd, buf, BLOCK) != BLOCK) { printf("B0-FILE-FAIL write\n"); exit(1); }
  }
  close(fd);

  uint64 sum = 0;
  fd = open("b0file.dat", O_RDONLY);
  if (fd < 0) { printf("B0-FILE-FAIL open-read\n"); exit(1); }
  for (int b = 0; b < BLOCKS; b++) {
    if (read(fd, buf, BLOCK) != BLOCK) { printf("B0-FILE-FAIL read\n"); exit(1); }
    for (int i = 0; i < BLOCK; i++)
      sum = sum * 131 + (unsigned char)buf[i];
  }
  close(fd);
  unlink("b0file.dat");

  printf("B0-FILE-CHECKSUM=%lx\n", (unsigned long)sum);
  printf("B0-FILE-DONE\n");
  exit(0);
}
