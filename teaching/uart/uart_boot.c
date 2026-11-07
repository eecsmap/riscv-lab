// UART project 2: the bootloader. It lives in the first 4 KiB of RAM (boot.ld) and is what the bitstream holds; it
// receives a program over the serial port into 0x8000_1000..0x8000_FFFF, checks it, and jumps to it. Changing the
// program then takes seconds instead of a Vivado run. The PC side is teaching/tools/uart_load.py (make boot-load).
//
// The protocol is binary, with a one-letter answer after each step, so that a script can follow it:
//   PC: 'L', address (4 bytes, little-endian), length (4 bytes)
//   MCU: 'A' accepted, or 'R' + text: the range is not inside the program area (or the address is not 8-aligned)
//   PC: the bytes, then their CRC-32 (4 bytes; the same CRC as zlib.crc32 and zip)
//   MCU: 'K' + text: stored and the CRC matches; 'C' + text: CRC mismatch; 'O' + text: bytes were lost (overrun);
//        'T' + text: nothing arrived for a second (the transfer is abandoned)
//   PC: 'G'
//   MCU: 'G' + text, then it jumps to the address of the last good load ('N' + text if there is none)
// Anything else (a person typing) gets the help text. After every answer comes the prompt "boot> ".
//
// A reset (BTN3, or the PC sending a serial break: mcu_break) restarts the bootloader, but RAM is NOT reloaded: a
// reset is not a power-on. So the bootloader keeps all its state in local variables -- an initialised global would
// still hold whatever it was changed to before the reset. LED0: waiting at the prompt, LED1: receiving, LED3: loaded.
#include "mcu0.h"
#include "uart.h"

#define APP_BASE 0x80001000u
#define APP_END  0x80010000u
#define TIMEOUT  (1000ull * TICKS_PER_MS)      // one second without a byte ends a transfer

// CRC-32, reflected, polynomial 0xEDB88320: one bit at a time, no table, no multiply
static uint32_t crc32_byte(uint32_t c, uint8_t b)
{
  c ^= b;
  for (int i = 0; i < 8; i++)
    c = (c >> 1) ^ (0xEDB88320u & (0u - (c & 1)));
  return c;
}

static int getc_timeout(void)
{
  uint64_t t0 = CLINT_MTIME;
  int c;
  while ((c = uart_getc_nb()) < 0)
    if (CLINT_MTIME - t0 > TIMEOUT) return -1;
  return c;
}

static int get_u32(uint32_t *v)
{
  uint32_t x = 0;
  for (int i = 0; i < 4; i++) {
    int c = getc_timeout();
    if (c < 0) return 0;
    x |= (uint32_t)c << (8 * i);
  }
  *v = x;
  return 1;
}

static void help(void)
{
  uart_puts("MCU-0 bootloader. Programs go to 0x80001000..0x8000ffff; use teaching/tools/uart_load.py.\n");
}

int main(void)
{
  uint32_t entry = 0;
  int loaded = 0;

  uart_init();
  LEDS = 1;
  uart_puts("\n");
  help();
  for (;;) {
    uart_puts("boot> ");
    LEDS = (uint8_t)(1 | (loaded << 3));
    int c = uart_getc();

    if (c == 'L') {
      uint32_t addr, len, want, got = 0xFFFFFFFFu;
      if (!get_u32(&addr) || !get_u32(&len)) { uart_puts("T timeout in the header\n"); continue; }
      if (addr < APP_BASE || addr >= APP_END || len > APP_END - addr || (addr & 7)) {
        uart_putc('R');
        uart_puts(" range: "); uart_puthex(addr, 8); uart_puts(" + "); uart_putdec(len);
        uart_puts(" is not inside 80001000..8000ffff\n");
        continue;
      }
      loaded = 0;                              // whatever was there is being overwritten
      UART_STATUS = 0;                         // clear old errors, so that an overrun now means this transfer
      LEDS = 2;
      uart_putc('A');
      volatile uint8_t *p = (volatile uint8_t *)(uintptr_t)addr;
      uint32_t i;
      for (i = 0; i < len; i++) {
        int b = getc_timeout();
        if (b < 0) break;
        p[i] = (uint8_t)b;
        got = crc32_byte(got, (uint8_t)b);
      }
      got = ~got;
      if (i < len || !get_u32(&want)) {
        uart_puts("T timeout after "); uart_putdec(i); uart_puts(" bytes\n");
      } else if (UART_STATUS & UART_RX_OVERRUN) {
        uart_puts("O overrun: bytes were lost (the sender is faster than this loop)\n");
      } else if (got != want) {
        uart_puts("C crc "); uart_puthex(got, 8); uart_puts(", expected "); uart_puthex(want, 8); uart_puts("\n");
      } else {
        uart_puts("K "); uart_putdec(len); uart_puts(" bytes at "); uart_puthex(addr, 8);
        uart_puts(", crc "); uart_puthex(got, 8); uart_puts("\n");
        entry = addr; loaded = 1;
      }
    } else if (c == 'G') {
      if (!loaded) { uart_puts("N nothing loaded\n"); continue; }
      uart_puts("G go "); uart_puthex(entry, 8); uart_puts("\n");
      while (!(UART_STATUS & UART_TX_IDLE))   // let the last byte leave before the program takes the UART
        ;
      LEDS = 0;
      __asm__ volatile(".4byte 0x0000100f" ::: "memory");   // fence.i: the bytes just stored are now instructions
      ((void (*)(void))(uintptr_t)entry)();
    } else {
      help();
    }
  }
}
