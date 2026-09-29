# PIPE-P2b association gate: a store right behind an ECALL, with a trap handler whose first instructions touch no
# memory. On a correct core the store is issued only after the handler returns, and every data response is followed
# by its own instruction's retirement. Under the core's knob 4 (STORE_UNDER_TRAP) the store's request leaves in the
# ECALL's trap cycle and its response arrives while the handler's first (non-memory) instructions retire: the
# association checker must name that unrelated retirement. The program's own checks: the word is still 0 at the trap
# and 0x55 afterwards, written once per pass. (p1crt/p1mac conventions; exit 0 = pass.)
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        la      s0, st_word
        li      s1, 0x55
        la      t0, alu_handler
        csrw    mtvec, t0
        li      s3, 3               # three passes (the later ones run from a warm I-cache)
pass:
        sd      zero, 0(s0)
        ecall
        sd      s1, 0(s0)
        CHECK_EQ(s2, 0, 1)          # s2 = the word as the handler saw it
        ld      t3, 0(s0)
        CHECK_EQ(t3, 0x55, 2)
        addi    s3, s3, -1
        bnez    s3, pass
        li      a0, 0
        ret
# the first six instructions retire without touching memory; then the snapshot; resume after the ECALL
        .align 2
alu_handler:
        addi    t6, zero, 1
        addi    t6, t6, 2
        addi    t6, t6, 3
        csrr    t4, mepc
        addi    t4, t4, 4
        csrw    mepc, t4
        ld      s2, 0(s0)
        mret
        .data
        .align 3
st_word: .dword 0
