// MCU-0, step 4: two tasks, preemptive round robin. The smallest "kernel".
//   task A: blinks LED0, timing itself by polling mtime in a busy loop -- it never gives the CPU away
//   task B: mirrors BTN0..2 onto LED1..3 in an endless loop -- it never gives the CPU away either
// Every SLICE ticks the timer interrupt saves the running task's registers on its own stack and resumes the other.
// Without the interrupt, task A would spin forever and the buttons would never reach the LEDs.
// Start code: task_start.S (saves all 31 registers, not just the caller-saved ones).
#include <stdint.h>

#define CLINT_MTIMECMP (*(volatile uint64_t *)0x02004000)
#define CLINT_MTIME    (*(volatile uint64_t *)0x0200BFF8)
#define GPIO_OUT       (*(volatile uint64_t *)0x10010000)
#define GPIO_IN        (*(volatile uint64_t *)0x10010008)
#ifndef DELAY
#define DELAY 20000000          /* LED0 half period in mtime ticks: 0.5 s at 40 MHz */
#endif
#define SLICE (DELAY / 16)      /* time slice: 31 ms on the board */

#define MSTATUS_MIE (1u << 3)
#define MIE_MTIE    (1u << 7)
#define MCAUSE_MTI  ((1ull << 63) | 7)
#define FRAME_WORDS 32          /* trap_entry's frame: mepc + x1..x31 */

static inline void irq_off(void) { asm volatile("csrc mstatus, %0" :: "r"(MSTATUS_MIE) : "memory"); }
static inline void irq_on(void)  { asm volatile("csrs mstatus, %0" :: "r"(MSTATUS_MIE) : "memory"); }

static uint64_t  stack_b[512];  // task B's stack, 4 KiB; task A runs on the boot stack
static uint64_t *frame[2];      // where each task's registers were saved when it was last interrupted
static int       current;       // 0 = A, 1 = B

uint64_t *trap_handler(uint64_t *f, uint64_t mcause)
{
  if (mcause != MCAUSE_MTI)
    for (;;) GPIO_OUT = 0xA;    // any other trap is a bug: show 1010 and stop
  CLINT_MTIMECMP += SLICE;      // next slice; also lowers mtip
  frame[current] = f;           // remember where the interrupted task's state is ...
  current ^= 1;
  return frame[current];        // ... and resume the other one
}

// Both tasks write GPIO_OUT. A switch between the read and the write would put back the other task's old bits,
// so the read-modify-write runs with interrupts off. This is the only place either task touches GPIO_OUT.
static void gpio_set(uint64_t mask, uint64_t bits)
{
  irq_off();
  GPIO_OUT = (GPIO_OUT & ~mask) | bits;
  irq_on();
}

static void task_a(void)
{
  uint64_t led = 0, until = CLINT_MTIME;
  for (;;) {
    until += DELAY;
    while ((int64_t)(CLINT_MTIME - until) < 0)
      ;                         // busy wait: no yield, no wfi
    led ^= 1;
    gpio_set(1, led);
  }
}

static void task_b(void)
{
  for (;;)
    gpio_set(0xE, (GPIO_IN & 7) << 1);
}

int main(void)
{
  // Make task B look as if it had been interrupted just before its first instruction: a frame at the top of its
  // stack whose mepc is task_b. The first switch "returns" into it. Registers start at zero.
  uint64_t *fb = stack_b + 512 - FRAME_WORDS;
  for (int i = 0; i < FRAME_WORDS; i++) fb[i] = 0;
  fb[0] = (uint64_t)task_b;
  frame[1] = fb;
  current = 0;                  // task A is the code running now; its frame is made by its first interrupt

  CLINT_MTIMECMP = CLINT_MTIME + SLICE;
  asm volatile("csrs mie, %0" :: "r"(MIE_MTIE));
  irq_on();
  task_a();                     // never returns
  return 0;
}
