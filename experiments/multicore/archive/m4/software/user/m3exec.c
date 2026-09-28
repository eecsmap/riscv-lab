// MC-M3: an exec chain (m3exec N -> exec m3exec N-1 ... -> 0) ending in an sbrk grow/fill/verify/shrink loop.
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "m3lib.h"
int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 3;
  int depth = argc > 2 ? atoi(argv[2]) : n;
  if (n > 0) {
    char a[8], d[8]; a[0] = '0' + (n - 1); a[1] = 0; d[0] = '0' + depth; d[1] = 0;
    char *av[] = {"m3exec", a, d, 0}; exec("m3exec", av); printf("M3-EXEC-CHAIN-FAIL exec\n"); exit(1);
  }
  int ok = 1, r;
  for (r = 0; r < 6; r++) {
    char *p = sbrk(32 * 4096);
    if (p == (char *)-1) { ok = 0; break; }
    unsigned *w = (unsigned *)p; int i;
    for (i = 0; i < 32 * 1024; i++) w[i] = i * 2654435761u + r;
    for (i = 0; i < 32 * 1024; i++) if (w[i] != i * 2654435761u + r) { ok = 0; break; }
    sbrk(-32 * 4096);
  }
  { char b[64]; int k = m3_str(b, "M3-EXEC-CHAIN-DONE depth="); k += m3_dec(b + k, depth); k += m3_str(b + k, " sbrk_ok="); b[k++] = '0' + ok; b[k] = 0; m3_line(b); }
  exit(0);
}
