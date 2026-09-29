# PIPE-P2a C ROIs (second pass, warm I-cache): compressed-only ALU, a mixed 16/32 stream with 32-bit instructions
# crossing fetch words, and a compressed taken-branch loop. Reported, not gated.
#include "p1mac.h"
        .option rvc
        .text
        .globl main
main:
        li      s7, 2
pass:
roi1_b: nop
        .rept 32
        c.addi  t0, 1
        c.addi  t1, 1
        .endr
roi1_e: nop
roi2_b: nop
        .rept 16
        c.addi  t2, 1
        addi    t3, t3, 1
        c.addi  t4, 1
        addi    t5, t5, 1
        .endr
roi2_e: nop
        li      a2, 32
roi3_b: nop
1:      c.addi  a2, -1
        c.bnez  a2, 1b
roi3_e: nop
        addi    s7, s7, -1
        bnez    s7, pass
        li      a0, 0
        ret
