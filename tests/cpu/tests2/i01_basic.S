# i01: one timer interrupt, accepted at an architectural boundary and returned from.
# The source is a level held by the harness until the handler quiets it through the test controller.
#include "testmac.h"
#include "irqmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        li      t0, 7
        la      t1, irq_clear_mask
        sd      t0, 0(t1)
        li      t0, MIE_MTIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        WAIT_IRQ(1, 1, t0, t1, t2)
        # exactly one interrupt, with the timer cause and the interrupt bit set
        la      t0, irq_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 1, 2)
        la      t0, last_cause
        ld      t1, 0(t0)
        li      t2, CAUSE_MTI
        slli    t3, t2, 0
        li      t2, -1
        srli    t2, t2, 1
        not     t2, t2                  # t2 = 1 << 63
        or      t2, t2, t3
        CHECK_EQ_R(t1, t2, 3)
        # the source is quiet again: mip must read back as zero
        csrr    t1, mip
        CHECK_EQ(t1, 0, 4)
        # and no further interrupt arrives
        la      t0, irq_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 1, 5)
        PASS
