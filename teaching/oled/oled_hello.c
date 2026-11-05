// OLED project 1: "hello, pixels". The Pmod OLEDrgb on Pmod JB, driven by bit-banging from software.
// RV64I only (start.S, no CSRs, no interrupts): a step-2 core is enough.
//
//   1. power up the display in the datasheet's order (oled_init)
//   2. push a full frame pixel by pixel -- 12,288 bytes through two GPIO stores per bit -- and time it with mtime
//   3. clear, draw eight colour bars with the controller's own rectangle command, and time that too
//   4. print both measurements; then LED0 is a heartbeat, and BTN0 runs the whole thing again
#include "oled.h"

#ifndef DELAY
#define DELAY 20000000          // heartbeat half period in mtime ticks: 0.5 s at 40 MHz
#endif

static const uint16_t bar_colour[8] = {
  RGB(255, 255, 255), RGB(255, 255, 0), RGB(0, 255, 255), RGB(0, 255, 0),
  RGB(255, 0, 255),   RGB(255, 0, 0),   RGB(0, 0, 255),   RGB(96, 96, 96),
};

// FRAME_SHIFT: push only the top 64 >> FRAME_SHIFT rows and scale the time up. The simulation uses 3 (8 rows), since
// a whole frame costs it minutes; the board pushes everything (0).
#ifndef FRAME_SHIFT
#define FRAME_SHIFT 0
#endif

// every pixel through SPI: red grows to the right, green downwards, blue the other way. Returns the time a whole
// 96 x 64 frame takes.
static uint64_t push_frame(void)
{
  uint64_t t0 = CLINT_MTIME;
  oled_window(0, 0, OLED_W - 1, (OLED_H >> FRAME_SHIFT) - 1);
  oled_data_begin();
  for (int y = 0; y < (OLED_H >> FRAME_SHIFT); y++)
    for (int x = 0; x < OLED_W; x++) {
      uint16_t r = (uint16_t)((x >> 2) + (x >> 4));          // 0..28 of 31, without a multiply
      oled_pixel((uint16_t)((r << 11) | (y << 5) | (31 - r)));
    }
  oled_data_end();
  return (CLINT_MTIME - t0) << FRAME_SHIFT;
}

// the bottom half: eight 12-pixel bars, each one Draw Rectangle command; returns the SPI time, without the waits
static uint64_t draw_bars(void)
{
  uint64_t spi = 0;
  for (int i = 0; i < 8; i++) {
    uint8_t c = (uint8_t)((i << 3) + (i << 2));               // i * 12
    uint64_t t0 = CLINT_MTIME;
    oled_rect(c, 32, c + 11, OLED_H - 1, bar_colour[i], bar_colour[i]);
    spi += CLINT_MTIME - t0 - TICKS_PER_MS;                   // oled_rect ends with a 1 ms wait: not SPI time
  }
  return spi;
}

static void show(uint64_t frame_ticks, uint64_t bars_ticks)
{
  static char line[24], num[24];
  const uint16_t white = RGB(255, 255, 255), dim = RGB(160, 160, 160), black = 0;
  oled_text(0, 0, "MY RV64 CORE", white, black);

  // a whole frame in tenths of a millisecond
  append(append(append(line, "PUSH "), fmt_fixed(num, udiv(mul10(frame_ticks), CLOCK_KHZ, 0), 1, 5)), "MS");
  oled_text(0, 1, line, dim, black);

  // frames per second, in tenths: CLOCK_KHZ * 1000 ticks in a second
  append(append(line, "FPS  "), fmt_fixed(num, udiv((uint64_t)CLOCK_KHZ * 10000, frame_ticks, 0), 1, 5));
  oled_text(0, 2, line, dim, black);

  // one rectangle in microseconds: (ticks / 8 rectangles) * 1000 / CLOCK_KHZ, with * 1000 = * (1024 - 16 - 8)
  uint64_t one = bars_ticks >> 3;
  append(append(append(line, "RECT "), fmt_fixed(num, udiv((one << 10) - (one << 4) - (one << 3), CLOCK_KHZ, 0), 0, 5)), "US");
  oled_text(0, 3, line, dim, black);
}

int main(void)
{
  oled_init();
  for (;;) {
    LEDS = 0x2;                                   // LED1: drawing
    uint64_t frame = push_frame();
    delay_ms(500);                                // let the gradient be seen
    oled_clear();
    uint64_t bars = draw_bars();
    show(frame, bars);
    LEDS = 0;

    uint64_t led = 0, next = CLINT_MTIME + DELAY;
    while (!(BUTTONS & 1)) {                      // heartbeat until BTN0
      if ((int64_t)(CLINT_MTIME - next) >= 0) { led ^= 1; LEDS = (uint8_t)led; next += DELAY; }
    }
    while (BUTTONS & 1)                           // wait for the release, then measure again
      ;
  }
}
