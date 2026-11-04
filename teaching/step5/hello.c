// Step 5, TODO 2: the first line your core prints inside a real system.
// Copy this file to teaching/work/hello.c, change the text, and run:  make step5-run PROG=work/hello.c
#include "console.h"

int main(void)
{
  uint64_t c0 = rdcycle(), i0 = rdinstret();
  con_puts("hello from my RV64 core\n");
  uint64_t c1 = rdcycle(), i1 = rdinstret();
  con_puts("that line took ");
  con_putdec(c1 - c0);
  con_puts(" cycles and ");
  con_putdec(i1 - i0);
  con_puts(" instructions\n");
  return 0;                     // the exit code the host reports; non-zero would make the run fail
}
