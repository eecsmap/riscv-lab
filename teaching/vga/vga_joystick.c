// VGA project 5, part 1: an analog joystick through the XADC, shown on the monitor. RV64I only (start.S).
// Board build: PMOD_VGA=1 (make mcu0-bit APP=vga_joystick). Joystick on the Arduino header: GND, +5V -> 3.3V (not
// 5 V!), VRx -> A0, VRy -> A1, SW -> D4.
//
// Left: a 64 x 64-cell box; the dot is where the stick is (X = A0 to the right, Y = A1 downwards, 64 ADC steps per
// cell). The dotted square is the dead zone: inside it the stick counts as "not pushed". The dot turns green when a
// direction counts, red while the stick is pressed down.
// Right: the raw readings, the voltage at the pin, the centre found at reset, the direction, the die temperature and
// how many conversion sequences the XADC completes per second.
// Like every VGA app here: stores only right after a frame begins, slow work (decimal numbers) after the stores. The
// panel goes out four cells per store: one cell at a time it would not fit in the blank (see the README).
// LEDs: LED0 heartbeat, LED1 screen drawn, LED2 a joystick was found at reset, LED3 pushed or pressed. The JB byte of
// GPIO OUT (not on any pin while JB carries the VGA) = direction (0 right .. 3 up, 4 none) + 16 if pressed: the
// testbench checks it.
#include "vga.h"
#include "adc.h"

#ifndef HEART_FRAMES
#define HEART_FRAMES 30         // LED0 toggles every half second (simulation: every frame)
#endif
#define BX 2                    // the box: cells (BX .. BX+63, BY .. BY+63)
#define BY 6
#define PX 68                   // the panel's left column: a multiple of 4, so a row of it is whole doublewords
#define PW 28                   // its width, 7 doublewords
#define PLINES 9

static struct joystick joy;
static char panel[PLINES][PW + 1], num[24];
static uint64_t cells[PLINES][PW / 4];    // the panel as cells, four to a doubleword: 63 stores in the blank, not 252
static const int prow[PLINES] = { 6, 8, 11, 13, 16, 18, 21, 23, 26 };

static int on_square(int x, int y)        // the dead zone's border, in cells of the box
{
  int r = JOY_ON >> 6, ox = x - (joy.cx >> 6), oy = y - (joy.cy >> 6);
  return ((ox == -r || ox == r) && oy >= -r && oy <= r) || ((oy == -r || oy == r) && ox >= -r && ox <= r);
}

static uint16_t background(int x, int y)  // what the box shows at (x, y) without the dot
{
  if (joy.present && x == (joy.cx >> 6) && y == (joy.cy >> 6)) return CELL('+', LGREY, BLACK);
  if (joy.present && on_square(x, y)) return CELL('.', DGREY, BLACK);
  return CELL(' ', WHITE, BLACK);
}

static void draw_box(void)
{
  for (int i = -1; i <= 64; i++) {
    vga_put(BX + i, BY - 1, ' ', WHITE, DGREY); vga_put(BX + i, BY + 64, ' ', WHITE, DGREY);
    vga_put(BX - 1, BY + i, ' ', WHITE, DGREY); vga_put(BX + 64, BY + i, ' ', WHITE, DGREY);
  }
  for (int y = 0; y < 64; y++)
    for (int x = 0; x < 64; x++)
      VGA_TEXT[mul100((uint32_t)(BY + y)) + (uint32_t)(BX + x)] = background(x, y);
  vga_text(BX, BY + 65, "X = A0 ->   Y = A1 DOWN   ONE CELL = 64 STEPS", LGREY, BLACK);
  vga_text(BX, BY + 66, "DOTTED: THE DEAD ZONE, +-800 STEPS FROM THE CENTRE", LGREY, BLACK);
}

static char *sgn(char *d, int v, int width)              // "+123" / "-123", right-aligned
{
  char t[24];
  fmt_fixed(t, (uint64_t)iabs(v), 0, 0);
  int n = 0; while (t[n]) n++;
  for (int i = n + 1; i < width; i++) *d++ = ' ';
  *d++ = v < 0 ? '-' : '+';
  return append(d, t);
}

static void line(int i, const char *label, const char *value)
{
  char *p = append(panel[i], label);
  p = append(p, value);
  while (p < panel[i] + PW) *p++ = ' ';
  *p = 0;
}

static const char *const dir_name[5] = { "RIGHT", "DOWN", "LEFT", "UP", "-" };

// everything slow: the panel's text, ready for the next frame
static void prepare(uint32_t x, uint32_t y, uint32_t temp, int click, uint32_t rate)
{
  char v[32], *p;
  p = append(v, fmt_fixed(num, x, 0, 4)); p = append(p, "  ");
  p = append(p, fmt_fixed(num, (x << 11) + (x << 10) + (x << 7) + (x << 6) + (x << 5) + (x << 2) >> 12, 0, 4));  // * 3300 / 4096
  append(p, " MV");
  line(0, "A0 X   ", v);
  p = append(v, fmt_fixed(num, y, 0, 4)); p = append(p, "  ");
  p = append(p, fmt_fixed(num, (y << 11) + (y << 10) + (y << 7) + (y << 6) + (y << 5) + (y << 2) >> 12, 0, 4));
  append(p, " MV");
  line(1, "A1 Y   ", v);
  p = append(v, fmt_fixed(num, (uint64_t)joy.cx, 0, 4)); p = append(p, "  "); append(p, fmt_fixed(num, (uint64_t)joy.cy, 0, 4));
  line(2, "CENTRE ", joy.present ? v : "NONE");
  p = sgn(v, joy.dx, 6); p = append(p, " "); sgn(p, joy.dy, 6);
  line(3, "DX DY ", v);
  line(4, "DIR    ", dir_name[joy.dir]);
  line(5, "CLICK  ", click ? "YES" : "NO");
  uint64_t t10 = ((uint64_t)temp << 12) + ((uint64_t)temp << 9) + ((uint64_t)temp << 8) + ((uint64_t)temp << 7)
               + ((uint64_t)temp << 5) + ((uint64_t)temp << 4);                       // * 5040: tenths of 504 C
  t10 >>= 12;
  p = append(v, t10 > 2732 ? fmt_fixed(num, t10 - 2732, 1, 5) : "  ---"); append(p, " C");
  line(6, "CHIP   ", v);
  line(7, "SEQ/S  ", rate ? fmt_fixed(num, rate, 0, 6) : "     -");
  line(8, "", joy.present ? "" : "NO JOYSTICK FOUND AT RESET");
  for (int i = 0; i < PLINES; i++)
    for (int k = 0; k < PW / 4; k++) {
      uint64_t w = 0;
      for (int j = 3; j >= 0; j--) w = (w << 16) | CELL(panel[i][4 * k + j], i == 8 ? LRED : WHITE, BLACK);
      cells[i][k] = w;
    }
}

int main(void)
{
  vga_fill(CELL(' ', WHITE, BLACK));
  joy_init(&joy);
  vga_text(BX - 1, 1, "JOYSTICK ON THE XADC   A0 = X, A1 = Y, D4 = CLICK   12 BITS, 0..4095 = 0..3.3 V", YELLOW, BLACK);
  vga_text(BX - 1, 2, "POWER IT FROM 3.3 V, NOT 5 V", LRED, BLACK);
  draw_box();
  prepare(ADC_X, ADC_Y, ADC_TEMP, 0, 0);
  int ox = -1, oy = -1, frames = 0, heart = 0;
  uint8_t led0 = 0;
  uint32_t count0 = ADC_COUNT, rate = 0;
  for (;;) {
    // ---- read, then decide where the dot goes (cheap); the frame begins; the stores
    uint32_t x = ADC_X, y = ADC_Y, temp = ADC_TEMP;
    int click = (BUTTONS & JOY_SW) != 0;
    joy_read(&joy);
    int nx = (int)(x >> 6), ny = (int)(y >> 6);
    int colour = click ? LRED : joy.dir != JOY_NONE ? LGREEN : YELLOW;
    vga_wait_frame();
    for (int i = 0; i < PLINES; i++) {
      volatile uint64_t *d = &VGA_TEXT64[(mul100((uint32_t)prow[i]) + PX) >> 2];
      for (int k = 0; k < PW / 4; k++) d[k] = cells[i][k];
    }
    if (ox >= 0 && (ox != nx || oy != ny))
      VGA_TEXT[mul100((uint32_t)(BY + oy)) + (uint32_t)(BX + ox)] = background(ox, oy);
    VGA_TEXT[mul100((uint32_t)(BY + ny)) + (uint32_t)(BX + nx)] = CELL(' ', WHITE, colour);
    ox = nx; oy = ny;
    // ---- after the stores: LEDs, the rate once a second, the panel for the next frame
    if (++heart >= HEART_FRAMES) { heart = 0; led0 ^= 1; }
    LEDS = (uint8_t)(led0 | 2 | (joy.present ? 4 : 0) | (click || joy.dir != JOY_NONE ? 8 : 0));
    JB = (uint8_t)(joy.dir | (click << 4));
    if (++frames == 60) { frames = 0; uint32_t c = ADC_COUNT; rate = c - count0; count0 = c; }
    prepare(x, y, temp, click, rate);
  }
}
