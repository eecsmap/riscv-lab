# i06: an interrupt that is still asserted when MRET restores the enable must be taken again, immediately,
# before the interrupted instruction runs. The handler is told to leave the source up for the first few
# entries, so the re-entry really happens, and irq_reenter_limit bounds it so the test terminates.
# Every mepc must be the same address: the instruction that still has not executed.
#include "testmac.h"
#include "irqmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        li      t0, 1
        la      t1, irq_leave_asserted
        sd      t0, 0(t1)
        li      t0, 3                   # quiet it on the third entry
        la      t1, irq_reenter_limit
        sd      t0, 0(t1)
        li      t0, MIE_MTIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        WAIT_IRQ(3, 1, t0, t1, t2)
        la      t0, irq_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 3, 2)
        # all three were the same line, and the source is quiet now
        la      t0, irq_seen
        ld      t1, 0(t0)
        li      t2, (CAUSE_MTI << 16) | (CAUSE_MTI << 8) | CAUSE_MTI
        CHECK_EQ_R(t1, t2, 3)
        csrr    t1, mip
        CHECK_EQ(t1, 0, 4)
        PASS
