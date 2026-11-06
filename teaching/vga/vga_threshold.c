// VGA project 6: where does a digital input switch from 0 to 1? RV64I only (start.S).
// Board build: PMOD_VGA=1 (make mcu0-bit APP=vga_threshold). The joystick of project 5, wired the same way; only its
// X axis (A0) is used.
//
// On the PYNQ-Z1 the header pin A0 goes to two FPGA pins: through the divider to the XADC (how many volts), and
// straight to Y11, read here as an ordinary 3.3 V digital input (0 or 1). The same voltage is measured both ways.
// For every XADC sequence (~0.16 ms on the board) mcu_adc counts the clocks in which the digital pin read 1; that
// count over the sequence's length is "the fraction of the time the pin read 1", next to the voltage averaged over the
// same sequence. Move the stick slowly through the threshold and back:
//   - top: the whole range 0..3.3 V, one column per 64 ADC steps (52 mV). Blue: 0.8..2.0 V, where LVCMOS33 promises
//     neither 0 nor 1.
//   - below: zoomed in around the threshold, 1, 2, 4 or 8 steps (0.8..6.4 mV) per column.
//   - green: readings taken while the voltage was rising, cyan: falling, white: both at the same height.
//   - right: the voltage now, the pin now, the fraction, how often the pin flips per second, where it went 0 -> 1 and
//     1 -> 0 (the fraction crossing 50%), the gap between the two (hysteresis), and the band where it is neither.
// BTN0 clears everything, BTN1 changes the zoom, BTN2 centres the zoom on the voltage now. Once both flips have been
// seen the zoom centres on them by itself (once; BTN0 starts over).
// LEDs: LED0 heartbeat, LED1 screen drawn, LED2 the pin now (GPIO IN bit 7), LED3 both flips seen. JB byte (not on
// any pin while JB carries the VGA): the middle of the two flips in units of 16 ADC steps, 0 until both are seen --
// the testbench checks it.
// Like every VGA app here: stores only right after a frame begins, prepared beforehand, four panel cells per store.
// Between frames the CPU does nothing but take every new sequence (sample()). Whatever else it does is time in which
// it sees no sequences, so that is kept short: one panel line per frame (decimal numbers are slow without a divider:
// all ten lines at once took a third of a frame), and the fraction with a 9-round division instead of udiv's 64.
#include "vga.h"
#include "adc.h"

#ifndef HEART_FRAMES
#define HEART_FRAMES 30         // LED0 toggles every half second (simulation: every frame)
#endif
#define GX     6                // both plots: columns GX .. GX+63
#define A_TOP  5                // the whole range: rows A_TOP .. A_TOP+16, 100% at the top, 0% at the bottom
#define B_TOP  28               // zoomed
#define ROWS   17
#define PX     72               // the panel: a multiple of 4, so a row of it is whole doublewords
#define PW     28
#define PLINES 10
#define LX     4                // the zoom's scale line, row B_TOP+18, columns LX .. LX+67: 17 doublewords
#define LW     68
#define NCOL   8                // plot columns redrawn per frame, 17 stores each
#define CENTRE0 1738            // the zoom's first centre, 1.4 V: a guess until both flips are seen
#define BLUE_LO 16              // whole-range columns entirely between 0.8 V (993) and 2.0 V (2482)
#define BLUE_HI 37

static int val[2][2][64];       // [whole, zoom][rising, falling][column]: fraction of 1s, 0..256, smoothed; -1 none
static uint64_t dirty[2];       // columns to redraw
static uint64_t shown[2];       // columns that show a reading (only these need clearing)
static int rr;                  // where the next search for dirty columns starts, 0..127
static int qn, qaddr[NCOL];     // the columns prepared for the next frame
static uint16_t qcell[NCOL][ROWS];
static char panel[PLINES][PW + 1], num[24], lab[LW + 1];
static uint64_t cells[PLINES][PW / 4], lcells[LW / 4];
static const int prow[PLINES] = { 5, 7, 9, 11, 14, 16, 18, 21, 22, 25 };
static const int pcol[PLINES] = { WHITE, WHITE, WHITE, WHITE, LGREEN, LCYAN, WHITE, WHITE, WHITE, LGREY };
static int label_due, pline;    // pline: the panel line prepared and written this time round

// what sample() keeps
static int rising = 1, xr = -1, state = -1, last_x, centred;
static int up_x = -1, down_x = -1, band_lo = 4096, band_hi = -1;
static uint32_t last_ones, last_cyc, flips_acc, seq_acc;
static int zsh = 1, zlo;        // zoom: 1 << zsh steps per column, starting at ADC value zlo

static uint32_t mv(uint32_t x) { return ((x << 11) + (x << 10) + (x << 7) + (x << 6) + (x << 5) + (x << 2)) >> 12; }   // * 3300 / 4096
static uint32_t mv10(uint32_t n) { return ((n << 15) + (n << 7) + (n << 6) + (n << 5) + (n << 3)) >> 12; }           // * 33000 / 4096: tenths of a mV

// ones * 256 / cyc, 0..256 (ones <= cyc): the answer has 9 bits, so 8 rounds of shift-and-subtract are enough
static int frac256(uint32_t ones, uint32_t cyc)
{
  if (ones >= cyc) return 256;
  uint32_t r = ones, q = 0;
  for (int i = 0; i < 8; i++) {
    r <<= 1; q <<= 1;
    if (r >= cyc) { r -= cyc; q |= 1; }
  }
  return (int)q;
}

static void touch(int plot, int col, int p)
{
  int *v = &val[plot][rising ? 0 : 1][col];
  *v = *v < 0 ? p : *v + ((p - *v) >> 2);                // smoothed: each new reading counts a quarter
  dirty[plot] |= 1ull << col;
}

// one XADC sequence: its average voltage and how much of it the digital pin read 1
static void sample(void)
{
  uint32_t c, x, ones, cyc, fl;
  do { c = ADC_COUNT; x = ADC_X; ones = ADC_ONES; cyc = ADC_CYCLES; fl = ADC_FLIPS; } while (ADC_COUNT != c);
  if (cyc == 0) return;
  int p = frac256(ones, cyc);
  int xi = (int)x;
  // rising or falling: the voltage must move 8 steps against the current direction to turn it round (ADC noise)
  if (xr < 0) xr = xi;
  if (rising) { if (xi > xr) xr = xi; else if (xi <= xr - 8) { rising = 0; xr = xi; } }
  else        { if (xi < xr) xr = xi; else if (xi >= xr + 8) { rising = 1; xr = xi; } }
  // the flips: the fraction crossing one half
  int s = p >= 128;
  if (state >= 0 && s != state) { if (s) up_x = xi; else down_x = xi; }
  state = s;
  if (ones != 0 && ones != cyc) { if (xi < band_lo) band_lo = xi; if (xi > band_hi) band_hi = xi; }
  flips_acc += fl; seq_acc++;
  last_x = xi; last_ones = ones; last_cyc = cyc;
  touch(0, xi >> 6, p);
  int z = xi - zlo;
  if (z >= 0 && (z >> zsh) < 64) touch(1, z >> zsh, p);
}

static void clear_plot(int plot)
{
  for (int s = 0; s < 2; s++)
    for (int i = 0; i < 64; i++) val[plot][s][i] = -1;
  dirty[plot] |= shown[plot];
}

static void set_zoom(int centre)
{
  zlo = centre - (32 << zsh);
  if (zlo < 0) zlo = 0;
  if (zlo > 4096 - (64 << zsh)) zlo = 4096 - (64 << zsh);
  clear_plot(1);
  label_due = 1;
}

static void clear_all(void)
{
  clear_plot(0);
  up_x = down_x = -1; band_lo = 4096; band_hi = -1; state = -1; centred = 0;
  set_zoom(CENTRE0);
}

static uint16_t background(int plot, int col, int row)
{
  int bg = (plot == 0 && col >= BLUE_LO && col <= BLUE_HI) ? BLUE : BLACK;
  return CELL(row == 8 ? '.' : ' ', DGREY, bg);         // the dotted row is 50%
}

static int row_of(int v) { return v < 0 ? -1 : 16 - (v >> 4); }

// the next frame's columns: up to NCOL dirty ones, round robin over both plots
static void pick_columns(void)
{
  qn = 0;
  for (int n = 0; n < 128 && qn < NCOL; n++) {
    int k = (rr + n) & 127, plot = k >> 6, col = k & 63;
    if (!((dirty[plot] >> col) & 1)) continue;
    dirty[plot] &= ~(1ull << col);
    int ru = row_of(val[plot][0][col]), rd = row_of(val[plot][1][col]);
    if (ru >= 0 || rd >= 0) shown[plot] |= 1ull << col; else shown[plot] &= ~(1ull << col);
    for (int r = 0; r < ROWS; r++)
      qcell[qn][r] = (r == ru && r == rd) ? CELL(' ', WHITE, WHITE) : r == ru ? CELL(' ', WHITE, LGREEN)
                   : r == rd ? CELL(' ', WHITE, LCYAN) : background(plot, col, r);
    qaddr[qn++] = (int)mul100((uint32_t)(plot ? B_TOP : A_TOP)) + GX + col;
    rr = (k + 1) & 127;
  }
}

static void line(int i, const char *label, const char *value)
{
  char *p = append(panel[i], label);
  p = append(p, value);
  while (p < panel[i] + PW) *p++ = ' ';
  *p = 0;
}

static char *at(char *d, int x)                         // "1712 = 1379 MV"
{
  d = append(d, fmt_fixed(num, (uint64_t)x, 0, 4)); d = append(d, " = ");
  d = append(d, fmt_fixed(num, mv((uint32_t)x), 0, 4)); return append(d, " MV");
}

// panel line i, and its cells
static void prepare(int i, int pin, uint32_t rate, uint32_t seqs)
{
  char v[40], *p;
  if (i == 0) { at(v, last_x); line(0, "A0 ADC  ", v); }
  if (i == 1) line(1, "A0 PIN  ", pin ? "1   (GPIO IN BIT 7)" : "0   (GPIO IN BIT 7)");
  if (i == 2) {
    uint32_t o = last_ones;
    uint32_t pc = last_cyc ? (uint32_t)udiv((uint64_t)((o << 10) - (o << 4) - (o << 3)), last_cyc, 0) : 0;   // * 1000
    p = append(v, fmt_fixed(num, pc, 1, 5)); append(p, " %");
    line(2, "ONES    ", v);
  }
  if (i == 3) line(3, "FLIPS/S ", fmt_fixed(num, rate, 0, 7));
  if (i == 4) { if (up_x >= 0) at(v, up_x); else append(v, "-"); line(4, "0->1 AT ", v); }
  if (i == 5) { if (down_x >= 0) at(v, down_x); else append(v, "-"); line(5, "1->0 AT ", v); }
  if (i == 6) {
    if (up_x >= 0 && down_x >= 0) {
      int g = up_x - down_x, a = g < 0 ? -g : g;
      p = append(v, g < 0 ? "-" : "+"); p = append(p, fmt_fixed(num, (uint64_t)a, 0, 0)); p = append(p, " STEPS = ");
      p = append(p, fmt_fixed(num, mv10((uint32_t)a), 1, 0)); append(p, " MV");
    } else append(v, "-");
    line(6, "GAP     ", v);
  }
  if (i == 7) {
    if (band_hi >= 0) {
      p = append(v, fmt_fixed(num, (uint64_t)band_lo, 0, 4)); p = append(p, " .. "); append(p, fmt_fixed(num, (uint64_t)band_hi, 0, 4));
    } else append(v, "-");
    line(7, "BAND    ", v);
  }
  if (i == 8) {
    if (band_hi >= 0) {
      uint32_t w = (uint32_t)(band_hi - band_lo);
      p = append(v, fmt_fixed(num, w, 0, 4)); p = append(p, " STEPS = "); p = append(p, fmt_fixed(num, mv10(w), 1, 0)); append(p, " MV");
    } else v[0] = 0;
    line(8, "        ", v);
  }
  if (i == 9) line(9, "SEQ/S   ", seqs ? fmt_fixed(num, seqs, 0, 6) : "     -");
  for (int k = 0; k < PW / 4; k++) {
    uint64_t w = 0;
    for (int j = 3; j >= 0; j--) w = (w << 16) | CELL(panel[i][4 * k + j], pcol[i], BLACK);
    cells[i][k] = w;
  }
}

// the zoom's scale line: the voltage at both ends and the size of a column
static void prepare_label(void)
{
  char t[32], *p;
  for (int i = 0; i < LW; i++) lab[i] = ' ';
  lab[LW] = 0;
  p = append(t, fmt_fixed(num, mv((uint32_t)zlo), 0, 0)); append(p, " MV");             // left end, under column 0
  for (int i = 0; t[i]; i++) lab[2 + i] = t[i];
  p = append(t, fmt_fixed(num, mv10(1u << zsh), 1, 0)); p = append(p, " MV (");          // the middle
  p = append(p, fmt_fixed(num, 1u << zsh, 0, 0)); append(p, " STEPS) PER COLUMN");
  for (int i = 0; t[i]; i++) lab[18 + i] = t[i];
  p = append(t, fmt_fixed(num, mv((uint32_t)(zlo + (64 << zsh) - 1)), 0, 0)); append(p, " MV");   // right end
  int n = 0; while (t[n]) n++;
  for (int i = 0; i < n; i++) lab[66 - n + i] = t[i];
  for (int k = 0; k < LW / 4; k++) {
    uint64_t w = 0;
    for (int j = 3; j >= 0; j--) w = (w << 16) | CELL(lab[4 * k + j], LGREY, BLACK);
    lcells[k] = w;
  }
}

static void static_screen(void)
{
  vga_fill(CELL(' ', WHITE, BLACK));
  vga_text(0, 1, "WHERE DOES A DIGITAL INPUT SWITCH?  A0 READ TWICE: BY THE XADC (VOLTS) AND BY PIN Y11 (0 OR 1)", YELLOW, BLACK);
  vga_text(0, 3, "WHOLE RANGE: % OF THE TIME THE PIN READ 1, AGAINST THE VOLTAGE (ONE COLUMN = 52 MV)", LGREY, BLACK);
  vga_text(0, 26, "ZOOMED IN AROUND THE THRESHOLD", LGREY, BLACK);
  for (int k = 0; k < 2; k++) {
    int t = k ? B_TOP : A_TOP;
    vga_text(0, t, "100%", LGREY, BLACK); vga_text(1, t + 8, "50%", LGREY, BLACK); vga_text(2, t + 16, "0%", LGREY, BLACK);
    for (int r = 0; r < ROWS; r++)
      for (int c = 0; c < 64; c++) VGA_TEXT[mul100((uint32_t)(t + r)) + GX + c] = background(k, c, r);
  }
  vga_text(GX, A_TOP + 18, "0 V", LGREY, BLACK);
  vga_text(GX + BLUE_LO - 1, A_TOP + 18, "0.8 V", LGREY, BLACK);
  vga_text(GX + BLUE_HI - 1, A_TOP + 18, "2.0 V", LGREY, BLACK);
  vga_text(GX + 60, A_TOP + 18, "3.3 V", LGREY, BLACK);
  vga_text(GX + BLUE_LO + 2, A_TOP + 19, "BLUE: NO PROMISE", BLUE, BLACK);
  static const char *const legend[] = {
    "GREEN: VOLTAGE RISING", "CYAN:  VOLTAGE FALLING", "WHITE: BOTH THE SAME", "",
    "LVCMOS33 PROMISES 0 BELOW", "0.8 V AND 1 ABOVE 2.0 V.", "BETWEEN: WHATEVER THIS", "CHIP DOES. MEASURE IT.", "",
    "MOVE THE STICK SLOWLY UP", "THROUGH THE THRESHOLD", "AND BACK DOWN.", "",
    "BTN0 CLEAR   BTN1 ZOOM", "BTN2 ZOOM ON THE VOLTAGE NOW" };
  for (int i = 0; i < 15; i++)
    vga_text(PX, 29 + i, legend[i], i == 0 ? LGREEN : i == 1 ? LCYAN : LGREY, BLACK);
  vga_text(0, 50, "THE CURVE: FOR EACH XADC SEQUENCE (ABOUT 0.16 MS) THE HARDWARE COUNTS THE CLOCKS IN WHICH THE PIN", LGREY, BLACK);
  vga_text(0, 51, "READ 1. A STEP STRAIGHT FROM 0% TO 100% WOULD BE AN IDEAL INPUT; THE SLOPE IS NOISE AT THE THRESHOLD.", LGREY, BLACK);
  vga_text(0, 52, "GAP: WHERE IT WENT 0->1 RISING MINUS WHERE IT WENT 1->0 FALLING. NEAR 0 MEANS NO HYSTERESIS.", LGREY, BLACK);
}

int main(void)
{
  static_screen();
  clear_all();
  for (int i = 0; i < PLINES; i++) prepare(i, 0, 0, 0);
  pick_columns();
  int ca = -1, cb = -2, heart = 0, frames = 0;
  uint8_t led0 = 0;
  uint32_t seen = ADC_COUNT, rate = 0, seqs = 0, prevb = 0;
  for (;;) {
    // ---- until the frame begins: take every sequence
    uint32_t f = VGA_FRAME;
    while (VGA_FRAME == f)
      if (ADC_COUNT != seen) { seen = ADC_COUNT; sample(); }
    int na = last_x >> 6, nb = last_x - zlo;
    nb = nb < 0 ? -1 : (nb >> zsh) > 63 ? 64 : nb >> zsh;
    // ---- the stores
    {
      volatile uint64_t *d = &VGA_TEXT64[(mul100((uint32_t)prow[pline]) + PX) >> 2];
      for (int k = 0; k < PW / 4; k++) d[k] = cells[pline][k];
    }
    for (int q = 0; q < qn; q++) {
      volatile uint16_t *d = &VGA_TEXT[qaddr[q]];
      for (int r = 0; r < ROWS; r++) { *d = qcell[q][r]; d += VGA_COLS; }
    }
    if (label_due == 2) {
      volatile uint64_t *d = &VGA_TEXT64[(mul100(B_TOP + 18) + LX) >> 2];
      for (int k = 0; k < LW / 4; k++) d[k] = lcells[k];
      label_due = 0;
    }
    if (ca != na) {                                      // the cursors: where the voltage is now
      if (ca >= 0) VGA_TEXT[mul100(A_TOP + 17) + GX + ca] = CELL(' ', WHITE, BLACK);
      VGA_TEXT[mul100(A_TOP + 17) + GX + na] = CELL('^', YELLOW, BLACK);
      ca = na;
    }
    if (cb != nb) {
      if (cb > -2) VGA_TEXT[mul100(B_TOP + 17) + GX + (cb < 0 ? 0 : cb > 63 ? 63 : cb)] = CELL(' ', WHITE, BLACK);
      VGA_TEXT[mul100(B_TOP + 17) + GX + (nb < 0 ? 0 : nb > 63 ? 63 : nb)] = CELL(nb < 0 ? '<' : nb > 63 ? '>' : '^', YELLOW, BLACK);
      cb = nb;
    }
    // ---- after the stores: LEDs, buttons, once a second the rates, everything for the next frame
    int pin = (BUTTONS & A0_PIN) != 0;
    if (++heart >= HEART_FRAMES) { heart = 0; led0 ^= 1; }
    int both = up_x >= 0 && down_x >= 0;
    LEDS = (uint8_t)(led0 | 2 | (pin ? 4 : 0) | (both ? 8 : 0));
    int mid = (up_x + down_x) >> 1;
    JB = (uint8_t)(both ? mid >> 4 : 0);
    uint32_t b = (uint32_t)BUTTONS & 7, pressed = b & ~prevb;
    prevb = b;
    if (pressed & 1) clear_all();
    if (pressed & 2) { int c = zlo + (32 << zsh); zsh = (zsh + 1) & 3; set_zoom(c); }   // same centre, next scale
    if (pressed & 4) { centred = 1; set_zoom(last_x); }
    if (!centred && both) { centred = 1; set_zoom(mid); }
    if (++frames == 60) { frames = 0; rate = flips_acc; seqs = seq_acc; flips_acc = 0; seq_acc = 0; }
    if (++pline == PLINES) pline = 0;
    prepare(pline, pin, rate, seqs);
    if (label_due == 1) { prepare_label(); label_due = 2; }
    pick_columns();
  }
}
