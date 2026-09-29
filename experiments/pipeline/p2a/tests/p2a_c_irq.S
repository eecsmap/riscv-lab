# PIPE-P2a C: an interrupt raised (after N retirements) in a mixed 16/32-bit stream whose 32-bit instructions start
# at every parcel position of a fetch word. Independent checks: one interrupt, mcause = MSIP, mepc 2-aligned (and
# odd multiples of 2 are allowed: IALIGN 16) inside the enabled window, and the block's sum is exact.
#include "p1mac.h"
        .option rvc
        .text
        .globl main
main:
        li      t0, 8
        csrw    mie, t0
        csrsi   mstatus, 8
irq_window:
        li      a1, 0
        .rept 12
        c.addi  a1, 1
        addi    a1, a1, 2
        c.addi  a1, 3
        c.nop
        addi    a1, a1, 4
        .endr
        li      a4, 300
1:      c.addi  a4, -1
        c.bnez  a4, 1b
        csrci   mstatus, 8
        CHECK_EQ(a1, 120, 1)            # 12 * (1 + 2 + 3 + 4)
        la      t0, irq_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 1, 2)
        LOG_ENTRY(0)
        li      gp, MSIP_CAUSE
        CHECK_REG(t4, gp, 3)
        andi    t1, t5, 1
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
