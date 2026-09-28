# dual04 (T3.5, C6.4, U2): both harts alternate peripheral-bus and DRAM accesses, 200 rounds each: their own
# mtimecmp (write, read back equal), mtime, the PLIC registers xv6 will address for THIS hart -- S-mode enable
# PLIC+0x2080+h*0x100 and S-mode priority threshold PLIC+0x201000+h*0x2000 -- and the M-mode ones
# PLIC+0x2000+h*0x80, PLIC+0x200000+h*0x1000, plus a DRAM word of their own. No access fault may occur (the
# handler records any trap as a failure). The values read back from the PLIC S-context addresses are REPORTED,
# not asserted: whether that address is a real context or an unmapped hole is what the report documents.
#include "dual.h"
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   mv      s0, a0
        slli    s1, s0, 3
        la      t0, handler
        csrw    mtvec, t0
        li      s2, 200
        li      s3, CLINT_MTIMECMP
        add     s3, s3, s1                      # own mtimecmp
        li      s4, PLIC_BASE + 0x2080
        slli    t0, s0, 8
        add     s4, s4, t0                      # xv6 PLIC_SENABLE(h)
        li      s5, PLIC_BASE + 0x201000
        slli    t0, s0, 13
        add     s5, s5, t0                      # xv6 PLIC_SPRIORITY(h)
        li      s6, PLIC_BASE + 0x2000
        slli    t0, s0, 7
        add     s6, s6, t0                      # M-mode enable(h)
        li      s7, PLIC_BASE + 0x200000
        slli    t0, s0, 12
        add     s7, s7, t0                      # M-mode threshold(h)
        la      s8, dram
        add     s8, s8, s1
loop:   li      t0, -1
        sd      t0, 0(s3)                       # mtimecmp = far away
        ld      t1, 0(s3)
        bne     t1, t0, f50
        li      t0, CLINT_MTIME
        ld      t1, 0(t0)
        sd      t1, 0(s8)                       # DRAM
        li      t0, 0x2
        sw      t0, 0(s4)                       # S enable (xv6's address for this hart)
        lw      t2, 0(s4)
        sw      zero, 0(s4)
        li      t0, 0x0
        sw      t0, 0(s5)                       # S threshold
        lw      t3, 0(s5)
        sw      zero, 0(s6)                     # M enable
        lw      t4, 0(s6)
        sw      zero, 0(s7)                     # M threshold
        lw      t5, 0(s7)
        ld      t6, 0(s8)
        bne     t6, t1, f51
        addi    s2, s2, -1
        bnez    s2, loop
        la      t0, rb_senable
        add     t0, t0, s1
        sd      t2, 0(t0)                       # what the S-enable address read back after writing 0x2
        la      t0, rb_sprio
        add     t0, t0, s1
        sd      t3, 0(t0)
        BARRIER(b1, NHARTS, t0)
        bnez    s0, park
        la      t0, traps
        ld      t1, 0(t0)
        bnez    t1, f52
        ld      t1, 8(t0)
        bnez    t1, f53
        la      a0, msg_ok
        call    htif_puts
        la      t0, rb_senable
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_sp
        call    htif_puts
        la      t0, rb_senable
        ld      a0, 8(t0)
        call    htif_puthex
        la      a0, msg_prio
        call    htif_puts
        la      t0, rb_sprio
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_sp
        call    htif_puts
        la      t0, rb_sprio
        ld      a0, 8(t0)
        call    htif_puthex
        la      a0, msg_nl
        call    htif_puts
        li      a0, 0
        call    htif_exit
f50: la a0, msg_fail; call htif_puts; FAIL(50)
f51: la a0, msg_fail; call htif_puts; FAIL(51)
f52: la a0, msg_fail; call htif_puts; FAIL(52)
f53: la a0, msg_fail; call htif_puts; FAIL(53)
park:   wfi
        j       park
        .align 2
handler:                                        # any trap is a failure here: record and skip
        addi    sp, sp, -32
        sd      t0, 0(sp)
        sd      t1, 8(sp)
        sd      t2, 16(sp)
        csrr    t1, mhartid
        slli    t1, t1, 3
        la      t2, traps
        add     t2, t2, t1
        ld      t0, 0(t2)
        addi    t0, t0, 1
        sd      t0, 0(t2)
        csrr    t0, mcause
        la      t2, trap_cause
        add     t2, t2, t1
        sd      t0, 0(t2)
        csrr    t0, mepc
        addi    t0, t0, 4
        csrw    mepc, t0
        ld      t0, 0(sp)
        ld      t1, 8(sp)
        ld      t2, 16(sp)
        addi    sp, sp, 32
        mret
        .section .data
        .align 3
b1:     .word 0
        .word 0
dram:       .dword 0, 0
traps:      .dword 0, 0
trap_cause: .dword 0, 0
rb_senable: .dword 0, 0
rb_sprio:   .dword 0, 0
msg_ok:   .asciz "M2B-PBUS-OK senable_rb=0x"
msg_prio: .asciz " sprio_rb=0x"
msg_sp:   .asciz " 0x"
msg_nl:   .asciz "\n"
msg_fail: .asciz "M2B-PBUS-FAIL\n"
