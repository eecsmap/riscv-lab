# The program quiets its own interrupt source with a store while the line is up (the harness raises it around
# that store; the run is repeated at several positions). Architecturally the interrupt may be taken before the
# quieting store completes or not at all; what may NOT happen is a trap for a source that is no longer pending
# with a stale cause, a lost or repeated instruction, or a second interrupt. In the pipeline a token created
# before the store completes must be CANCELLED at WB (the instruction it replaced is refetched and executes).
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      t0, 8
        csrw    mie, t0
        csrsi   mstatus, 8
        li      a1, 0
        li      t1, 0x60000000
        li      t2, 7
        li      s4, 2               # two passes: the second is warm, so younger instructions stream behind the store
        .align 4
2:      .rept 4
        addi    a1, a1, 1
        .endr
        sd      t2, 0(t1)           # quiet msip/mtip/meip (the harness's test source)
        .rept 16
        addi    a1, a1, 1
        .endr
        addi    s4, s4, -1
        bnez    s4, 2b
        li      t3, 100
1:      addi    t3, t3, -1
        bnez    t3, 1b
        csrci   mstatus, 8
        CHECK_EQ(a1, 40, 1)
        la      t0, irq_n
        ld      t0, 0(t0)
        li      gp, 2
        bgeu    t0, gp, 90f         # at most one
        beqz    t0, 2f
        LOG_ENTRY(0)
        li      gp, MSIP_CAUSE
        CHECK_REG(t4, gp, 3)
2:      li      a0, 0
        ret
90:     FAIL(2)
