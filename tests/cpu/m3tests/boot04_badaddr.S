# M3-c negative: an access the interconnect cannot serve must come back as an error and become a precise
# trap in the CPU, with the faulting instruction's own PC and the address that failed. 0x50000000 is claimed
# by no manager in this SoC (the elaboration's address map shows the gap).
#include "m3lib.h"
        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top
        la      t0, trap_vector
        csrw    mtvec, t0
        la      t0, handler_stack_top
        csrw    mscratch, t0
        li      s0, 0x50000000
        .globl bad_load
bad_load:
        ld      s1, 0(s0)               # must fault: no manager claims this address
        la      t0, trap_count
        ld      t1, 0(t0)
        CHECK_EQ(t1, 1, 1)
        la      t0, last_cause
        ld      t1, 0(t0)
        CHECK_EQ(t1, 5, 2)              # load access fault
        la      t0, last_epc
        ld      t1, 0(t0)
        la      t2, bad_load
        CHECK_EQ_R(t1, t2, 3)           # the faulting instruction's own address
        la      t0, last_tval
        ld      t1, 0(t0)
        CHECK_EQ_R(t1, s0, 4)           # the address that failed
        # the machine is still usable afterwards: DRAM still works
        la      t0, buf
        li      t1, 0x1234
        sd      t1, 0(t0)
        ld      t2, 0(t0)
        CHECK_EQ_R(t2, t1, 5)
        la      a0, okmsg
        call    htif_puts
        li      a0, 0
        call    htif_exit
        .align 2
trap_vector:
        csrrw   sp, mscratch, sp
        sd      t0, -8(sp)
        sd      t1, -16(sp)
        csrr    t0, mcause
        la      t1, last_cause
        sd      t0, 0(t1)
        csrr    t0, mepc
        la      t1, last_epc
        sd      t0, 0(t1)
        csrr    t0, mtval
        la      t1, last_tval
        sd      t0, 0(t1)
        la      t1, trap_count
        ld      t0, 0(t1)
        addi    t0, t0, 1
        sd      t0, 0(t1)
        csrr    t0, mepc
        addi    t0, t0, 4
        csrw    mepc, t0
        ld      t0, -8(sp)
        ld      t1, -16(sp)
        csrrw   sp, mscratch, sp
        mret
        .section .rodata, "a", @progbits
okmsg:  .asciz "M3-BADADDR-OK\n"
        .section .data, "aw", @progbits
        .align 3
        .globl trap_count, last_cause, last_epc, last_tval
trap_count: .dword 0
last_cause: .dword 0
last_epc:   .dword 0
last_tval:  .dword 0
buf:    .dword 0
        .align 3
        .space 256
        .globl handler_stack_top
handler_stack_top:
