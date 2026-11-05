// MCU-0 firmware basics shared by teaching/oled and teaching/vga: the CLINT and GPIO registers, the clock, a
// millisecond wait, and decimal numbers without a divider (RV64I has no divide, and with -nostdlib there is no libgcc
// to call). Peripheral drivers (oled.h, vga.h) include this.
#ifndef MCU0_H
#define MCU0_H
#include <stdint.h>

#define CLINT_MTIME (*(volatile uint64_t *)0x0200BFF8)
#define LEDS        (*(volatile uint8_t  *)0x10010000)  // GPIO OUT[7:0]: byte lane 0 only, the JB pins are not touched
#define JB          (*(volatile uint8_t  *)0x10010001)  // GPIO OUT[15:8], Pmod JB: byte lane 1 only, the LEDs are not touched
#define BUTTONS     (*(volatile uint64_t *)0x10010008)

// mtime counts core clocks (TICK_DIV = 1), 40 MHz on the board and in the simulation alike. CLOCK_KHZ turns ticks into
// time for measurements; TICKS_PER_MS is only for waits, and the simulation shrinks it so that "20 ms" is 800 clocks.
#define CLOCK_KHZ 40000
#ifndef TICKS_PER_MS
#define TICKS_PER_MS CLOCK_KHZ
#endif

static void delay_ms(uint32_t ms)
{
  while (ms--) {
    uint64_t until = CLINT_MTIME + TICKS_PER_MS;
    while ((int64_t)(CLINT_MTIME - until) < 0)
      ;
  }
}

// ---- numbers without a divider ----
static uint64_t udiv(uint64_t n, uint64_t d, uint64_t *rem)   // shift and subtract, one quotient bit per round
{
  uint64_t q = 0, r = 0;
  for (int i = 63; i >= 0; i--) {
    r = (r << 1) | ((n >> i) & 1);
    if (r >= d) { r -= d; q |= 1ull << i; }
  }
  if (rem) *rem = r;
  return q;
}

static uint64_t mul10(uint64_t x) { return (x << 3) + (x << 1); }

// v as a decimal with `frac` digits after the point (v is already scaled: 741 with frac 1 is "74.1"), right-aligned in
// `width` characters; returns s
static char *fmt_fixed(char *s, uint64_t v, int frac, int width)
{
  char tmp[24];
  int n = 0;
  uint64_t rem;
  do {
    v = udiv(v, 10, &rem);
    tmp[n++] = (char)('0' + rem);
    if (n == frac) tmp[n++] = '.';
  } while (v || (frac && n < frac + 2));     // at least one digit in front of the point: 5 -> "0.5"
  int pad = width - n, i = 0;
  while (pad-- > 0) s[i++] = ' ';
  while (n) s[i++] = tmp[--n];
  s[i] = 0;
  return s;
}

static char *append(char *d, const char *s) { while (*s) *d++ = *s++; *d = 0; return d; }

#endif
