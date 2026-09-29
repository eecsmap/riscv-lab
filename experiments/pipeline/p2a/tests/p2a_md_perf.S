# PIPE-P2a M ROIs (second pass, warm I-cache): independent multiplies, a dependent divide chain, and a mix of
# M and ALU instructions. Measured by p1/scripts/perf.py; reported, not gated.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      s0, 123457
        li      s1, 3
        li      s7, 2
pass:
roi1_b: nop
        .rept 8
        mul     t0, s0, s1
        mul     t1, s0, s0
        .endr
roi1_e: nop
        mv      t2, s0
roi2_b: nop
        .rept 8
        divu    t2, t2, s1
        .endr
roi2_e: nop
roi3_b: nop
        .rept 8
        mul     t3, s0, s1
        addi    t4, t4, 1
        addi    t5, t5, 1
        add     t6, t3, t4
        .endr
roi3_e: nop
        addi    s7, s7, -1
        bnez    s7, pass
        li      a0, 0
        ret
