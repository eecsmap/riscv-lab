# i08: a synchronous exception belongs to the instruction that caused it. The interrupt here is injected
# while a load that will come back with a bus error is outstanding, so the load's access fault must be
# reported first, and the interrupt only afterwards. An interrupt may never swallow a committed access.
#include "testmac.h"
#include "irqmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        li      t0, MIE_MTIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        li      s0, 0x90000000          # a well-formed address with no memory behind it
        .option push
        .option norvc
        .globl the_bad_load
the_bad_load:
        ld      t2, 0(s0)               # issued, handshakes, answered with error
        .option pop
        # the first trap must be the load's access fault, not the interrupt
        la      t0, irq_seen
        ld      t1, 0(t0)
        la      t0, first_cause
        ld      t2, 0(t0)
        CHECK_EQ(t2, 5, 1)              # cause 5 = load access fault, recorded below
        WAIT_IRQ(1, 2, t0, t1, t2)
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 2, 3)              # exactly two traps: the fault and the interrupt
        PASS
