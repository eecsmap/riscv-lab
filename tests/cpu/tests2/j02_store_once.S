# j02: "exactly once" for a named store, measured rather than inferred. The loop runs a fixed number of
# iterations regardless of when the interrupt arrives, so the expected transaction counts at the watched
# address are static: one load and one store per iteration, and one applied write per iteration.
# The final value alone proves nothing here -- a store repeated with the same value leaves it unchanged --
# which is why the harness counts write side effects on its own side.
#include "testmac.h"
#include "irqmac.h"
#define ITERS 50
        .section .text, "ax", @progbits
        .globl main
main:   call    install_handler
        li      t0, MIE_MTIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        la      s5, watch_slot
        sd      x0, 0(s5)                       # not part of the counted window: see the runner's expectation
        li      s3, 0                           # iterations, counted in a register
        li      s4, ITERS
        li      t0, IRQ_ARM
        li      t1, 1
        sd      t1, 0(t0)
1:      .option push
        .option norvc
        .globl watched_load, watched_store
watched_load:
        ld      t1, 0(s5)
        addi    t1, t1, 1
watched_store:
        sd      t1, 0(s5)
        .option pop
        addi    s3, s3, 1
        blt     s3, s4, 1b
        # the memory counter must equal the register counter: neither lost nor duplicated
        ld      t1, 0(s5)
        CHECK_EQ_R(t1, s3, 1)
        CHECK_EQ(s3, ITERS, 2)
        WAIT_IRQ(1, 3, t0, t1, t2)
        la      t0, irq_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 1, 4)
        PASS
        .section .data, "aw", @progbits
        .align 3
        .globl watch_slot
watch_slot: .dword 0
