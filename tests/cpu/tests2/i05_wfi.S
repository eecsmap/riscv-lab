# i05: WFI is a legal no-op here. It retires exactly once, it does not stop anything, and it does not make
# an interrupt acceptable on its own: with the global enable clear, execution simply continues past it.
# This is not a low-power wait implementation and the report says so.
#include "testmac.h"
#include "irqmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        li      t0, MIE_MTIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrc    mstatus, t0             # global enable off for the whole of the first part
        # WFI retires: the span below is static, so the count is exact
        .option push
        .option norvc
        csrr    s0, minstret
        wfi
        addi    t0, x0, 1
        csrr    s1, minstret
        .option pop
        sub     s2, s1, s0
        li      t1, 3                   # wfi, addi, and the closing csrr
        CHECK_EQ_R(s2, t1, 1)
        # the source is asserted by now, but the global enable is off: nothing was taken
        li      t2, 2000
1:      addi    t2, t2, -1
        bnez    t2, 1b
        csrr    t1, mip
        CHECK_EQ(t1, 0x80, 2)           # the level really is up
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 3)              # and WFI did not let it in
        # a second WFI, still with the enable off, still just retires
        .option push
        .option norvc
        wfi
        .option pop
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 4)
        # now enable: the interrupt is taken
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        WAIT_IRQ(1, 5, t0, t1, t2)
        PASS
