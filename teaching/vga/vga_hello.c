// VGA project 1: a test screen in text mode, 800 x 600 at 60 Hz on a Pmod VGA (JA + JB).
// RV64I only (start.S, no CSRs, no interrupts): a step-2 core is enough; the new part is the hardware, mcu_vga.v.
//
//   1. measure: clear all 7,500 cells with halfword stores, then again with doubleword stores (four cells each)
//   2. draw: the palette, the character set, and line art in quarter blocks (Bresenham lines and a midpoint circle:
//      adds and shifts only)
//   3. live: a frame counter and the uptime, rewritten once per frame during the vertical blank, so no frame ever
//      shows a half-written number. SW0 up scrolls the whole screen by moving one register.
// LED1 = the screen is drawn, LED0 toggles every HEART_FRAMES frames, LED2 = scrolling.
#include "vga.h"

#ifndef HEART_FRAMES
#define HEART_FRAMES 30         // LED0 blinks once a second
#endif
#ifndef SCROLL_FRAMES
#define SCROLL_FRAMES 6         // SW0 up: one text row every 6 frames, 10 rows a second
#endif
#define SW0 (1u << 4)           // GPIO IN = {sw, btn}

static char num[24], line[VGA_COLS + 1];

// ---- step 1: the same clear, two ways
static uint64_t clear16(uint16_t cell)
{
  uint64_t t0 = CLINT_MTIME;
  for (int i = 0; i < VGA_CELLS; i++) VGA_TEXT[i] = cell;
  return CLINT_MTIME - t0;
}

static uint64_t clear64(uint16_t cell)
{
  uint64_t t0 = CLINT_MTIME;
  vga_fill(cell);
  return CLINT_MTIME - t0;
}

static void show_clear(int y, const char *how, uint64_t ticks)
{
  char *p = append(line, how);
  p = append(p, fmt_fixed(num, udiv(ticks, CLOCK_KHZ / 1000, 0), 3, 8));          // clocks -> microseconds = ms.xxx
  p = append(p, " MS   ");
  p = append(p, fmt_fixed(num, udiv(mul10(ticks), VGA_CELLS, 0), 1, 6));
  append(p, " CLOCKS PER CELL");
  vga_text(2, y, line, WHITE, BLACK);
}

// ---- step 2: line art on the 200 x 150 quarter-block grid
static void line_to(int x0, int y0, int x1, int y1, int fg)        // Bresenham: no multiply, no divide
{
  int dx = x1 > x0 ? x1 - x0 : x0 - x1, sx = x0 < x1 ? 1 : -1;
  int dy = y1 > y0 ? y0 - y1 : y1 - y0, sy = y0 < y1 ? 1 : -1;
  int err = dx + dy;
  for (;;) {
    vga_plot(x0, y0, fg);
    if (x0 == x1 && y0 == y1) break;
    int e2 = err << 1;
    if (e2 >= dy) { err += dy; x0 += sx; }
    if (e2 <= dx) { err += dx; y0 += sy; }
  }
}

static void circle(int cx, int cy, int r, int fg)                   // midpoint circle: one octant, mirrored 8 ways
{
  int x = r, y = 0, err = 1 - r;
  while (x >= y) {
    vga_plot(cx + x, cy + y, fg); vga_plot(cx - x, cy + y, fg); vga_plot(cx + x, cy - y, fg); vga_plot(cx - x, cy - y, fg);
    vga_plot(cx + y, cy + x, fg); vga_plot(cx - y, cy + x, fg); vga_plot(cx + y, cy - x, fg); vga_plot(cx - y, cy - x, fg);
    y++;
    if (err < 0) err += (y << 1) + 1;
    else { x--; err += ((y - x) << 1) + 1; }
  }
}

static void draw(void)
{
  static const char hex[] = "0123456789ABCDEF";
  vga_hline(0, 0, VGA_COLS, CELL(' ', WHITE, BLUE));
  vga_text(1, 0, "MCU-0  MY RV64 CORE ON VGA   800 X 600 @ 60 HZ   TEXT MODE 100 X 75 CELLS, 16 COLOURS", WHITE, BLUE);
  vga_text(2, 2, "CLEAR THE SCREEN, 7500 CELLS:", YELLOW, BLACK);

  vga_text(2, 7, "PALETTE", YELLOW, BLACK);
  for (int c = 0; c < 16; c++) {
    vga_hline(2 + c * 6, 8, 5, CELL(' ', WHITE, c));
    vga_hline(2 + c * 6, 9, 5, CELL(' ', WHITE, c));
    vga_put(4 + c * 6, 10, hex[c], LGREY, BLACK);
  }

  vga_text(2, 12, "CHARACTERS 20..8F (80..8F ARE QUARTER BLOCKS)", YELLOW, BLACK);
  for (int r = 0; r < 7; r++) {
    vga_put(2, 13 + r, hex[r + 2], DGREY, BLACK);
    vga_put(3, 13 + r, 'X', DGREY, BLACK);
    for (int c = 0; c < 16; c++) vga_put(6 + c * 2, 13 + r, (char)(0x20 + (r << 4) + c), r == 6 ? LCYAN : WHITE, r == 6 ? BLUE : BLACK);
  }

  vga_text(2, 21, "QUARTER BLOCKS: 200 X 150 PIXELS -- BRESENHAM LINES AND A MIDPOINT CIRCLE, ADDS AND SHIFTS ONLY", YELLOW, BLACK);
  line_to(0, 44, 199, 44, LGREEN); line_to(199, 44, 199, 139, LGREEN);
  line_to(199, 139, 0, 139, LGREEN); line_to(0, 139, 0, 44, LGREEN);
  line_to(8, 48, 191, 135, LCYAN);
  line_to(8, 135, 191, 48, LMAGENTA);
  circle(100, 91, 40, YELLOW);
  circle(100, 91, 20, LRED);

  vga_text(2, 74, "SW0 UP: SCROLL THE SCREEN -- ONE STORE TO THE SCROLL REGISTER PER ROW, NOT 7500 CELLS MOVED", DGREY, BLACK);
}

int main(void)
{
  LEDS = 0;
  uint64_t t16 = clear16(CELL(' ', WHITE, BLACK));
  uint64_t t64 = clear64(CELL(' ', WHITE, BLACK));
  draw();
  show_clear(3, "16-BIT STORES (SH) ", t16);
  show_clear(4, "64-BIT STORES (SD) ", t64);
  LEDS = 2;

  // ---- step 3: live, once per frame
  uint32_t led0 = 0, top = 0, beat = 0, roll = 0;
  for (;;) {
    // prepare the text first, then wait for the blank and only store: the stores are all that must fit in it
    char *p = append(line, "FRAME ");
    p = append(p, fmt_fixed(num, VGA_FRAME + 1, 0, 9));
    p = append(p, "     UPTIME ");
    p = append(p, fmt_fixed(num, udiv(CLINT_MTIME, CLOCK_KHZ * 100, 0), 1, 8));   // tenths of a second
    append(p, " S");
    int scroll = (BUTTONS & SW0) != 0;

    vga_wait_frame();
    vga_text(2, 72, line, LGREEN, BLACK);
    if (scroll && ++roll >= SCROLL_FRAMES) { roll = 0; top = (top == VGA_ROWS - 1) ? 0 : top + 1; VGA_SCROLL = top; }
    if (!scroll && top) { top = 0; VGA_SCROLL = 0; }
    if (++beat >= HEART_FRAMES) { beat = 0; led0 ^= 1; }
    LEDS = (uint8_t)(led0 | 2 | (scroll ? 4 : 0));
  }
}
