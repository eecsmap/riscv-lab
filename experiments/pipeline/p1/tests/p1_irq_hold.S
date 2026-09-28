# A permanently pending, enabled interrupt cannot disappear: the handler leaves the line raised twice, so the
# interrupt must be taken three times in a row, then it is quieted and the program continues.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        la      t0, irq_hold
        li      t1, 2
        sd      t1, 0(t0)
        li      t0, 8
        csrw    mie, t0
        csrsi   mstatus, 8
        li      a1, 0
        .rept 30
        addi    a1, a1, 1
        .endr
        li      t1, 200
1:      addi    t1, t1, -1
        bnez    t1, 1b
        csrci   mstatus, 8
        la      t0, irq_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 3, 1)
        CHECK_EQ(a1, 30, 2)
        LOG_ENTRY(1)
        li      gp, MSIP_CAUSE
        CHECK_REG(t4, gp, 3)
        li      a0, 0
        ret
