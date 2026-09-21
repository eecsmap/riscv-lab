# M3-b: the first program the teaching CPU runs from real DRAM, after the real boot chain.
# Self-contained: rv64i_zicsr, lp64, no compressed instructions, no library and no runtime. It prints a
# fixed marker through the HTIF console device and exits with code 0, so the host's verdict and the marker
# are two separate pieces of evidence. The HTIF protocol lives in htif.S, shared with the other programs.
#include "m3lib.h"
        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top
        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit
        .section .rodata, "a", @progbits
marker: .asciz "TEACHING-CPU-M3-OK\n"
