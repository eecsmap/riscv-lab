# d03: a branch that is NOT taken must not check its target's alignment. The encoding below is
# `bne x0, x0, .+2`: never taken, target misaligned. The core must fall through and pass.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   li      t2, 7
        .option push
        .option norvc
        .word   0x00001163          # bne x0, x0, +2  (never taken, misaligned target)
        .option pop
        li      t3, 7
        bne     t2, t3, 1f
        PASS
1:      FAIL_CODE(33, t2)
