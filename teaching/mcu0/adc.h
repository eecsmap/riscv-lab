// The XADC and an analog joystick on MCU-0 (teaching/mcu0/mcu_adc.v; wiring in teaching/vga/README.md, project 5).
// RV64I only. A joystick is two potentiometers: each axis is a voltage, 0..3.3 V, about half way at rest. The XADC
// turns it into 0..4095; this file turns that into "pushed left / right / up / down, or not".
#ifndef ADC_H
#define ADC_H
#include "mcu0.h"

#define ADC_X     (*(volatile uint32_t *)0x10040000)   // A0, 0..4095 = 0..3.3 V
#define ADC_Y     (*(volatile uint32_t *)0x10040008)   // A1
#define ADC_TEMP  (*(volatile uint32_t *)0x10040010)   // die temperature, raw
#define ADC_COUNT (*(volatile uint32_t *)0x10040018)   // sequences completed: changes when X, Y, TEMP are fresh
#define JOY_SW    (1u << 6)                            // GPIO IN bit 6: the stick pressed down (Arduino D4)
// A0 read a second way, as a digital input (pin Y11; VGA project 6, teaching/vga/vga_threshold.c)
#define A0_PIN    (1u << 7)                            // GPIO IN bit 7: A0 as an ordinary GPIO input, 0 or 1
#define ADC_ONES   (*(volatile uint32_t *)0x10040028)  // clocks during the last sequence in which the pin read 1
#define ADC_CYCLES (*(volatile uint32_t *)0x10040030)  // clocks in that sequence
#define ADC_FLIPS  (*(volatile uint32_t *)0x10040038)  // how often the pin changed during it

// which way the board's X and Y run depends on how the joystick is held; vga_joystick shows the raw numbers
#ifndef JOY_SWAP_XY
#define JOY_SWAP_XY 0
#endif
#ifndef JOY_FLIP_X
#define JOY_FLIP_X 0            // 1: X grows to the left
#endif
#ifndef JOY_FLIP_Y
#define JOY_FLIP_Y 0            // 1: Y grows upwards
#endif

// Where the stick rests is not the middle of 0..4095. On the PYNQ-Z1, A0..A5 go through a resistor divider to
// ground, a few kilohms, and that load pulls a 10 k potentiometer's middle position down: measured, 0.75 V instead of
// 1.65 V (X = 935, Y = 1007), while the ends still reach 12 and ~3980. So from the centre there is about 900 steps of
// travel one way and 3000 the other, and a dead zone in fixed steps would be wrong on one side.
// The stick's position is therefore counted as a fraction of the travel on its side: 1024 = all the way.
// Dead zone with hysteresis: a direction starts at JOY_ON (40% of the way), and ends only back within JOY_OFF (20%).
// Between the two nothing changes, so noise near one threshold cannot make the direction flicker on and off.
#define JOY_ON  410
#define JOY_OFF 205
enum { JOY_RIGHT, JOY_DOWN, JOY_LEFT, JOY_UP, JOY_NONE };   // the same order as the snake's directions

struct joystick {
  int present, cx, cy;          // found at reset; the rest position
  int dx, dy;                   // the last reading, raw steps from the centre (after JOY_SWAP/FLIP)
  int nx, ny;                   // the same as a fraction of the travel on that side, -1024 .. 1024
  int dir;
};

// wait for a fresh conversion, at most ~1 ms (if the XADC is not running, COUNT never moves)
static void adc_fresh(void)
{
  uint32_t c = ADC_COUNT;
  uint64_t until = CLINT_MTIME + CLOCK_KHZ;
  while (ADC_COUNT == c && (int64_t)(CLINT_MTIME - until) < 0)
    ;
}

// Nothing plugged in reads near 0 V (the board's divider pulls the pin down); a joystick at rest reads clearly above
// 0 V and below 3.3 V on both axes. Calibrate: the rest position, averaged over 16 readings, is the centre from now on.
#define JOY_MIN_REST 300        // 0.24 V
#define JOY_MAX_REST 3795       // 3.06 V
static void joy_init(struct joystick *j)
{
  int sx = 0, sy = 0;
  for (int i = 0; i < 16; i++) { adc_fresh(); sx += (int)ADC_X; sy += (int)ADC_Y; }
  j->cx = sx >> 4; j->cy = sy >> 4;
  j->present = j->cx > JOY_MIN_REST && j->cx < JOY_MAX_REST && j->cy > JOY_MIN_REST && j->cy < JOY_MAX_REST;
  j->dx = j->dy = j->nx = j->ny = 0; j->dir = JOY_NONE;
}

static int iabs(int v) { return v < 0 ? -v : v; }

// d steps from centre c, as a fraction (1024 = the end) of the travel on that side: c below, 4095 - c above
static int joy_frac(int d, int c)
{
  if (d >= 0) return (int)udiv((uint64_t)d << 10, (uint64_t)(4095 - c), 0);
  return -(int)udiv((uint64_t)(-d) << 10, (uint64_t)c, 0);
}

// read the stick; returns its direction (JOY_NONE in the dead zone, or with no joystick)
static int joy_read(struct joystick *j)
{
  if (!j->present) return j->dir = JOY_NONE;
  int dx = (int)ADC_X - j->cx, dy = (int)ADC_Y - j->cy;
  int nx = joy_frac(dx, j->cx), ny = joy_frac(dy, j->cy);
  if (JOY_SWAP_XY) { int t = dx; dx = dy; dy = t; t = nx; nx = ny; ny = t; }
  if (JOY_FLIP_X) { dx = -dx; nx = -nx; }
  if (JOY_FLIP_Y) { dy = -dy; ny = -ny; }
  j->dx = dx; j->dy = dy; j->nx = nx; j->ny = ny;
  int far = iabs(nx) > iabs(ny) ? iabs(nx) : iabs(ny);
  if (far >= JOY_ON)                                     // clearly pushed: the axis pushed further wins
    j->dir = iabs(nx) > iabs(ny) ? (nx > 0 ? JOY_RIGHT : JOY_LEFT) : (ny > 0 ? JOY_DOWN : JOY_UP);
  else if (far < JOY_OFF)
    j->dir = JOY_NONE;                                   // back in the middle
  return j->dir;                                         // in between: keep what it was
}

#endif
