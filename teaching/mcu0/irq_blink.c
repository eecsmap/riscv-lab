// MCU-0, step 4: LED0 blinks from the CLINT timer interrupt; main only mirrors BTN0..2 onto LED1..3.
// Compare blink.c, where main polls mtime: here main never looks at the time at all.
// Needs a step-4 core (Zicsr, mie/mip, interrupts). Start code: trap_start.S.
#include <stdint.h>

#define CLINT_MTIMECMP (*(volatile uint64_t *)0x02004000)
#define CLINT_MTIME    (*(volatile uint64_t *)0x0200BFF8)
#define GPIO_OUT       (*(volatile uint64_t *)0x10010000)
#define GPIO_IN        (*(volatile uint64_t *)0x10010008)
#ifndef DELAY
#define DELAY 20000000          /* mtime ticks per half period: 0.5 s at 40 MHz */
#endif

#define MSTATUS_MIE (1u << 3)
#define MIE_MTIE    (1u << 7)
#define MCAUSE_MTI  ((1ull << 63) | 7)    /* interrupt bit + machine timer */

static inline void irq_off(void) { asm volatile("csrc mstatus, %0" :: "r"(MSTATUS_MIE) : "memory"); }
static inline void irq_on(void)  { asm volatile("csrs mstatus, %0" :: "r"(MSTATUS_MIE) : "memory"); }

void trap_handler(uint64_t mcause, uint64_t mepc)
{
  (void)mepc;
  if (mcause == MCAUSE_MTI) {
    // Move the deadline by exactly DELAY: the period stays exact however late this handler ran.
    // This also lowers mtip (mtime < mtimecmp again), otherwise the interrupt would fire again at once.
    CLINT_MTIMECMP += DELAY;
    GPIO_OUT ^= 1;                        // the handler owns LED0
    return;
  }
  // Any other trap is a bug in this program: show 1010 on the LEDs and stop here (MIE is already 0 in a trap).
  for (;;)
    GPIO_OUT = 0xA;
}

int main(void)
{
  CLINT_MTIMECMP = CLINT_MTIME + DELAY;   // first deadline
  asm volatile("csrs mie, %0" :: "r"(MIE_MTIE));
  irq_on();
  for (;;) {
    uint64_t buttons = (GPIO_IN & 7) << 1;
    // GPIO_OUT is shared with the handler. Read-modify-write it with interrupts off: an interrupt between the read
    // and the write would toggle LED0, and the write would then put the old LED0 back -- a lost blink.
    irq_off();
    GPIO_OUT = (GPIO_OUT & 1) | buttons;
    irq_on();
  }
}
