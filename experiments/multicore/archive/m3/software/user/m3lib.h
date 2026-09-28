// MC-M3 user test helpers.
// Console output on this platform is atomic per write() call (uartwrite holds htif_tx_lock for the whole
// buffer), but xv6's user printf issues one write() per CHARACTER -- so two processes printing at the same
// time on two harts interleave character by character (seen in dual run 1). Test programs therefore build a
// whole line and emit it with ONE write(), and children hand their results to the parent through a pipe so
// that only one process prints.
static __attribute__((unused)) int m3_hex(char *d, unsigned long v) { int i; for (i = 15; i >= 0; i--) { int x = v & 15; d[i] = x < 10 ? '0' + x : 'a' + x - 10; v >>= 4; } return 16; }
static __attribute__((unused)) int m3_dec(char *d, unsigned long v) { char t[24]; int n = 0, i; if (v == 0) t[n++] = '0'; while (v) { t[n++] = '0' + v % 10; v /= 10; } for (i = 0; i < n; i++) d[i] = t[n - 1 - i]; return n; }
static __attribute__((unused)) int m3_str(char *d, const char *s) { int n = 0; while (*s) d[n++] = *s++; return n; }
static __attribute__((unused)) void m3_line(const char *s) { char b[160]; int n = m3_str(b, s); b[n++] = '\n'; write(1, b, n); }
// a deterministic mixing loop; samples the running hart every 1024 iterations into *harts
static __attribute__((unused)) unsigned long m3compute(unsigned long seed, int iters, unsigned *harts) {
  unsigned long x = seed; int i;
  for (i = 0; i < iters; i++) {
    x = x * 6364136223846793005UL + 1442695040888963407UL;
    x ^= x >> 29;
    if ((i & 1023) == 0) *harts |= 1u << getcpu();
  }
  return x;
}
