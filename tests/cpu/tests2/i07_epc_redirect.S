# i07: mepc is the address of the instruction that has not executed yet, and that address already reflects
# what the instruction before it did. The interrupt is injected during the writeback of a taken backward
# branch (the harness skips the earlier redirects, so this is the one), which means mepc must be the branch
# target -- not the branch's own address plus four.
#include "testmac.h"
#include "irqmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        li      t0, MIE_MTIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        # arm the injector here: the next taken redirect is the backward branch below, and nothing in the
        # startup code can claim it first
        li      t0, IRQ_ARM
        li      t1, 1
        sd      t1, 0(t0)
        li      s4, 100000
        .option push
        .option norvc
        .globl loop_target
loop_target:
        addi    s4, s4, -1
        la      t0, irq_count
        ld      t1, 0(t0)
        bnez    t1, 2f
        bnez    s4, loop_target         # taken backward branch: the redirect the interrupt lands after
        .option pop
        FAIL_CODE(1, t0)
2:      la      t0, irq_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 1, 2)
        # mepc must be exactly the branch target
        la      t0, last_epc
        ld      t1, 0(t0)
        la      t2, loop_target
        CHECK_EQ_R(t1, t2, 3)
        PASS
