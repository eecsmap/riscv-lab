# i02: all three lines asserted together. The order taken must be external, then software, then timer.
# The handler quiets one line at a time, so each pass through it takes the next one in priority order.
#include "testmac.h"
#include "irqmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        li      t0, MIE_MSIE | MIE_MTIE | MIE_MEIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        # All three lines come up together. The handler quiets only the one it was called for, so the three
        # traps happen back to back and the order they arrive in is the priority order under test.
        WAIT_IRQ(3, 1, t0, t1, t2)
        # irq_seen packs the causes one byte per entry, oldest in the high byte of the three
        la      t0, irq_seen
        ld      t1, 0(t0)
        li      t2, (CAUSE_MEI << 16) | (CAUSE_MSI << 8) | CAUSE_MTI
        CHECK_EQ_R(t1, t2, 4)
        csrr    t1, mip
        CHECK_EQ(t1, 0, 5)
        PASS
