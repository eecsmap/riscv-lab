# Extension probe: M. Multiply, divide, remainder, and their word forms, with results checked against
# values computed here rather than trusted. The marker is only printed if every check holds, so the marker
# means "these instructions produced these answers", not "the program reached the end".
#include "m3lib.h"
        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top

        li      t0, 0x00000000deadbeef
        li      t1, 0x0000000000010001
        mul     t2, t0, t1              # low 64 of the product
        li      t3, 0xdeadbeef
        li      t4, 0x0001
        # deadbeef * 10001 = deadbeef + deadbeef0000
        slli    t5, t3, 16
        add     t5, t5, t3
        bne     t2, t5, fail

        li      t0, -7
        li      t1, 2
        div     t2, t0, t1              # RISC-V division truncates toward zero: -3
        li      t3, -3
        bne     t2, t3, fail
        rem     t2, t0, t1              # remainder takes the dividend's sign: -1
        li      t3, -1
        bne     t2, t3, fail

        li      t0, 7
        li      t1, 2
        divu    t2, t0, t1
        li      t3, 3
        bne     t2, t3, fail

        li      t0, 0x7fffffff
        li      t1, 2
        mulw    t2, t0, t1              # .W result is sign-extended from bit 31: 0xfffffffffffffffe
        li      t3, -2
        bne     t2, t3, fail

        li      t0, 5
        li      t1, 0
        div     t2, t0, t1              # division by zero is defined: all ones
        li      t3, -1
        bne     t2, t3, fail
        rem     t2, t0, t1              # and the remainder is the dividend
        li      t3, 5
        bne     t2, t3, fail

        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit
fail:   la      a0, failmark
        call    htif_puts
        li      a0, 1
        call    htif_exit

        .section .rodata, "a", @progbits
marker:   .asciz "TEACHING-EXT-M-OK\n"
failmark: .asciz "TEACHING-EXT-M-FAIL\n"
