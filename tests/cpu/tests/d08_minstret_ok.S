# d08: the counter the core really does implement must still read, and must still advance. This is the
# control for d07: removing the fabricated CSRs must not have removed the real one.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   .option push
        .option norvc
        csrr    s0, minstret
        addi    t0, x0, 1
        addi    t1, x0, 2
        csrr    s1, instret             # the same counter under its other name
        .option pop
        sub     s2, s1, s0
        li      s3, 3                   # addi, addi, and the closing csrr
        CHECK_EQ_R(s2, s3, 39)
        PASS
