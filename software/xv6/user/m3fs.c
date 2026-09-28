// MC-M3: two children write, read back and verify their own files at the same time (disk requests from two
// harts interleave through the block-device lock); each reports through a pipe; the parent waits for both and
// prints (single writer).
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "kernel/fcntl.h"
#include "m3lib.h"
#define WORDS 2048
int main(int argc, char **argv) {
  int c, st, ok = 1, fd[2]; int res[2] = {-1, -1};
  if (pipe(fd) < 0) { m3_line("M3-FS-FAIL pipe"); exit(1); }
  for (c = 0; c < 2; c++) {
    if (fork() == 0) {
      char name[8] = "m3f0"; name[3] = '0' + c;
      unsigned buf[256]; int i, k, good = 1;
      int f = open(name, O_CREATE | O_WRONLY);
      if (f < 0) good = 0;
      else {
        for (k = 0; k < WORDS / 256; k++) { for (i = 0; i < 256; i++) buf[i] = (k * 256 + i) * 2246822519u + c; if (write(f, buf, sizeof buf) != sizeof buf) good = 0; }
        close(f);
        f = open(name, O_RDONLY);
        for (k = 0; k < WORDS / 256; k++) { if (read(f, buf, sizeof buf) != sizeof buf) good = 0; for (i = 0; i < 256; i++) if (buf[i] != (k * 256 + i) * 2246822519u + c) good = 0; }
        close(f); unlink(name);
      }
      int r[2] = {c, good}; close(fd[0]); write(fd[1], r, sizeof r); close(fd[1]); exit(good ? 0 : 1);
    }
  }
  close(fd[1]);
  for (c = 0; c < 2; c++) { int r[2]; if (read(fd[0], r, sizeof r) == sizeof r && r[0] >= 0 && r[0] < 2) res[r[0]] = r[1]; }
  for (c = 0; c < 2; c++) { if (wait(&st) < 0 || st != 0) ok = 0; }
  for (c = 0; c < 2; c++) { char b[40]; int k = m3_str(b, "M3-FS-CHILD"); b[k++] = '0' + c; k += m3_str(b + k, " ok="); b[k++] = res[c] == 1 ? '1' : '0'; b[k] = 0; m3_line(b); if (res[c] != 1) ok = 0; }
  m3_line(ok ? "M3-FS-DONE ok=1" : "M3-FS-DONE ok=0");
  exit(0);
}
