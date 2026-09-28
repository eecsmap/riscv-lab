// MC-M3: migration of ONE process across harts, then user execution and exec on the new hart.
//   1. record the hart it starts on; try NATURAL migration for 8 sleeps (informational: on this platform hart 0
//      wakes the sleeper from its tick and the idle hart 1 picks it up first, so it may never move);
//   2. controlled migration (test-only pin(hart) syscall): pin to the OTHER hart, which must be observed by
//      getcpu(); run user code there; fork a child that pins itself to that hart too and execs echo (new code
//      fetched and executed on the hart the process migrated to); unpin.
//   On a single-core build pin() is refused (only one hart started) and the program reports pinned_ok=0.
#include "kernel/types.h"
#include "kernel/stat.h"
#include "user/user.h"
#include "m3lib.h"
int main(int argc, char **argv) {
  unsigned mask = 0; int i, st, exec_ok = 0, pinned_ok = 0, natural = 0;
  int h0 = getcpu(); mask |= 1u << h0;
  for (i = 0; i < 8; i++) { pause(1); mask |= 1u << getcpu(); if (mask == 3) { natural = 1; break; } }
  int other = 1 - h0;
  if (pin(other) == 0) {
    int h1 = getcpu(); mask |= 1u << h1;
    unsigned dummy = 0; unsigned long s = m3compute(7, 20000, &dummy); (void)s; mask |= dummy;   // user work on the new hart
    if (h1 == other) pinned_ok = 1;
    int pid = fork();
    if (pid == 0) { pin(other); char *av[] = {"echo", "M3-EXEC-AFTER-MIGRATE", 0}; exec("echo", av); exit(2); }
    if (pid > 0 && wait(&st) == pid && st == 0) exec_ok = 1;
    pin(-1);
  } else {
    int pid = fork();
    if (pid == 0) { char *av[] = {"echo", "M3-EXEC-AFTER-MIGRATE", 0}; exec("echo", av); exit(2); }
    if (pid > 0 && wait(&st) == pid && st == 0) exec_ok = 1;
  }
  { char b[96]; int k = m3_str(b, "M3-MIGRATE-DONE harts=0x"); b[k++] = '0' + (mask & 3); k += m3_str(b + k, " natural="); b[k++] = '0' + natural;
    k += m3_str(b + k, " pinned_ok="); b[k++] = '0' + pinned_ok; k += m3_str(b + k, " exec_ok="); b[k++] = '0' + exec_ok; b[k] = 0; m3_line(b); }
  exit(0);
}
