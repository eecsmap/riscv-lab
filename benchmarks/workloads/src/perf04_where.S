# Performance probe: how much of a memory round-trip is the PL, and how much is the PS and its DDR?
#
# perf03 established that one round-trip costs about 17.7 cycles on the board and 7.3 in simulation, with
# the same RTL -- so roughly ten cycles of it are the real memory system that simulation does not model.
# This splits the round-trip by TARGET instead of by simulator:
#
#   A  load from DRAM     core -> adapter -> AXI -> PS S_AXI_HP0 -> DDR controller -> DDR3 and back
#   B  load from the CLINT at 0x0200bff8 (mtime), which lives in the PL beside the core and never leaves
#      the fabric
#
# Same loop, same shape, three instructions, one load each. B is the PL-internal part of the path; A - B
# is everything beyond the fabric boundary.
#
# mtime changes while being read, which does not matter: the value is discarded and only the timing of the
# access is of interest. It is read with a plain ld, exactly as the DRAM loop reads its scratch word.
#include "m3lib.h"

        .equ ITERS, 10000

        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top
        la      s8, results

        la      s9, scratch                  # in DRAM, placed by the linker
        li      a0, ITERS
        call    measure_ld
        sd      a0, 0(s8)
        sd      a1, 8(s8)

        li      s9, CLINT_MTIME              # in the PL, beside the core
        li      a0, ITERS
        call    measure_ld
        sd      a0, 16(s8)
        sd      a1, 24(s8)

        li      t3, (ITERS * 3 + 2)
        ld      t5, 8(s8)
        bne     t5, t3, fail
        ld      t5, 24(s8)
        bne     t5, t3, fail

        la      s2, labels
        la      s3, results
        li      s4, 4
3:      mv      a0, s2
        call    htif_puts
        ld      a0, 0(s3)
        call    puthex
        addi    s3, s3, 8
4:      lbu     t0, 0(s2)
        addi    s2, s2, 1
        bnez    t0, 4b
        addi    s4, s4, -1
        bnez    s4, 3b

        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit
fail:   la      a0, failmark
        call    htif_puts
        li      a0, 1
        call    htif_exit

measure_ld:
        mv      t6, a0
        csrr    t4, cycle
        csrr    t5, instret
1:      ld      t1, 0(s9)
        addi    t6, t6, -1
        bnez    t6, 1b
        csrr    a0, cycle
        csrr    a1, instret
        sub     a0, a0, t4
        sub     a1, a1, t5
        ret

puthex: mv      s5, a0
        mv      s7, ra
        li      s6, 60
1:      srl     t0, s5, s6
        andi    t0, t0, 15
        li      t1, 10
        blt     t0, t1, 2f
        addi    t0, t0, 87
        j       3f
2:      addi    t0, t0, 48
3:      mv      a0, t0
        call    htif_putc
        addi    s6, s6, -4
        bgez    s6, 1b
        li      a0, 10
        call    htif_putc
        mv      ra, s7
        ret

        .section .rodata, "a", @progbits
labels: .asciz "WHERE-CYC-DRAM="
        .asciz "WHERE-INS-DRAM="
        .asciz "WHERE-CYC-CLINT="
        .asciz "WHERE-INS-CLINT="
marker:   .asciz "TEACHING-PERF-WHERE-OK\n"
failmark: .asciz "TEACHING-PERF-WHERE-FAIL\n"

        .section .data, "aw", @progbits
        .align 3
results: .zero 32
scratch: .dword 0x0123456789abcdef
