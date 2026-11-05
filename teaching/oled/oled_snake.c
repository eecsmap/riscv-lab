// OLED project 5: snake. Needs a step-4 core: the game tick is the CLINT timer interrupt (start code trap_start.S).
// The board build moves the reset to SW1 (RESET_SW1=1), so all four buttons steer:
//   BTN3 left, BTN2 up, BTN1 down, BTN0 right (change dir_of_button[] if your fingers disagree)
//   SW0 up: pause. SW1 up: reset. After a crash any button starts a new game.
// LEDs: LED0 toggles on every move, LED1..2 = score & 3, LED3 = game over.
//
// Who does what:
//   the interrupt  counts ticks and sets the next deadline -- nothing else, so it can never be slow
//   main           debounces the buttons all the time, and makes one move per tick it has not handled yet
// Drawing is incremental: a move repaints the old head, the new head and the old tail -- three 4 x 4 cells, about
// 35 bytes on SPI -- never the whole screen.
#include "oled.h"

#define CLINT_MTIMECMP (*(volatile uint64_t *)0x02004000)
#define MSTATUS_MIE (1u << 3)
#define MIE_MTIE    (1u << 7)
#define MCAUSE_MTI  ((1ull << 63) | 7)

#ifndef TICK_MS
#define TICK_MS 150             // the first game speed; 5 ms faster per food, down to 60 ms
#endif
#define DEBOUNCE_MS 5           // a button must read the same for this long before it counts
#define SW0 (1u << 4)           // GPIO IN = {sw, btn}

#define COLS 24                 // 4 x 4-pixel cells; the top 8 pixel rows are the score line
#define ROWS 14
#define CELLS (COLS * ROWS)
#define TOP 8

enum { RIGHT, DOWN, LEFT, UP };
static const int8_t dx[4] = { 1, 0, -1, 0 }, dy[4] = { 0, 1, 0, -1 };
static const uint8_t dir_of_button[4] = { RIGHT, DOWN, UP, LEFT };   // BTN0, BTN1, BTN2, BTN3

#define C_HEAD RGB(160, 255, 80)
#define C_BODY RGB(0, 170, 60)
#define C_FOOD RGB(255, 40, 40)
#define C_TEXT RGB(255, 255, 255)

// ---- shared with the interrupt handler
static volatile uint32_t ticks;            // written only by the handler; a 32-bit load reads it in one piece
static volatile uint64_t tick_len;         // written only by main; the handler reads it (one 64-bit load: never torn)

void trap_handler(uint64_t mcause, uint64_t mepc)
{
  (void)mepc;
  if (mcause == MCAUSE_MTI) {
    CLINT_MTIMECMP += tick_len;            // fixed grid, and it lowers mtip
    ticks++;
    return;
  }
  for (;;) LEDS = 0xA;                     // any other trap is a bug: 1010 on the LEDs
}

// ---- game state
static uint8_t occ[CELLS];                 // 1 where the snake is
static uint8_t body_x[CELLS], body_y[CELLS];   // ring buffer, tail .. head
static int head, len, dir, score, hi, dead;
static int food_x, food_y;
static uint8_t queue[2];                   // turns pressed but not yet made: two, so up-then-left inside one tick works
static int queued;
static uint16_t lfsr = 0xACE1;

static int cell(int x, int y) { return (y << 4) + (y << 3) + x; }   // y * 24 + x without a multiply

static void paint(int x, int y, uint16_t c)
{
  uint8_t px = (uint8_t)(x << 2), py = (uint8_t)(TOP + (y << 2));
  oled_rect(px, py, px + 3, py + 3, c, c);
}

static void erase(int x, int y)
{
  uint8_t cmd[5];
  cmd[0] = 0x25; cmd[1] = (uint8_t)(x << 2); cmd[2] = (uint8_t)(TOP + (y << 2)); cmd[3] = cmd[1] + 3; cmd[4] = cmd[2] + 3;
  oled_cmds(cmd, 5);
  delay_ms(1);
}

// 16-bit Galois LFSR: a pseudo-random sequence from shifts and one XOR
static uint16_t rnd(void)
{
  lfsr = (uint16_t)((lfsr >> 1) ^ (-(lfsr & 1u) & 0xB400u));
  return lfsr;
}

// a random free cell. No modulo (no divider): draw 9 bits, throw away anything >= CELLS or occupied, draw again.
static void place_food(void)
{
  int i;
  do i = rnd() & 511; while (i >= CELLS || occ[i]);
  food_y = 0;
  while (i >= COLS) { i -= COLS; food_y++; }
  food_x = i;
  paint(food_x, food_y, C_FOOD);
}

static void show_score(void)
{
  static char line[24], num[8];
  append(append(append(append(line, "PTS"), fmt_fixed(num, (uint64_t)score, 0, 3)), " HI"), fmt_fixed(num, (uint64_t)hi, 0, 3));   // 12 cells
  oled_text(0, 0, line, C_TEXT, 0);
}

static void leds(int toggle)
{
  static uint8_t led0;
  led0 ^= (uint8_t)toggle;
  LEDS = (uint8_t)(led0 | ((score & 3) << 1) | (dead ? 8 : 0));
}

static void new_game(void)
{
  for (int i = 0; i < CELLS; i++) occ[i] = 0;
  oled_clear();
  len = 3; head = 2; dir = RIGHT; score = 0; dead = 0; queued = 0;
  for (int i = 0; i < 3; i++) {
    body_x[i] = (uint8_t)(2 + i); body_y[i] = 7;
    occ[cell(2 + i, 7)] = 1;
    paint(2 + i, 7, i == 2 ? C_HEAD : C_BODY);
  }
  food_x = 10; food_y = 7;                 // the first food is always straight ahead: a test can count on it
  paint(food_x, food_y, C_FOOD);
  show_score();
  tick_len = (uint64_t)TICK_MS * TICKS_PER_MS;
  leds(0);
}

// ---- buttons: debounced edges become queued turns
static uint32_t btn_raw, btn_stable;
static uint64_t btn_since;

static void poll_buttons(void)
{
  uint32_t raw = (uint32_t)(BUTTONS & 0xF);
  if (raw != btn_raw) { btn_raw = raw; btn_since = CLINT_MTIME; return; }
  if (raw == btn_stable || CLINT_MTIME - btn_since < (uint64_t)DEBOUNCE_MS * TICKS_PER_MS) return;
  uint32_t pressed = raw & ~btn_stable;
  btn_stable = raw;
  if (pressed) lfsr ^= (uint16_t)CLINT_MTIME | 1;    // your timing is the randomness
  for (int b = 0; b < 4; b++) {
    if (!(pressed & (1u << b)) || queued == 2) continue;
    int d = dir_of_button[b], last = queued ? queue[queued - 1] : dir;
    if (d != last && d != (last ^ 2)) queue[queued++] = (uint8_t)d;    // same way or straight back: ignored
  }
}

static void move(void)
{
  if (queued) { dir = queue[0]; queue[0] = queue[1]; queued--; }
  int hx = body_x[head] + dx[dir], hy = body_y[head] + dy[dir];
  int tail = head - len + 1; if (tail < 0) tail += CELLS;
  int eat = (hx == food_x && hy == food_y);
  // a wall, or the body -- except the tail cell, which moves away in this same step unless the snake grows
  if (hx < 0 || hx >= COLS || hy < 0 || hy >= ROWS ||
      (occ[cell(hx, hy)] && !(!eat && hx == body_x[tail] && hy == body_y[tail]))) {
    dead = 1;
    return;
  }
  if (!eat) {
    occ[cell(body_x[tail], body_y[tail])] = 0;
    erase(body_x[tail], body_y[tail]);
  }
  paint(body_x[head], body_y[head], C_BODY);
  head = (head == CELLS - 1) ? 0 : head + 1;
  body_x[head] = (uint8_t)hx; body_y[head] = (uint8_t)hy;
  occ[cell(hx, hy)] = 1;
  paint(hx, hy, C_HEAD);
  if (eat) {
    len++; score++;
    if (score > hi) hi = score;
    if (tick_len > (uint64_t)65 * TICKS_PER_MS) tick_len -= (uint64_t)5 * TICKS_PER_MS;
    place_food();
    show_score();
  }
}

static void game_over(void)
{
  static const uint8_t dim[5] = { 0x24, 0, TOP, OLED_W - 1, OLED_H - 1 };
  oled_cmds(dim, 5);                       // the controller darkens the board by itself
  delay_ms(5);
  oled_text(1, 3, "GAME  OVER", RGB(255, 80, 80), 0);
  show_score();
  leds(0);
}

int main(void)
{
  oled_init();
  spi_mode(1, 4);                          // the SPI master from project 3
  tick_len = (uint64_t)TICK_MS * TICKS_PER_MS;
  CLINT_MTIMECMP = CLINT_MTIME + tick_len;
  asm volatile("csrs mie, %0" :: "r"(MIE_MTIE));
  asm volatile("csrs mstatus, %0" :: "r"(MSTATUS_MIE));
  for (;;) {
    new_game();
    uint32_t seen = ticks;
    while (!dead) {
      poll_buttons();
      if (seen == ticks) continue;
      seen++;                              // one move per tick; if drawing ever fell behind, catch up one by one
      if (BUTTONS & SW0) continue;         // paused: ticks pass, the snake stays
      move();
      leds(1);
    }
    game_over();
    while (btn_stable) poll_buttons();     // let go of the button that steered into the wall ...
    while (!btn_stable) poll_buttons();    // ... then any press starts again
    queued = 0;
  }
}
