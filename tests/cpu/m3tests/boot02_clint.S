# M3-c: the real CLINT, as a closed loop. Both machine sources are driven from software through the device
# itself -- no harness back door and no test MMIO -- and each is quieted the way the device requires: msip by
# writing it, mtip by moving mtimecmp into the future.
#include "m3lib.h"
        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top
        la      t0, trap_vector
        csrw    mtvec, t0
        la      t0, handler_stack_top   # the handler borrows mscratch as its scratch pointer
        csrw    mscratch, t0
        # ---- quiet the timer first: mtimecmp is not reset, so it must be pushed out before MIE goes on
        li      t0, CLINT_MTIMECMP
        li      t1, -1
        sd      t1, 0(t0)
        csrr    t1, mip
        andi    t1, t1, MIP_MTIP
        CHECK_EQ(t1, 0, 1)
        # ---- the hole inside the CLINT window: msip for a hart that does not exist
        li      t0, CLINT_MSIP1
        li      t1, 1
        sw      t1, 0(t0)               # must be answered, not an access fault
        lw      t2, 0(t0)
        CHECK_EQ(t2, 0, 2)              # and must read back zero, which is what ends the ROM's wake loop
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 0, 3)              # none of that trapped
        # ---- machine software interrupt, end to end
        li      t0, MIE_MSIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        li      t0, CLINT_MSIP
        li      t1, 1
        sw      t1, 0(t0)               # raise it through the device
        li      s4, 100000
1:      la      t0, irq_count
        ld      t1, 0(t0)
        li      t2, 1
        bge     t1, t2, 2f
        addi    s4, s4, -1
        bnez    s4, 1b
        FAIL(4, t0)
2:      la      t0, last_cause
        ld      t1, 0(t0)
        li      t2, -1
        srli    t2, t2, 1
        not     t2, t2                  # 1 << 63
        ori     t2, t2, 3
        CHECK_EQ_R(t1, t2, 5)
        csrr    t1, mip
        andi    t1, t1, MIP_MSIP
        CHECK_EQ(t1, 0, 6)              # the handler cleared it at the device
        # ---- machine timer interrupt, end to end
        li      t0, MIE_MTIE
        csrw    mie, t0
        li      t0, CLINT_MTIME
        ld      t1, 0(t0)
        addi    t1, t1, 2
        li      t0, CLINT_MTIMECMP
        sd      t1, 0(t0)               # due almost immediately
        li      s4, 1000000
3:      la      t0, irq_count
        ld      t1, 0(t0)
        li      t2, 2
        bge     t1, t2, 4f
        addi    s4, s4, -1
        bnez    s4, 3b
        FAIL(7, t0)
4:      la      t0, last_cause
        ld      t1, 0(t0)
        li      t2, -1
        srli    t2, t2, 1
        not     t2, t2
        ori     t2, t2, 7
        CHECK_EQ_R(t1, t2, 8)
        csrr    t1, mip
        andi    t1, t1, MIP_MTIP
        CHECK_EQ(t1, 0, 9)              # quieted by moving the comparison, not by writing mip
        # ---- the global mask really masks: raise msip again with MIE clear
        li      t0, MSTATUS_MIE
        csrc    mstatus, t0
        li      t0, CLINT_MSIP
        li      t1, 1
        sw      t1, 0(t0)
        li      s4, 3000
5:      addi    s4, s4, -1
        bnez    s4, 5b
        csrr    t1, mip
        andi    t1, t1, MIP_MSIP
        CHECK_EQ(t1, MIP_MSIP, 10)      # the level is up ...
        la      t0, irq_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 2, 11)             # ... and nothing more was accepted
        li      t0, CLINT_MSIP
        sw      zero, 0(t0)
        la      a0, okmsg
        call    htif_puts
        li      a0, 0
        call    htif_exit

        .align 2
trap_vector:
        csrrw   sp, mscratch, sp
        sd      t0, -8(sp)
        sd      t1, -16(sp)
        sd      t2, -24(sp)
        csrr    t0, mcause
        la      t1, last_cause
        sd      t0, 0(t1)
        bltz    t0, 1f
        # a synchronous exception is a failure of this test; count it and step over the instruction
        la      t1, trap_count
        ld      t2, 0(t1)
        addi    t2, t2, 1
        sd      t2, 0(t1)
        csrr    t1, mepc
        addi    t1, t1, 4
        csrw    mepc, t1
        j       2f
1:      la      t1, irq_count
        ld      t2, 0(t1)
        addi    t2, t2, 1
        sd      t2, 0(t1)
        # quiet the source this interrupt was raised for, at the device itself
        andi    t0, t0, 0xff
        li      t1, 3
        beq     t0, t1, 3f
        li      t1, CLINT_MTIMECMP      # timer: move the comparison out of reach
        li      t2, -1
        sd      t2, 0(t1)
        j       2f
3:      li      t1, CLINT_MSIP          # software: clear the register
        sw      zero, 0(t1)
2:      ld      t0, -8(sp)
        ld      t1, -16(sp)
        ld      t2, -24(sp)
        csrrw   sp, mscratch, sp
        mret

        .section .rodata, "a", @progbits
okmsg:  .asciz "M3-CLINT-OK\n"
        .section .data, "aw", @progbits
        .align 3
        .globl trap_count, irq_count, last_cause
trap_count: .dword 0
irq_count:  .dword 0
last_cause: .dword 0
        .align 3
        .space 256
        .globl handler_stack_top
handler_stack_top:
