# An enabled machine software interrupt raised (by the harness, after N retirements) while a straight-line block
# of 64 counted instructions runs. Independent checks, not a comparison: exactly one interrupt; mcause = MSIP;
# mepc is 4-aligned and inside the block (or at its end); no instruction lost or repeated (the count is 64).
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      t0, 8
        csrw    mie, t0             # MSIE
        csrsi   mstatus, 8          # MIE
        li      a1, 0
blk_start:
        .rept 64
        addi    a1, a1, 1
        .endr
blk_end:
        # spin a little so a late raise is still taken inside the program
        li      t1, 200
1:      addi    t1, t1, -1
        bnez    t1, 1b
        csrci   mstatus, 8
        CHECK_EQ(a1, 64, 1)
        la      t0, irq_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 1, 2)
        LOG_ENTRY(0)
        li      gp, MSIP_CAUSE
        CHECK_REG(t4, gp, 3)
        andi    t1, t5, 3
        CHECK_EQ(t1, 0, 4)
        CHECK_EQ(t6, 0, 5)          # mtval = 0 for an interrupt
        la      t1, blk_start
        bltu    t5, t1, 90f
        la      t1, tail_limit
        bgtu    t5, t1, 90f
        li      a0, 0
        ret
90:     FAIL(6)
tail_limit:
        nop
