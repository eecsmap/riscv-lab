# i09: an interrupt that arrives while a store is in flight may not cancel it, repeat it, or let it be seen
# twice. The store below writes a value that is read back afterwards, and the harness counts requests,
# responses and retirements so that "exactly once" is measured on the bus, not inferred from the value.
#include "testmac.h"
#include "irqmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        li      t0, MIE_MTIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        la      s0, slot
        li      s1, 0x0123456789abcdef
        # keep storing and checking: the injected interrupt lands inside one of these accesses
        li      s4, 2000
1:      sd      s1, 0(s0)
        ld      s2, 0(s0)
        CHECK_EQ_R(s2, s1, 1)
        # a counter that must be incremented exactly once per iteration, through memory
        ld      t1, 8(s0)
        addi    t1, t1, 1
        sd      t1, 8(s0)
        la      t0, irq_count
        ld      t2, 0(t0)
        bnez    t2, 2f
        addi    s4, s4, -1
        bnez    s4, 1b
        FAIL_CODE(2, t0)
2:      # the value survived the interrupt intact
        ld      s2, 0(s0)
        CHECK_EQ_R(s2, s1, 3)
        la      t0, irq_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 1, 4)
        PASS
        .section .data, "aw", @progbits
        .align 3
slot:   .dword 0
        .dword 0
