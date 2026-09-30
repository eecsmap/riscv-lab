# PIPE-P4a dual08: hart 1 runs a store right behind an ECALL, three times, with a trap handler whose first
# instructions touch no memory (the p2b_assoc_trap pattern, moved to the second hart). On a correct core the store
# is issued only after the handler returns: the handler's snapshot of the word is 0 at every trap and the word is
# 0x55 afterwards, written once per pass. Hart 0 waits for hart 1 and reports (only hart 0 talks to the host).
# Used as the program on which the core's knob 4 on HART 1 ONLY must be caught by hart 1's association checker
# while hart 0's stays clean; on the delivered integration it must pass.
#include "dual.h"
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   bnez    a0, hart1
        # ---- hart 0: wait for hart 1, then check its record
        WAIT_EQ(h1_done, 1, t0)
        la      t0, h1_snapfail
        ld      t1, 0(t0)
        bnez    t1, 91f
        la      t0, h1_traps
        ld      t1, 0(t0)
        li      t2, 3
        bne     t1, t2, 92f
        la      t0, st_word
        ld      t1, 0(t0)
        li      t2, 0x55
        bne     t1, t2, 93f
        la      a0, okmsg
        call    htif_puts
        li      a0, 0
        call    htif_exit
91:     FAIL(1)
92:     FAIL(2)
93:     FAIL(3)
        # ---- hart 1
hart1:  la      t0, h1_handler
        csrw    mtvec, t0
        la      s0, st_word
        li      s1, 0x55
        li      s3, 3
1:      sd      zero, 0(s0)
        ecall
        sd      s1, 0(s0)
        ld      t3, 0(s0)
        bne     t3, s1, 2f
        addi    s3, s3, -1
        bnez    s3, 1b
        fence   rw, rw
        la      t0, h1_done
        li      t1, 1
        sw      t1, 0(t0)
3:      wfi
        j       3b
2:      la      t0, h1_snapfail
        li      t1, 2
        sd      t1, 0(t0)
        fence   rw, rw
        la      t0, h1_done
        li      t1, 1
        sw      t1, 0(t0)
        j       3b
        .align 2
h1_handler:
        addi    t6, zero, 1
        addi    t6, t6, 2
        addi    t6, t6, 3
        csrr    t4, mepc
        addi    t4, t4, 4
        csrw    mepc, t4
        ld      t5, 0(s0)                       # the word as the handler sees it: must be 0
        beqz    t5, 4f
        la      t4, h1_snapfail
        sd      t5, 0(t4)
4:      la      t4, h1_traps
        ld      t5, 0(t4)
        addi    t5, t5, 1
        sd      t5, 0(t4)
        mret
        .section .rodata
okmsg:  .asciz "P4A-DUAL08-OK\n"
        .data
        .align 3
st_word:     .dword 0
h1_snapfail: .dword 0
h1_traps:    .dword 0
h1_done:     .word 0
