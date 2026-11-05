// VGA project 3: snake on a monitor. The game is teaching/oled/oled_snake.c's -- same rules, same buttons, the same
// two-entry turn queue and debouncing -- on a 48 x 34 board of 16 x 16-pixel squares instead of 24 x 14.
// RV64I only (start.S, no CSRs, no interrupts): a step-2 core runs it.
//
// What changes with the display:
//   - The clock is the display's own: one move every `speed` frames (9 = 150 ms at first, down to 4 = 67 ms). The
//     OLED version needs the timer interrupt for its tick; here the frame counter is the tick, polled.
//   - Every move is drawn right after a new frame begins, in the vertical blank: three squares, about 12 stores, a
//     few hundred clocks. No square is ever seen half-drawn. On the OLED a move costs ~35 SPI bytes and 3 ms of waits.
//   - Anything slow (numbers need udiv) is prepared after the stores and written at the next blank.
// Board build: RESET_SW1=1 PMOD_VGA=1 (make mcu0-bit APP=vga_snake adds both).
//   BTN3 left, BTN2 up, BTN1 down, BTN0 right. SW0 up: pause. SW1 up: reset. After a crash any button starts again.
// LEDs: LED0 toggles on every move, LED1..2 = score & 3, LED3 = the game-over screen is up.
#include "vga.h"

#ifndef START_FRAMES
#define START_FRAMES 9          // frames per move at the start: 150 ms
#endif
#ifndef MIN_FRAMES
#define MIN_FRAMES 4            // the fastest: 67 ms
#endif
#define DEBOUNCE_MS 5
#define SW0 (1u << 4)           // GPIO IN = {sw, btn}

#define COLS 48                 // squares of 2 x 2 characters, inside a one-square border
#define ROWS 34
#define CELLS (COLS * ROWS)
#ifndef START_Y
#define START_Y (ROWS / 2)      // the simulation starts near the top, so the scripted crash comes sooner
#endif
#define X0 2                    // character column of square x = 0
#define Y0 4                    // character row of square y = 0 (row 0: status, rows 2-3: the top border)

enum { RIGHT, DOWN, LEFT, UP };
static const int8_t dx[4] = { 1, 0, -1, 0 }, dy[4] = { 0, 1, 0, -1 };
static const uint8_t dir_of_button[4] = { RIGHT, DOWN, UP, LEFT };   // BTN0, BTN1, BTN2, BTN3

#define C_HEAD   LGREEN
#define C_BODY   GREEN
#define C_FOOD   LRED
#define C_BORDER BLUE

// ---- game state
static uint8_t occ[CELLS];
static uint8_t body_x[CELLS], body_y[CELLS];   // ring buffer, tail .. head
static int head, len, dir, score, hi, dead, speed;   // dead: 1 crashed, 2 game-over screen shown
static int food_x, food_y;
static uint8_t queue[2];
static int queued;
static uint16_t lfsr = 0xACE1;

static int cell(int x, int y) { return (y << 5) + (y << 4) + x; }   // y * 48 + x

// one square: 2 x 2 character cells, colour as background
static void square(int x, int y, int colour)
{
  volatile uint16_t *p = &VGA_TEXT[mul100((uint32_t)(Y0 + y + y)) + (uint32_t)(X0 + x + x)];   // x, y can be -1: the border
  uint16_t c = CELL(' ', BLACK, colour);
  p[0] = c; p[1] = c; p[VGA_COLS] = c; p[VGA_COLS + 1] = c;
}

// food: a round dot in the middle of its square -- four quarter blocks, each lighting the corner nearest the centre
static void food(int x, int y)
{
  volatile uint16_t *p = &VGA_TEXT[mul100((uint32_t)(Y0 + y + y)) + (uint32_t)(X0 + x + x)];   // x, y can be -1: the border
  p[0] = CELL(QUARTER | 8, C_FOOD, BLACK);              // bottom-right quarter of the top-left character
  p[1] = CELL(QUARTER | 4, C_FOOD, BLACK);
  p[VGA_COLS] = CELL(QUARTER | 2, C_FOOD, BLACK);
  p[VGA_COLS + 1] = CELL(QUARTER | 1, C_FOOD, BLACK);
}

static uint16_t rnd(void)
{
  lfsr = (uint16_t)((lfsr >> 1) ^ (-(lfsr & 1u) & 0xB400u));
  return lfsr;
}

static void place_food(void)              // a random free square: 11 bits, throw away >= CELLS or occupied
{
  int i;
  do i = rnd() & 2047; while (i >= CELLS || occ[i]);
  food_y = 0;
  while (i >= COLS) { i -= COLS; food_y++; }
  food_x = i;
  food(food_x, food_y);
}

// ---- the status line: prepared whenever it changes, stored at the next vertical blank
static char status[VGA_COLS + 1], num[24];
static int status_ready;

static void prepare_status(void)
{
  char *p = append(status, "SNAKE   SCORE ");
  p = append(p, fmt_fixed(num, (uint64_t)score, 0, 3));
  p = append(p, "   HI ");
  p = append(p, fmt_fixed(num, (uint64_t)hi, 0, 3));
  p = append(p, "   LENGTH ");
  p = append(p, fmt_fixed(num, (uint64_t)len, 0, 4));
  p = append(p, "   SPEED ");
  p = append(p, fmt_fixed(num, udiv(600, (uint64_t)speed, 0), 1, 4));   // 60 frames a second / speed, in tenths
  append(p, " MOVES/S   ");
  status_ready = 1;
}

static void leds(int toggle)
{
  static uint8_t led0;
  led0 ^= (uint8_t)toggle;
  LEDS = (uint8_t)(led0 | ((score & 3) << 1) | (dead == 2 ? 8 : 0));
}

static void new_game(void)
{
  for (int i = 0; i < CELLS; i++) occ[i] = 0;
  vga_fill(CELL(' ', WHITE, BLACK));                    // not tear-free (1.5 ms is longer than a blank); once a game
  for (int x = -1; x <= COLS; x++) { square(x, -1, C_BORDER); square(x, ROWS, C_BORDER); }
  for (int y = 0; y < ROWS; y++) { square(-1, y, C_BORDER); square(COLS, y, C_BORDER); }
  vga_text(2, 74, "BTN3 LEFT  BTN2 UP  BTN1 DOWN  BTN0 RIGHT   SW0 PAUSE   SW1 RESET", DGREY, BLACK);
  len = 3; head = 2; dir = RIGHT; score = 0; dead = 0; queued = 0; speed = START_FRAMES;
  for (int i = 0; i < 3; i++) {
    body_x[i] = (uint8_t)(2 + i); body_y[i] = START_Y;
    occ[cell(2 + i, START_Y)] = 1;
    square(2 + i, START_Y, i == 2 ? C_HEAD : C_BODY);
  }
  food_x = 10; food_y = START_Y;                        // the first food is straight ahead: a test can count on it
  food(food_x, food_y);
  prepare_status();
  vga_text(0, 0, status, YELLOW, BLACK);
  status_ready = 0;
  leds(0);
}

// ---- buttons, exactly as in oled_snake.c
static uint32_t btn_raw, btn_stable;
static uint64_t btn_since;

static void poll_buttons(void)
{
  uint32_t raw = (uint32_t)(BUTTONS & 0xF);
  if (raw != btn_raw) { btn_raw = raw; btn_since = CLINT_MTIME; return; }
  if (raw == btn_stable || CLINT_MTIME - btn_since < (uint64_t)DEBOUNCE_MS * TICKS_PER_MS) return;
  uint32_t pressed = raw & ~btn_stable;
  btn_stable = raw;
  if (pressed) lfsr ^= (uint16_t)CLINT_MTIME | 1;
  for (int b = 0; b < 4; b++) {
    if (!(pressed & (1u << b)) || queued == 2) continue;
    int d = dir_of_button[b], last = queued ? queue[queued - 1] : dir;
    if (d != last && d != (last ^ 2)) queue[queued++] = (uint8_t)d;
  }
}

// one move; only stores while the beam is off screen. Returns 1 if the score changed.
static int move(void)
{
  if (queued) { dir = queue[0]; queue[0] = queue[1]; queued--; }
  int hx = body_x[head] + dx[dir], hy = body_y[head] + dy[dir];
  int tail = head - len + 1; if (tail < 0) tail += CELLS;
  int eat = (hx == food_x && hy == food_y);
  if (hx < 0 || hx >= COLS || hy < 0 || hy >= ROWS ||
      (occ[cell(hx, hy)] && !(!eat && hx == body_x[tail] && hy == body_y[tail]))) {
    dead = 1;
    return 0;
  }
  if (!eat) {
    occ[cell(body_x[tail], body_y[tail])] = 0;
    square(body_x[tail], body_y[tail], BLACK);
  }
  square(body_x[head], body_y[head], C_BODY);
  head = (head == CELLS - 1) ? 0 : head + 1;
  body_x[head] = (uint8_t)hx; body_y[head] = (uint8_t)hy;
  occ[cell(hx, hy)] = 1;
  square(hx, hy, C_HEAD);
  if (!eat) return 0;
  len++; score++;
  if (score > hi) hi = score;
  if (speed > MIN_FRAMES && (score & 1) == 0) speed--;  // a little faster every second food
  place_food();
  return 1;
}

static void game_over(void)
{
  static const char *msg[3] = { "                        ", "       GAME  OVER       ", "  ANY BUTTON: NEW GAME  " };
  prepare_status();
  vga_wait_frame();                                     // all of it in one blank: about 100 stores
  vga_text(0, 0, status, YELLOW, BLACK);
  for (int i = 0; i < 5; i++) vga_hline(37, 34 + i, 26, CELL(' ', WHITE, RED));
  for (int i = 0; i < 3; i++) vga_text(38, 35 + i, msg[i], i == 1 ? YELLOW : WHITE, RED);
  dead = 2;
  leds(0);
}

int main(void)
{
  for (;;) {
    new_game();
    uint32_t seen = VGA_FRAME;
    int wait = 0;
    while (!dead) {
      poll_buttons();
      if (VGA_FRAME == seen) continue;
      seen = VGA_FRAME;                                 // a frame just ended: the beam is in the blank now
      if (status_ready) { vga_text(0, 0, status, YELLOW, BLACK); status_ready = 0; }
      if (BUTTONS & SW0) continue;                      // paused
      if (++wait < speed) continue;
      wait = 0;
      int scored = move();
      leds(1);
      if (scored) prepare_status();                     // slow (udiv): after the stores, shown at the next blank
    }
    game_over();
    while (btn_stable) poll_buttons();                  // let go of the button that steered into the wall ...
    while (!btn_stable) poll_buttons();                 // ... then any press starts again
    queued = 0;
  }
}
