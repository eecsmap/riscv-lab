# i03: the two masks. With mstatus.MIE clear, or with the individual enable clear, a level that is asserted
# the whole time must not be accepted; enabling then takes it immediately, before one more instruction runs.
#include "testmac.h"
#include "irqmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        li      t0, 7
        la      t1, irq_clear_mask
        sd      t0, 0(t1)
        # global enable off, individual enable on
        li      t0, MIE_MTIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrc    mstatus, t0
        # let the source come up and stay up: spin a while, nothing may be taken
        li      t2, 2000
1:      addi    t2, t2, -1
        bnez    t2, 1b
        csrr    t1, mip                 # the level is visible ...
        CHECK_EQ(t1, 0x80, 1)           # ... MTIP is bit 7
        la      t0, irq_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 2)              # ... but nothing was accepted
        # now clear the individual enable and set the global one: still nothing
        csrw    mie, x0
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        li      t2, 2000
2:      addi    t2, t2, -1
        bnez    t2, 2b
        la      t0, irq_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 3)
        # enable the individual bit: the interrupt must be taken now
        li      t0, MIE_MTIE
        csrw    mie, t0
        WAIT_IRQ(1, 4, t0, t1, t2)
        la      t0, last_cause
        ld      t1, 0(t0)
        andi    t1, t1, 0xff
        CHECK_EQ(t1, CAUSE_MTI, 5)
        PASS
