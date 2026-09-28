# An older instruction that traps must prevent the younger store from reaching memory before the trap; after the
# handler resumes at the next instruction the store happens exactly once. Four older faults: ecall, an illegal
# instruction, a misaligned load (detected in EX), a load beyond the 32-bit physical space (detected in MEM).
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        la      s0, st_word
        li      s1, 0x55
        # the handler snapshots st_word on every trap: it must still be 0 at each trap
        la      t0, snap_handler
        csrw    mtvec, t0
        li      s3, 2               # two passes: the second runs from a warm I-cache, so the port is free
pass:
        sd      zero, 0(s0)
        ecall
        sd      s1, 0(s0)
        CHECK_EQ(s2, 0, 1)          # s2 = the word as the handler saw it
        sd      zero, 0(s0)
        .word   0x0000000b          # custom-0: illegal in P1
        sd      s1, 0(s0)
        CHECK_EQ(s2, 0, 2)
        sd      zero, 0(s0)
        addi    t1, s0, 1
        ld      t2, 0(t1)           # misaligned
        sd      s1, 0(s0)
        CHECK_EQ(s2, 0, 3)
        sd      zero, 0(s0)
        li      t1, 1
        slli    t1, t1, 40          # beyond the 32-bit physical space
        ld      t2, 0(t1)
        sd      s1, 0(s0)
        CHECK_EQ(s2, 0, 4)
        ld      t3, 0(s0)
        CHECK_EQ(t3, 0x55, 5)       # the store did happen once, after the trap
        addi    s3, s3, -1
        bnez    s3, pass
        la      t0, trap_seen
        ld      t0, 0(t0)
        CHECK_EQ(t0, 8, 6)
        li      a0, 0
        ret
# snapshot the word, count, resume after the faulting instruction
        .align 2
snap_handler:
        ld      s2, 0(s0)
        la      t4, trap_seen
        ld      t5, 0(t4)
        addi    t5, t5, 1
        sd      t5, 0(t4)
        csrr    t4, mepc
        addi    t4, t4, 4
        csrw    mepc, t4
        mret
        .data
        .align 3
st_word:   .dword 0
trap_seen: .dword 0
