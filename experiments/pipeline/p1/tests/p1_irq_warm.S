# The same independent checks as irq_basic, but the interrupt arrives while WARM code runs (a loop over one
# I-cache-resident block), so instructions are flowing into ID when the line rises: the token attaches to a
# real instruction. 20 iterations x 8 counted instructions.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      t0, 8
        csrw    mie, t0
        csrsi   mstatus, 8
        li      a1, 0
        li      t2, 20
        .align 4
loop_b:
        .rept 8
        addi    a1, a1, 1
        .endr
        addi    t2, t2, -1
        bnez    t2, loop_b
loop_e:
        li      t1, 100
1:      addi    t1, t1, -1
        bnez    t1, 1b
        csrci   mstatus, 8
        CHECK_EQ(a1, 160, 1)
        la      t0, irq_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 1, 2)
        LOG_ENTRY(0)
        li      gp, MSIP_CAUSE
        CHECK_REG(t4, gp, 3)
        la      t1, loop_b
        bltu    t5, t1, 90f
        la      t1, loop_e
        bgtu    t5, t1, 91f
        li      a0, 0
        ret
90:     FAIL(4)
91:     li      a0, 0               # taken in the spin loop after the block: allowed
        ret
