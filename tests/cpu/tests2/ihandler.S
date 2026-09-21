# Interrupt-aware M-mode handler for the M2-3 tests. It handles both kinds of trap:
#   - a synchronous exception resumes at the following instruction (every faulting instruction in these
#     tests is four bytes, as in M2-2)
#   - an interrupt resumes at mepc itself, because mepc is the instruction that has not run yet. The source
#     is quieted by writing the test interrupt controller: there is no sticky bit in the CPU to clear, and
#     writing mip would not do anything, which is the point.
#include "irqmac.h"
        .section .text, "ax", @progbits
        .globl trap_handler
        .align 2
trap_handler:
        csrrw   sp, mscratch, sp
        sd      t0, -8(sp)
        sd      t1, -16(sp)
        sd      t2, -24(sp)
        csrr    t0, minstret
        la      t1, handler_entry_instret
        sd      t0, 0(t1)
        csrr    t0, mcause
        la      t1, last_cause
        sd      t0, 0(t1)
        csrr    t1, mepc
        la      t2, last_epc
        sd      t1, 0(t2)
        csrr    t1, mtval
        la      t2, last_tval
        sd      t1, 0(t2)
        la      t1, trap_count
        ld      t2, 0(t1)
        addi    t2, t2, 1
        sd      t2, 0(t1)
        li      t1, 1
        bne     t2, t1, 8f                  # remember the very first cause, for ordering checks
        la      t1, first_cause
        andi    t2, t0, 0xff
        sd      t2, 0(t1)
8:
        # interrupt or exception? bit 63 of mcause decides
        bltz    t0, 1f
        # ---- synchronous: resume after the faulting instruction
        li      t1, 1
        beq     t0, t1, 2f                  # instruction access fault: use the recovery address instead
        csrr    t1, mepc
        addi    t1, t1, 4
        csrw    mepc, t1
        j       3f
2:      la      t1, fetch_recover
        ld      t1, 0(t1)
        csrw    mepc, t1
        j       3f
        # ---- interrupt: count it, quiet the source, resume at mepc unchanged
1:      la      t1, irq_count
        ld      t2, 0(t1)
        addi    t2, t2, 1
        sd      t2, 0(t1)
        # remember which line, so a test can check the priority order it saw
        la      t1, irq_seen
        ld      t2, 0(t1)
        slli    t2, t2, 8
        andi    t0, t0, 0xff
        or      t2, t2, t0
        sd      t2, 0(t1)
        # Quiet the source this trap was raised for -- a handler services the line it was called about,
        # and that is also what lets a test with several lines pending walk through them in priority order.
        # Writing mip instead would do nothing, which is the property i04 checks.
        # A test may ask the handler to leave the source asserted, so that returning re-enters immediately.
        # irq_reenter_limit bounds that: once enough re-entries have happened the source is quieted anyway,
        # so the test terminates instead of spinning forever.
        la      t1, irq_leave_asserted
        ld      t2, 0(t1)
        beqz    t2, 7f
        la      t1, irq_reenter_limit
        ld      t1, 0(t1)
        la      t2, irq_count
        ld      t2, 0(t2)
        blt     t2, t1, 3f
7:      li      t1, CAUSE_MSI
        beq     t0, t1, 4f
        li      t1, CAUSE_MTI
        beq     t0, t1, 5f
        li      t2, 4                       # external
        j       6f
4:      li      t2, 1                       # software
        j       6f
5:      li      t2, 2                       # timer
6:      li      t1, IRQ_MMIO
        sd      t2, 0(t1)
3:      ld      t0, -8(sp)
        ld      t1, -16(sp)
        ld      t2, -24(sp)
        csrrw   sp, mscratch, sp
        mret

        .globl install_handler
install_handler:
        la      t0, trap_handler
        csrw    mtvec, t0
        la      t0, handler_stack_top
        csrw    mscratch, t0
        ret

        .section .data, "aw", @progbits
        .align 3
        .globl trap_count, last_cause, last_epc, last_tval, fetch_recover, handler_entry_instret
        .globl irq_count, irq_seen, irq_clear_mask, irq_leave_asserted
trap_count: .dword 0
last_cause: .dword 0
last_epc:   .dword 0
last_tval:  .dword 0
fetch_recover: .dword 0
handler_entry_instret: .dword 0
irq_count:  .dword 0
irq_seen:   .dword 0
irq_clear_mask: .dword 7
irq_leave_asserted: .dword 0
        .globl irq_reenter_limit
irq_reenter_limit: .dword 0
        .globl first_cause
first_cause: .dword 0
        .align 3
        .space 256
        .globl handler_stack_top
handler_stack_top:
        .space 64   # the handler saves below this pointer; the padding keeps it clear of test data
