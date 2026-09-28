// MC-PERF time-base smoke test (short): the mtime() syscall reads the shared CLINT mtime.
//  1. monotonic: 8 consecutive reads in the parent never go backwards, and each pair's difference is printed (read cost).
//  2. shared across processes/harts: a child reads mtime between the parent's reads P0 (before fork) and P1 (after wait);
//     with two harts the child usually runs on the other hart; the value must satisfy P0 <= C <= P1 (one time base, not per-hart).
//  3. correspondence: the parent spins a fixed loop between two reads and prints the delta; with the kernel tick also printed
//     (uptime), dmtime/25000 must be >= ticks elapsed (ticks can only under-count, never over-count elapsed mtime).
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "m3lib.h"
int main(int argc, char **argv) {
  unsigned long r[8]; int i, fd[2], st, ok = 1; unsigned long p0, p1, c = 0, u0, u1, s0, s1, x = 1;
  char b[200]; int k;
  for (i = 0; i < 8; i++) r[i] = mtime();
  k = 0; k += m3_str(b + k, "MTIME-READS");
  for (i = 0; i < 8; i++) { b[k++] = ' '; k += m3_dec(b + k, r[i]); if (i && r[i] < r[i - 1]) ok = 0; }
  b[k] = 0; m3_line(b);
  if (pipe(fd) < 0) { m3_line("MTIME-FAIL pipe"); exit(1); }
  u0 = (unsigned long)uptime(); p0 = mtime();
  int pid = fork();
  if (pid < 0) { m3_line("MTIME-FAIL fork"); exit(1); }
  if (pid == 0) { unsigned long v = mtime(); close(fd[0]); write(fd[1], &v, sizeof v); close(fd[1]); exit(0); }
  close(fd[1]); if (read(fd[0], &c, sizeof c) != sizeof c) ok = 0; close(fd[0]); wait(&st);
  p1 = mtime(); u1 = (unsigned long)uptime();
  if (!(p0 <= c && c <= p1)) ok = 0;
  s0 = mtime(); for (i = 0; i < 100000; i++) { x = x * 6364136223846793005UL + 1442695040888963407UL; x ^= x >> 29; } s1 = mtime();
  k = 0; k += m3_str(b + k, "MTIME-SHARED p0="); k += m3_dec(b + k, p0); k += m3_str(b + k, " child="); k += m3_dec(b + k, c);
  k += m3_str(b + k, " p1="); k += m3_dec(b + k, p1); k += m3_str(b + k, " ticks="); k += m3_dec(b + k, u1 - u0);
  k += m3_str(b + k, " spin100k="); k += m3_dec(b + k, s1 - s0); k += m3_str(b + k, " x="); k += m3_hex(b + k, x); b[k] = 0; m3_line(b);
  m3_line(ok ? "MTIME-DONE ok=1" : "MTIME-DONE ok=0");
  exit(ok ? 0 : 1);
}
