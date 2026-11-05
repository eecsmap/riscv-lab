// OLED project 3: the same screen, pushed by the SPI master (mcu_spi.v) instead of by bit-banging.
// RV64I only (start.S, no CSRs, no interrupts): a step-2 core is enough; the hardware is the new part.
//
//   1. measure: one full frame bit-banged (project 1's way), one full frame through the SPI master; show both and the
//      speed-up
//   2. animate: a box bouncing over a gradient, the whole 96 x 56 area redrawn every frame, frames per second on the
//      top line. SW0 picks the way: 0 = bit-bang, 1 = SPI master. Flip it and watch.
//   BTN0 measures again. LED0 toggles once per animation frame, LED1 is on while the SPI master is in use.
#include "oled.h"

#ifndef SPI_DIV
#define SPI_DIV 4               // clocks per half SCK period: 8 per bit, 5 MHz at 40 MHz (the SSD1331 allows 6.67 MHz)
#endif
#ifndef FRAME_SHIFT
#define FRAME_SHIFT 0           // as in oled_hello.c: the simulation times 8 rows and scales up
#endif
#ifndef HOLD_MS
#define HOLD_MS 3000            // how long the measurement screen stays
#endif
#define SW0 (1u << 4)           // GPIO IN = {sw, btn}

static uint64_t push_gradient(void)
{
  uint64_t t0 = CLINT_MTIME;
  oled_window(0, 0, OLED_W - 1, (OLED_H >> FRAME_SHIFT) - 1);
  oled_data_begin();
  for (int y = 0; y < (OLED_H >> FRAME_SHIFT); y++)
    for (int x = 0; x < OLED_W; x++) {
      uint16_t r = (uint16_t)((x >> 2) + (x >> 4));
      oled_pixel((uint16_t)((r << 11) | (y << 5) | (31 - r)));
    }
  oled_data_end();                                  // with the SPI master: returns once the last byte is on the wire
  return (CLINT_MTIME - t0) << FRAME_SHIFT;
}

static void show_ms(int row, const char *label, uint64_t ticks, uint16_t colour)
{
  static char line[24], num[24];
  oled_text(0, row, label, colour, 0);
  append(append(append(line, "  "), fmt_fixed(num, udiv(mul10(ticks), CLOCK_KHZ, 0), 1, 6)), " MS");
  oled_text(0, row + 1, line, RGB(255, 255, 255), 0);
}

static void measure(void)
{
  static char line[24], num[24];
  LEDS = 0;
  spi_mode(0, SPI_DIV);
  uint64_t bb = push_gradient();
  LEDS = 2;
  spi_mode(1, SPI_DIV);
  uint64_t hw = push_gradient();
  oled_clear();
  show_ms(0, "BIT-BANG", bb, RGB(255, 160, 0));
  show_ms(2, "SPI MASTER", hw, RGB(0, 255, 128));
  oled_text(0, 4, "SPEEDUP", RGB(160, 160, 255), 0);
  append(append(line, "  X "), fmt_fixed(num, udiv(mul10(bb), hw, 0), 1, 5));
  oled_text(0, 5, line, RGB(255, 255, 255), 0);
  if (SPI_STATUS & SPI_OVF) oled_text(0, 7, "FIFO OVERFLOW", RGB(255, 0, 0), 0);
  delay_ms(HOLD_MS);
}

// one animation frame: rows 8..63, a 12 x 12 white box at (bx, by) over a gradient that changes per row
static void frame(int bx, int by)
{
  oled_window(0, 8, OLED_W - 1, OLED_H - 1);
  oled_data_begin();
  for (int y = 8; y < OLED_H; y++) {
    uint16_t bg = (uint16_t)(((63 - y) >> 1) | ((y - 8) << 5));        // blue fades out, green fades in
    unsigned dy = (unsigned)(y - by);
    for (int x = 0; x < OLED_W; x++)
      oled_pixel(((unsigned)(x - bx) < 12 && dy < 12) ? 0xFFFF : bg);
  }
  oled_data_end();
}

static void animate(void)
{
  static char line[24], num[24];
  int bx = 3, by = 20, vx = 2, vy = 1, frames = 0, hw = -1;
  uint64_t led = 0, second = CLINT_MTIME + (uint64_t)CLOCK_KHZ * 1000;   // a real second, also in simulation
  oled_clear();
  while (!(BUTTONS & 1)) {
    int want = (BUTTONS & SW0) ? 1 : 0;
    if (want != hw) {                               // SW0 flipped: switch, and start counting afresh
      hw = want; spi_mode(hw, SPI_DIV); frames = 0;
      oled_text(0, 0, hw ? "SPI MASTER  " : "BIT-BANG    ", hw ? RGB(0, 255, 128) : RGB(255, 160, 0), 0);
      second = CLINT_MTIME + (uint64_t)CLOCK_KHZ * 1000;
    }
    frame(bx, by);
    frames++;
    led ^= 1; LEDS = (uint8_t)(led | (hw ? 2 : 0));
    bx += vx; by += vy;
    if (bx <= 0 || bx >= OLED_W - 12) vx = -vx;
    if (by <= 8 || by >= OLED_H - 12) vy = -vy;
    if ((int64_t)(CLINT_MTIME - second) >= 0) {     // once a second: frames in the last second
      fmt_fixed(num, (uint64_t)frames, 0, 3);
      append(append(append(line, hw ? "SPI " : "BB  "), num), " FPS    ");
      oled_text(0, 0, line, hw ? RGB(0, 255, 128) : RGB(255, 160, 0), 0);
      frames = 0;
      second += (uint64_t)CLOCK_KHZ * 1000;
    }
  }
  while (BUTTONS & 1)
    ;
}

int main(void)
{
  oled_init();
  for (;;) {
    measure();
    animate();
  }
}
