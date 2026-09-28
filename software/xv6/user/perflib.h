// MC-PERF: fixed-total-work parallel benchmarks, shared helpers. Same single-write() console discipline as m3lib.h
// (xv6 user printf writes per character; concurrent writers interleave). The parent is the ONLY writer.
#include "m3lib.h"
#define PERF_CHILDREN 4
struct perf_res { int idx; unsigned long sum; };
// Time base (Codex timebase-fix): the shared CLINT mtime, read through the mtime() syscall -- a free-running hardware counter
// at core clock / 100 (400 kHz at 40 MHz). NOT the kernel tick: timervec rearms mtimecmp from the current mtime, so
// `ticks` (uptime()) under-counts elapsed time under load; uptime is printed as a DIAGNOSTIC only.
static __attribute__((unused)) unsigned long perf_now(void) { return mtime(); }
// the parent: fork PERF_CHILDREN children (each an independent address space), collect each child's checksum through a
// pipe, wait for all, print one summary line. work(idx, size) is the child's job. Returns nonzero if anything failed.
static __attribute__((unused)) int perf_run(const char *tag, unsigned long size, unsigned long (*work)(int, unsigned long)) {
  int c, st, fd[2], ok = 1, n = 0; struct perf_res got[PERF_CHILDREN]; unsigned long m0, m1, ma, mb, u0, u1;
  for (c = 0; c < PERF_CHILDREN; c++) got[c].idx = -1;
  if (pipe(fd) < 0) { m3_line("PERF-FAIL pipe"); return 1; }
  ma = perf_now(); mb = perf_now();     // two back-to-back reads: the cost of one mtime() round trip, in mtime units
  u0 = (unsigned long)uptime();
  m0 = perf_now();                      // START: immediately before the first fork
  for (c = 0; c < PERF_CHILDREN; c++) {
    int pid = fork();
    if (pid < 0) { m3_line("PERF-FAIL fork"); return 1; }
    if (pid == 0) { struct perf_res r; r.idx = c; r.sum = work(c, size); close(fd[0]); write(fd[1], &r, sizeof r); close(fd[1]); exit(0); }
  }
  close(fd[1]);
  while (n < PERF_CHILDREN) { struct perf_res r; if (read(fd[0], &r, sizeof r) != sizeof r) break; if (r.idx >= 0 && r.idx < PERF_CHILDREN) got[r.idx] = r; n++; }
  for (c = 0; c < PERF_CHILDREN; c++) { if (wait(&st) < 0 || st != 0) ok = 0; }
  m1 = perf_now();                      // END: after the LAST wait returned; the children's exit is inside the region
  u1 = (unsigned long)uptime();
  close(fd[0]);
  if (n != PERF_CHILDREN) ok = 0;
  for (c = 0; c < PERF_CHILDREN; c++) if (got[c].idx != c) ok = 0;
  { char b[240]; int k = 0;
    k += m3_str(b + k, tag); k += m3_str(b + k, " size="); k += m3_dec(b + k, size);
    k += m3_str(b + k, " children="); k += m3_dec(b + k, PERF_CHILDREN);
    k += m3_str(b + k, " mt0="); k += m3_dec(b + k, m0); k += m3_str(b + k, " mt1="); k += m3_dec(b + k, m1);
    k += m3_str(b + k, " dmtime="); k += m3_dec(b + k, m1 - m0);
    k += m3_str(b + k, " readcost="); k += m3_dec(b + k, mb - ma);
    k += m3_str(b + k, " ticks="); k += m3_dec(b + k, u1 - u0);
    k += m3_str(b + k, " ok="); b[k++] = ok ? '1' : '0'; b[k] = 0; m3_line(b); }
  for (c = 0; c < PERF_CHILDREN; c++) { char b[96]; int k = 0; k += m3_str(b + k, tag); k += m3_str(b + k, "-CHILD"); b[k++] = '0' + c;
    k += m3_str(b + k, " checksum="); if (got[c].idx == c) k += m3_hex(b + k, got[c].sum); else k += m3_str(b + k, "MISSING"); b[k] = 0; m3_line(b); }
  m3_line(ok ? "PERF-DONE ok=1" : "PERF-DONE ok=0");
  return ok ? 0 : 1;
}
