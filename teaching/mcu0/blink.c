// MCU-0 firmware: LED0 blinks on the CLINT's mtime, LED1..3 mirror BTN0..2 continuously.
// RV64I only -- no CSRs, no multiply, no divide, no interrupts: everything is polled.
#include <stdint.h>

#define CLINT_MTIME (*(volatile uint64_t *)0x0200BFF8)
#define GPIO_OUT    (*(volatile uint64_t *)0x10010000)
#define GPIO_IN     (*(volatile uint64_t *)0x10010008)
#ifndef DELAY
#define DELAY 20000000          /* mtime ticks per half period: 0.5 s at 40 MHz */
#endif

static void wait_and_mirror(uint64_t ticks, uint64_t led0)
{
  uint64_t until = CLINT_MTIME + ticks;
  while ((int64_t)(CLINT_MTIME - until) < 0)
    GPIO_OUT = led0 | ((GPIO_IN & 7) << 1);     // buttons -> LED1..3, polled every loop
}

int main(void)
{
  uint64_t led0 = 0;
  for (;;) {
    led0 ^= 1;
    wait_and_mirror(DELAY, led0);
  }
}
