// VGA text mode on MCU-0 (teaching/mcu0/mcu_vga.v): 100 x 75 character cells, 16 colours, on a Pmod VGA across
// JA + JB. RV64I only -- no multiply, no divide, no CSRs -- so a step-2 core runs it.
//
// A cell is one halfword: character in bits 7:0, foreground colour 11:8, background colour 15:12. The hardware reads
// the cells 60 times a second by itself; drawing is nothing but stores. Characters 0x20..0x7F are ASCII,
// 0x80..0x8F are quarter blocks (bit 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right), which give 200 x 150
// "pixels" with two colours per cell.
#ifndef VGA_DRIVER_H
#define VGA_DRIVER_H
#include "mcu0.h"

#define VGA_TEXT   ((volatile uint16_t *)0x10030000)   // cell (x, y) is VGA_TEXT[y * 100 + x]
#define VGA_TEXT64 ((volatile uint64_t *)0x10030000)   // the same memory, four cells per doubleword
#define VGA_FRAME  (*(volatile uint32_t *)0x10034000)  // frames since reset; changes as each vertical blank begins
#define VGA_STATUS (*(volatile uint32_t *)0x10034008)  // bit 0 VBLANK, bits 25:16 the beam's line
#define VGA_SCROLL (*(volatile uint32_t *)0x10034010)  // the text row shown at the top (0..74)
#define VGA_COLS 100
#define VGA_ROWS 75
#define VGA_CELLS 7500

enum { BLACK, BLUE, GREEN, CYAN, RED, MAGENTA, BROWN, LGREY, DGREY, LBLUE, LGREEN, LCYAN, LRED, LMAGENTA, YELLOW, WHITE };
#define CELL(ch, fg, bg) ((uint16_t)((uint8_t)(ch) | ((fg) << 8) | ((bg) << 12)))
#define QUARTER 0x80                                   // + 4 bits: a quarter-block character

static uint32_t mul100(uint32_t y) { return (y << 6) + (y << 5) + (y << 2); }   // 64 + 32 + 4, no multiplier

static void vga_put(int x, int y, char ch, int fg, int bg) { VGA_TEXT[mul100((uint32_t)y) + (uint32_t)x] = CELL(ch, fg, bg); }

static void vga_text(int x, int y, const char *s, int fg, int bg)
{
  volatile uint16_t *p = &VGA_TEXT[mul100((uint32_t)y) + (uint32_t)x];
  while (*s && x++ < VGA_COLS) *p++ = CELL(*s++, fg, bg);
}

// every cell the same, four cells per store
static void vga_fill(uint16_t cell)
{
  uint64_t four = cell | ((uint64_t)cell << 16);
  four |= four << 32;
  for (int i = 0; i < VGA_CELLS / 4; i++) VGA_TEXT64[i] = four;
}

// a run of cells on one row
static void vga_hline(int x, int y, int n, uint16_t cell)
{
  volatile uint16_t *p = &VGA_TEXT[mul100((uint32_t)y) + (uint32_t)x];
  while (n--) *p++ = cell;
}

// wait until the next vertical blank begins: the beam then spends 28 lines (29,568 clocks) off screen, and whatever
// is stored during that time shows up whole in the next frame
static uint32_t vga_wait_frame(void)
{
  uint32_t f = VGA_FRAME;
  while (VGA_FRAME == f)
    ;
  return f + 1;
}

// one "pixel" of the 200 x 150 quarter-block grid, in colour fg. The cell keeps its other three quarters (read back
// from the text RAM) and its background; the foreground is per cell, so the latest colour wins for all four.
static void vga_plot(int px, int py, int fg)
{
  volatile uint16_t *p = &VGA_TEXT[mul100((uint32_t)(py >> 1)) + (uint32_t)(px >> 1)];
  uint16_t c = *p;
  uint8_t q = (uint8_t)(((c & 0xF0) == QUARTER) ? (c & 0x0F) : 0);
  q |= (uint8_t)(1u << ((px & 1) | ((py & 1) << 1)));
  *p = (uint16_t)((c & 0xF000) | (fg << 8) | QUARTER | q);
}

#endif
