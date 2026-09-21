# j01: an interrupt that arrives while interrupts are genuinely enabled, during a specific wait state of a
# specific instruction. The order below matters and is the whole point of the test:
#   1. enable mie and mstatus.MIE, and prove they are in effect by reading them back
#   2. only then arm the injector -- the harness holds the arming off until the arming store itself has
#      completed, so the moment that gets injected into cannot be the arming store
#   3. the very next instruction is `target_insn`, a load: it has a fetch phase, a data phase and a
#      writeback, so the same program serves every injection point
# The interrupt must be deferred until that load has finished and retired, and mepc must then be exactly
# `after_target`. The harness records which state it actually fired in and whether the enables were real.
#include "testmac.h"
#include "irqmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        li      t0, MIE_MTIE
        csrw    mie, t0
        csrr    t1, mie
        CHECK_EQ_R(t1, t0, 1)                   # the per-line enable is really set
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        csrr    t1, mstatus
        andi    t1, t1, MSTATUS_MIE
        CHECK_EQ(t1, MSTATUS_MIE, 2)            # and so is the global one
        la      s0, payload
        li      s1, 0x1122334455667788
        # arm only now: everything above is already enabled
        li      t0, IRQ_ARM
        li      t1, 1
        sd      t1, 0(t0)
        .option push
        .option norvc
        .globl target_insn, after_target
target_insn:
        ld      s2, 0(s0)                       # the instruction the interrupt must not cut short
after_target:
        addi    s3, x0, 1
        .option pop
        # the load completed with the right value: it was not cancelled or replayed
        CHECK_EQ_R(s2, s1, 3)
        CHECK_EQ(s3, 1, 4)
        WAIT_IRQ(1, 5, t0, t1, t2)
        la      t0, irq_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 1, 6)
        # mepc is the instruction after the target, never the target itself
        la      t0, last_epc
        ld      t1, 0(t0)
        la      t2, after_target
        CHECK_EQ_R(t1, t2, 7)
        PASS
        .section .data, "aw", @progbits
        .align 3
payload: .dword 0x1122334455667788
