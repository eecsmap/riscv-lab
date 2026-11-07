// MCU-0 UART driver (teaching/uart/README.md; the hardware is teaching/mcu0/mcu_uart.v). Polled: every function waits
// by reading STATUS or RX, no interrupts, so it runs on a step-2 core.
#ifndef UART_H
#define UART_H
#include <stdint.h>
#include "mcu0.h"

#define UART_TX     (*(volatile uint64_t *)0x10050000)
#define UART_RX     (*(volatile uint64_t *)0x10050008)   // bit 8 VALID, bits 7:0 the byte; reading takes it
#define UART_STATUS (*(volatile uint64_t *)0x10050010)
#define UART_DIV    (*(volatile uint64_t *)0x10050018)   // clocks per bit, 347 after reset = 115200 baud at 40 MHz

#define UART_TX_READY   1u
#define UART_TX_IDLE    2u
#define UART_RX_VALID   4u
#define UART_RX_OVERRUN 8u
#define UART_RX_FRAME   16u
#define UART_TX_OVERFLOW 32u

static void uart_putc(char c)
{
  while (!(UART_STATUS & UART_TX_READY))
    ;
  UART_TX = (uint8_t)c;
}

// -1 if nothing has arrived; one load both checks and takes
static int uart_getc_nb(void)
{
  uint64_t v = UART_RX;
  return (v & 0x100) ? (int)(v & 0xFF) : -1;
}

static int uart_getc(void)
{
  int c;
  while ((c = uart_getc_nb()) < 0)
    ;
  return c;
}

// "\n" goes out as "\r\n", which is what a terminal wants
static void uart_puts(const char *s)
{
  for (; *s; s++) {
    if (*s == '\n') uart_putc('\r');
    uart_putc(*s);
  }
}

static void uart_putdec(uint64_t v)
{
  char s[24];
  uart_puts(fmt_fixed(s, v, 0, 0));
}

static void uart_puthex(uint64_t v, int digits)
{
  for (int i = digits - 1; i >= 0; i--)
    uart_putc("0123456789abcdef"[(v >> (4 * i)) & 15]);
}

#endif
