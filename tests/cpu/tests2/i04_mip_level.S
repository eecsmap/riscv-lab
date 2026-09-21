# i04: mip is a window onto the external levels, not a register software owns. With the global enable off
# nothing is accepted, the level is visible in mip, and writing mip -- which is a legal instruction, since
# mip is not an encoded read-only address -- changes nothing. Only the platform can quiet the source.
#include "testmac.h"
#include "irqmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        li      t0, MIE_MTIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrc    mstatus, t0             # global enable off: nothing may be accepted below
        # wait for the level to come up
        li      t2, 100000
1:      csrr    t1, mip
        bnez    t1, 2f
        addi    t2, t2, -1
        bnez    t2, 1b
        FAIL_CODE(1, t0)
2:      CHECK_EQ(t1, 0x80, 2)           # MTIP is bit 7
        # a write to mip is legal and must not trap ...
        li      t0, -1
        csrw    mip, t0
        csrr    t1, mip
        CHECK_EQ(t1, 0x80, 3)           # ... and must not invent pending bits
        csrc    mip, t0
        csrr    t1, mip
        CHECK_EQ(t1, 0x80, 4)           # ... and must not clear a source that is still asserted
        li      t0, 0x80
        csrc    mip, t0
        csrr    t1, mip
        CHECK_EQ(t1, 0x80, 5)
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 6)              # no trap anywhere above
        # only the platform can quiet it
        li      t0, IRQ_MMIO
        li      t1, 7
        sd      t1, 0(t0)
        csrr    t1, mip
        CHECK_EQ(t1, 0, 7)
        PASS
