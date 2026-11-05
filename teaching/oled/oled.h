// Pmod OLEDrgb (SSD1331 controller, 96 x 64 pixels, 16-bit colour) on MCU-0, on the Pmod JB header, which is GPIO
// OUT[15:8]. Bytes go out by bit-banging GPIO (project 1), or through the SPI master mcu_spi.v after spi_mode(1, div)
// (project 3). RV64I only: no multiply, no divide, no CSRs, no interrupts -- a step-2 core runs it.
//
// The rules this follows, and where they come from (teaching/oled/README.md has the details):
//   SSD1331 datasheet rev 1.2, 7.1.3  SCLK rising edge shifts SDIN in, D7 first; D/C# is sampled on the 8th clock
//                              7.9    RES# low >= 3 us, then VCC on, then command AFh; the panel lights 100 ms later
//                              table  serial clock cycle >= 150 ns
//                              9.2    Draw Rectangle colours: C and A in bits 5:1, B in bits 5:0
//   Digilent PmodOLEDrgb driver       the init command list, and the waits: 20 ms after PMODEN, 5 ms after a clear,
//                                     25 ms after VCCEN
// No / or %: RV64I has no divide, and with -nostdlib there is no libgcc to call. udiv() in mcu0.h does it by hand.
#ifndef OLED_DRIVER_H
#define OLED_DRIVER_H
#include <stdint.h>
#include "mcu0.h"
#include "font8x8.h"

// GPIO OUT[15:8] bit = Pmod JB pin: jb[0..3] are pins 1-4, jb[4..7] are pins 7-10
#define JB_CS     0x01  // pin 1  CS#, active low
#define JB_MOSI   0x02  // pin 2  SDIN
#define JB_SCK    0x08  // pin 4  SCLK (pin 3 is not connected on the OLEDrgb)
#define JB_DC     0x10  // pin 7  D/C#: 0 = command, 1 = display data
#define JB_RES    0x20  // pin 8  RES#, active low
#define JB_VCCEN  0x40  // pin 9  the panel's high voltage
#define JB_PMODEN 0x80  // pin 10 the Pmod's logic supply

#define OLED_W 96
#define OLED_H 64
#define RGB(r, g, b) ((uint16_t)((((r) >> 3) << 11) | (((g) >> 2) << 5) | ((b) >> 3)))   // 8-bit components -> 565

static uint8_t jb_now;          // what the JB pins show now (a copy: reading GPIO back would cost a bus round trip)

// ---- the SPI master, teaching/mcu0/mcu_spi.v (OLED project 3). Off after reset: then everything is bit-banged.
#define SPI_DATA8  (*(volatile uint8_t  *)0x10020000)   // one byte into the FIFO
#define SPI_DATA16 (*(volatile uint16_t *)0x10020008)   // one pixel: two bytes, bits 15:8 first
#define SPI_STATUS (*(volatile uint32_t *)0x10020010)
#define SPI_CTRL   (*(volatile uint32_t *)0x10020018)
#define SPI_BUSY 1u                                     // a byte on the wire or waiting in the FIFO
#define SPI_FULL 2u                                     // fewer than 2 free FIFO entries: wait before writing
#define SPI_OVF  4u                                     // a write was dropped (cleared by writing CTRL)
static int spi_hw;                                      // 1: bytes go through the SPI master

static void spi_wait_idle(void) { while (SPI_STATUS & SPI_BUSY) ; }

// hand SCK and MOSI to the SPI master (hw = 1) or back to GPIO (hw = 0); div: clocks per half SCK period
static void spi_mode(int hw, uint32_t div)
{
  if (spi_hw) spi_wait_idle();
  spi_hw = hw;
  SPI_CTRL = (div << 8) | (hw ? 1u : 0u);
}

// CS# and D/C# stay on GPIO. Changing them while a byte is still on the wire would cut it off or change D/C# before
// the 8th edge samples it, so with the SPI master on, wait for it to finish first.
static void jb(uint8_t v)
{
  if (spi_hw) spi_wait_idle();
  jb_now = v; JB = v;
}

// one byte by bit-banging, SPI mode 0: SCK rests low; MOSI is set while SCK is low and the display takes it on the
// rising edge. Two stores per bit, never one: if MOSI and SCK changed in the same store there would be no setup time.
#ifndef OLED_FAST
static void bb_byte(uint8_t b)
{
  uint8_t lo = jb_now & (uint8_t)~(JB_MOSI | JB_SCK);
  for (int i = 0; i < 8; i++) {
    uint8_t d = (b & 0x80) ? (lo | JB_MOSI) : lo;
    JB = d;                     // data out, SCK low
    JB = d | JB_SCK;            // rising edge: the display shifts this bit in
    b <<= 1;
  }
  JB = lo;
}
#else
// OLED_FAST: the same bits, without the loop counter and without the branch -- the bit is moved straight to the MOSI
// position (bit 1) with a shift and a mask. Same SPI waveform, fewer instructions per bit.
static void bb_byte(uint8_t b)
{
  uint32_t lo = jb_now & (uint8_t)~(JB_MOSI | JB_SCK), hi = lo | JB_SCK, v = b, m;
#define SPI_BIT(k) m = ((k) >= 1 ? (v >> ((k) - 1)) : (v << 1)) & JB_MOSI; JB = (uint8_t)(lo | m); JB = (uint8_t)(hi | m);
  SPI_BIT(7) SPI_BIT(6) SPI_BIT(5) SPI_BIT(4) SPI_BIT(3) SPI_BIT(2) SPI_BIT(1) SPI_BIT(0)
#undef SPI_BIT
  JB = (uint8_t)lo;
}
#endif

static void spi_byte(uint8_t b)
{
  if (spi_hw) { while (SPI_STATUS & SPI_FULL) ; SPI_DATA8 = b; }
  else bb_byte(b);
}

// a command and its parameters: D/C# = 0 for every byte, CS# low around the whole group
static void oled_cmds(const uint8_t *p, int n)
{
  jb(jb_now & (uint8_t)~(JB_DC | JB_CS));
  while (n--) spi_byte(*p++);
  jb(jb_now | JB_CS);
}

static void oled_cmd1(uint8_t c) { oled_cmds(&c, 1); }

// display data: D/C# = 1, two bytes per pixel, high byte first (datasheet figure 11: C4..C0 B5..B3, then B2..B0 A4..A0)
static void oled_data_begin(void) { jb((jb_now | JB_DC) & (uint8_t)~JB_CS); }
static void oled_pixel(uint16_t c)
{
  if (spi_hw) { while (SPI_STATUS & SPI_FULL) ; SPI_DATA16 = c; }      // one store per pixel
  else { bb_byte((uint8_t)(c >> 8)); bb_byte((uint8_t)c); }
}
static void oled_data_end(void) { jb((jb_now | JB_CS) & (uint8_t)~JB_DC); }

// where the next pixels go: columns c1..c2, rows r1..r2, filled left to right, then top to bottom
static void oled_window(uint8_t c1, uint8_t r1, uint8_t c2, uint8_t r2)
{
  static uint8_t cmd[6] = { 0x15, 0, 0, 0x75, 0, 0 };
  cmd[1] = c1; cmd[2] = c2; cmd[4] = r1; cmd[5] = r2;
  oled_cmds(cmd, 6);
}

static void oled_clear(void)
{
  static const uint8_t cmd[5] = { 0x25, 0, 0, OLED_W - 1, OLED_H - 1 };
  oled_cmds(cmd, 5);
  delay_ms(5);                  // the controller clears its RAM on its own; Digilent's driver waits 5 ms
}

// the controller draws the rectangle itself: 13 bytes over SPI instead of two per pixel
static void oled_rect(uint8_t c1, uint8_t r1, uint8_t c2, uint8_t r2, uint16_t line, uint16_t fill)
{
  static uint8_t cmd[13] = { 0x26, 0x01, 0x22 };      // fill on, then draw rectangle
  cmd[3] = c1; cmd[4] = r1; cmd[5] = c2; cmd[6] = r2;
  cmd[7]  = (uint8_t)((line >> 11) << 1); cmd[8]  = (uint8_t)((line >> 5) & 0x3F); cmd[9]  = (uint8_t)((line & 0x1F) << 1);
  cmd[10] = (uint8_t)((fill >> 11) << 1); cmd[11] = (uint8_t)((fill >> 5) & 0x3F); cmd[12] = (uint8_t)((fill & 0x1F) << 1);
  oled_cmds(cmd, 13);
  delay_ms(1);                  // the datasheet gives no drawing time; 1 ms is a guess with a wide margin
}

// one 8x8 character in text cell (cx, cy): 12 cells across, 8 down
static void oled_char(int cx, int cy, char ch, uint16_t fg, uint16_t bg)
{
  const uint8_t *g = &font8x8[(uint32_t)((ch < 0x20 || ch > 0x7F) ? '?' - FONT_FIRST : ch - FONT_FIRST) << 3];
  uint8_t x = (uint8_t)(cx << 3), y = (uint8_t)(cy << 3);
  oled_window(x, y, x + 7, y + 7);
  oled_data_begin();
  for (int row = 0; row < 8; row++)
    for (int col = 0; col < 8; col++)
      oled_pixel((g[col] >> row) & 1 ? fg : bg);
  oled_data_end();
}

static void oled_text(int cx, int cy, const char *s, uint16_t fg, uint16_t bg)
{
  while (*s && cx < OLED_W / 8) oled_char(cx++, cy, *s++, fg, bg);
}

// power up and configure, as datasheet 7.9 orders it, with Digilent's waits
static void oled_init(void)
{
  static const uint8_t init[] = {
    0xFD, 0x12,                 // unlock the command interface
    0xAE,                       // display off while configuring
    0xA0, 0x72,                 // remap: 65k colour (A[7:6] = 01), COM split, scan COM63..0, column 95..0 -> pixel (0,0) top left
    0xA1, 0x00, 0xA2, 0x00,     // start line 0, no vertical offset
    0xA4,                       // normal display (not all on / all off / inverted)
    0xA8, 0x3F,                 // multiplex 1/64: all 64 rows
    0xAD, 0x8E,                 // master configuration: external VCC (the Pmod's VCCEN supply)
    0xB0, 0x0B,                 // power save off
    0xB1, 0x31,                 // phase 1 and 2 lengths
    0xB3, 0xF0,                 // display clock divider and oscillator
    0x8A, 0x64, 0x8B, 0x78, 0x8C, 0x64,   // second precharge speed, colours A, B, C
    0xBB, 0x3A,                 // precharge voltage
    0xBE, 0x3E,                 // VCOMH level
    0x87, 0x06,                 // master current
    0x81, 0x91, 0x82, 0x50, 0x83, 0x7D,   // contrast, colours A, B, C
    0x2E,                       // no scrolling
  };
  jb(JB_CS | JB_RES | JB_PMODEN);          // logic supply on; RES# high, CS# idle high, VCC still off
  delay_ms(20);                             // let VDD settle
  jb(jb_now & (uint8_t)~JB_RES);            // RES# low: >= 3 us
  delay_ms(1);
  jb(jb_now | JB_RES);
  delay_ms(2);
  oled_cmds(init, sizeof init);
  oled_clear();
  jb(jb_now | JB_VCCEN);                    // only now the panel's high voltage
  delay_ms(25);                             // until VCC is stable
  oled_cmd1(0xAF);                          // display on
  delay_ms(100);                            // SEG/COM come on 100 ms after AFh
}

#endif
