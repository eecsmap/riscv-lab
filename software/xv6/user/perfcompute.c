// MC-PERF compute: fixed total work = PERF_CHILDREN x size iterations of the dependency-chained LCG mix (m3compute_nocpu);
// no memory traffic, no syscalls inside the timed work. size defaults to 2000000 per child; argv[1] overrides (short sims).
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "perflib.h"
static unsigned long work(int idx, unsigned long size) { return m3compute_nocpu((unsigned long)idx + 1, (int)size); }
int main(int argc, char **argv) {
  unsigned long size = argc > 1 ? (unsigned long)atoi(argv[1]) : 2000000UL;
  exit(perf_run("PERF-COMPUTE", size, work));
}
