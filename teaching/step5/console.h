// Step 5: a console for C programs on the RD2 SoC, through HTIF. Header only, no library.
//
// tohost is a 64-bit word in memory (defined in tests/cpu/m3tests/htif.S, section .htif). The host (fesvr) polls
// it over the serial link: a non-zero value is a command, and the host writes 0 back once it has taken it.
//   tohost = device << 56 | command << 48 | payload
//   console: device 1, command 1, payload = the character
//   exit:    device 0, payload = (code << 1) | 1
// So every write waits until the previous command has been taken -- the console is as slow as the host's polling.
#ifndef STEP5_CONSOLE_H
#define STEP5_CONSOLE_H
#include <stdint.h>

extern volatile uint64_t tohost;

static inline void con_putc(char c)
{
  while (tohost != 0)
    ;
  tohost = (1ull << 56) | (1ull << 48) | (uint8_t)c;
}

static inline void con_puts(const char *s)
{
  while (*s)
    con_putc(*s++);
}

static inline void con_puthex(uint64_t v)
{
  con_puts("0x");
  for (int i = 60; i >= 0; i -= 4)
    con_putc("0123456789abcdef"[(v >> i) & 15]);
}

// RV64I has no divide instruction (that is the M extension, step 11), and -nostdlib gives no __udivdi3 either,
// so v / 10 would not even link. Repeated subtraction of powers of ten instead: at most 9 subtractions per digit.
static inline void con_putdec(uint64_t v)
{
  static const uint64_t pow10[] = { 10000000000000000000ull, 1000000000000000000ull, 100000000000000000ull,
    10000000000000000ull, 1000000000000000ull, 100000000000000ull, 10000000000000ull, 1000000000000ull,
    100000000000ull, 10000000000ull, 1000000000ull, 100000000ull, 10000000ull, 1000000ull, 100000ull, 10000ull,
    1000ull, 100ull, 10ull, 1ull };
  int started = 0;
  for (int i = 0; i < 20; i++) {
    char d = '0';
    while (v >= pow10[i]) { v -= pow10[i]; d++; }
    if (d != '0' || started || i == 19) { con_putc(d); started = 1; }
  }
}

static inline uint64_t rdcycle(void)   { uint64_t v; asm volatile("csrr %0, mcycle" : "=r"(v)); return v; }
static inline uint64_t rdinstret(void) { uint64_t v; asm volatile("csrr %0, minstret" : "=r"(v)); return v; }

#endif
