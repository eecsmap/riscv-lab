# Extension probe: C. The point is that *compressed encodings* execute correctly, so this file
# deliberately allows RVC and uses c.* instructions explicitly, then checks the arithmetic they
# performed. Every other probe here is built with .option norvc; this one is the exception, and says so.
# (Comment lines must not begin with "# else" or "# if": these files go through the C preprocessor
# because of the #include, and such a line is read as a directive.)
#include "m3lib.h"
        .section .text.start, "ax", @progbits
        .globl _start
_start: la      sp, _stack_top
        .option rvc
        li      a1, 0
        c.li    a2, 15                  # compressed load immediate
        c.addi  a2, 1                   # 16
        li      a3, 16
        bne     a2, a3, fail
        c.slli  a2, 2                   # 64
        li      a3, 64
        bne     a2, a3, fail
        c.mv    a4, a2                  # compressed move
        bne     a4, a3, fail
        c.add   a4, a2                  # 128
        li      a3, 128
        bne     a4, a3, fail
        addi    sp, sp, -16
        c.sdsp  a4, 0(sp)               # compressed store/load through sp
        c.ldsp  a5, 0(sp)
        addi    sp, sp, 16
        bne     a5, a4, fail
        .option norvc

        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit
fail:   la      a0, failmark
        call    htif_puts
        li      a0, 1
        call    htif_exit

        .section .rodata, "a", @progbits
marker:   .asciz "TEACHING-EXT-C-OK\n"
failmark: .asciz "TEACHING-EXT-C-FAIL\n"
