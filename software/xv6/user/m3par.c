// MC-M3: two concurrent compute children; each sends {checksum, harts-run-on} to the parent through a pipe;
// the parent waits for BOTH, then prints one line per child and its own DONE line (single writer).
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "m3lib.h"
struct res { int idx; unsigned harts; unsigned long sum; };
int main(int argc, char **argv) {
  int c, st, ok = 1, fd[2];
  if (pipe(fd) < 0) { m3_line("M3-PAR-FAIL pipe"); exit(1); }
  for (c = 0; c < 2; c++) {
    int pid = fork();
    if (pid < 0) { m3_line("M3-PAR-FAIL fork"); exit(1); }
    if (pid == 0) {
      struct res r; r.idx = c; r.harts = 0; r.sum = m3compute(c + 1, 200000, &r.harts);
      close(fd[0]); write(fd[1], &r, sizeof r); close(fd[1]); exit(0);
    }
  }
  close(fd[1]);
  struct res got[2]; int n = 0;
  while (n < 2) { struct res r; if (read(fd[0], &r, sizeof r) != sizeof r) break; if (r.idx >= 0 && r.idx < 2) got[r.idx] = r; n++; }
  for (c = 0; c < 2; c++) { if (wait(&st) < 0 || st != 0) ok = 0; }
  if (n != 2) ok = 0;
  for (c = 0; c < 2; c++) {
    char b[96]; int k = 0; k += m3_str(b + k, "M3-PAR-CHILD"); b[k++] = '0' + c; k += m3_str(b + k, " checksum="); k += m3_hex(b + k, got[c].sum);
    k += m3_str(b + k, " harts=0x"); b[k++] = '0' + (got[c].harts & 3); b[k] = 0; m3_line(b);
  }
  m3_line(ok ? "M3-PAR-DONE children=2 ok=1" : "M3-PAR-DONE children=2 ok=0");
  exit(0);
}
