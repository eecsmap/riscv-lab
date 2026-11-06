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

// Dead zone with hysteresis, in ADC steps away from the centre (4096 steps = 3.3 V): a direction starts when the
// stick is JOY_ON from the middle, and ends only when it is back within JOY_OFF. Between the two nothing changes, so
// noise of a few steps near one threshold cannot make the direction flicker on and off.
#define JOY_ON  800
#define JOY_OFF 400
enum { JOY_RIGHT, JOY_DOWN, JOY_LEFT, JOY_UP, JOY_NONE };   // the same order as the snake's directions

struct joystick { int present, cx, cy, dx, dy, dir; };

// wait for a fresh conversion, at most ~1 ms (if the XADC is not running, COUNT never moves)
static void adc_fresh(void)
{
  uint32_t c = ADC_COUNT;
  uint64_t until = CLINT_MTIME + CLOCK_KHZ;
  while (ADC_COUNT == c && (int64_t)(CLINT_MTIME - until) < 0)
    ;
}

// A joystick at rest reads near the middle on both axes; nothing plugged in reads near 0 V (the board's divider pulls
// the pin down). Calibrate: the rest position, averaged over 16 readings, is the centre from now on.
static void joy_init(struct joystick *j)
{
  int sx = 0, sy = 0;
  for (int i = 0; i < 16; i++) { adc_fresh(); sx += (int)ADC_X; sy += (int)ADC_Y; }
  j->cx = sx >> 4; j->cy = sy >> 4;
  j->present = j->cx > 1024 && j->cx < 3072 && j->cy > 1024 && j->cy < 3072;
  j->dx = j->dy = 0; j->dir = JOY_NONE;
}

static int iabs(int v) { return v < 0 ? -v : v; }

// read the stick; returns its direction (JOY_NONE in the dead zone, or with no joystick)
static int joy_read(struct joystick *j)
{
  if (!j->present) return j->dir = JOY_NONE;
  int dx = (int)ADC_X - j->cx, dy = (int)ADC_Y - j->cy;
  if (JOY_SWAP_XY) { int t = dx; dx = dy; dy = t; }
  if (JOY_FLIP_X) dx = -dx;
  if (JOY_FLIP_Y) dy = -dy;
  j->dx = dx; j->dy = dy;
  int far = iabs(dx) > iabs(dy) ? iabs(dx) : iabs(dy);
  if (far >= JOY_ON)                                     // clearly pushed: the axis pushed further wins
    j->dir = iabs(dx) > iabs(dy) ? (dx > 0 ? JOY_RIGHT : JOY_LEFT) : (dy > 0 ? JOY_DOWN : JOY_UP);
  else if (far < JOY_OFF)
    j->dir = JOY_NONE;                                   // back in the middle
  return j->dir;                                         // in between: keep what it was
}

#endif
