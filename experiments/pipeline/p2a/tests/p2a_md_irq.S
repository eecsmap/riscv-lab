# PIPE-P2a M: an interrupt raised (by the harness, after N retirements) around a run of long mul/div operations.
# Independent checks: exactly one interrupt, mcause = MSIP, mepc 4-aligned and inside the enabled window, and every
# result right (an interrupted operation is either complete before the trap or re-executed after it, once).
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      t0, 8
        csrw    mie, t0
        csrsi   mstatus, 8
irq_window:                             # interrupts are enabled from here on
        li      s0, 99991
        li      s1, 13
        li      a1, 0
blk_start:
        .rept 8
        div     t1, s0, s1              # 7691
        add     a1, a1, t1
        mul     t2, t1, s1              # 99983
        add     a1, a1, t2
        .endr
blk_end:
        li      t3, 300
1:      addi    t3, t3, -1
        bnez    t3, 1b
        csrci   mstatus, 8
        CHECK_EQ(a1, 861392, 1)         # 8 * (7691 + 99983)
        la      t0, irq_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 1, 2)
        LOG_ENTRY(0)
        li      gp, MSIP_CAUSE
        CHECK_REG(t4, gp, 3)
        andi    t1, t5, 3
        CHECK_EQ(t1, 0, 4)
        la      t1, irq_window
        bltu    t5, t1, 90f
        la      t1, tail_limit
        bgtu    t5, t1, 90f
        li      a0, 0
        ret
90:     FAIL(5)
tail_limit:
        nop
