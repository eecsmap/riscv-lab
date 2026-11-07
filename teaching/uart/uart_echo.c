// UART project 1: echo. Prints a banner and a prompt, then sends back every byte it receives, in upper case -- so what
// comes back has been through the CPU, not just across a wire. Enter ends a line and reports its length.
// LED0 heartbeat (about 2.4 Hz from mtime), LED1 toggles with every byte received, LED2 = a receive error was seen
// (overrun or framing), LED3 = at least one whole line received. Polled, RV64I: a step-2 core runs it.
#include "mcu0.h"
#include "uart.h"

int main(void)
{
  uint8_t rx_toggle = 0, err = 0, line_seen = 0;
  uint64_t len = 0;
  int last = 0;

  uart_init();
  uart_puts("\nMCU-0 UART ready. Type; it comes back in upper case. Enter ends a line.\n> ");
  for (;;) {
    uint64_t st = UART_STATUS;
    if (st & (UART_RX_OVERRUN | UART_RX_FRAME)) err = 1;
    LEDS = (uint8_t)(((CLINT_MTIME >> 23) & 1) | (rx_toggle << 1) | (err << 2) | (line_seen << 3));

    int c = uart_getc_nb();
    if (c < 0) continue;
    rx_toggle ^= 1;
    int crlf = (c == '\n' && last == '\r');   // a terminal that sends "\r\n" for Enter: one line end, not two
    last = c;
    if (crlf) continue;
    if (c == '\r' || c == '\n') {
      uart_puts(" (");
      uart_putdec(len);
      uart_puts(" chars)\n> ");
      len = 0;
      line_seen = 1;
    } else {
      if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
      uart_putc((char)c);
      len++;
    }
  }
}
