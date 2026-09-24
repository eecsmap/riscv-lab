# The program the port testbench runs. Two phases, because the defect that prompted all this lived in
# the second one.
#
#   BARE   32-bit instructions at pc%4==0 (the wide path), a compressed instruction, and 32-bit
#          instructions at pc%4==2 (the two-parcel fallback).
#
#   SV39   the same shapes, but executed with translation ON. This is the phase that matters: the fetch
#          is then issued from S_XLATE after the walk, and the first version of OPT01 left that issue at
#          two bytes while consuming four. Against a memory that poisons every byte outside the request,
#          that core reads 0xEE into the upper half of its instruction and cannot reach the sentinel.
#
# The sentinel store is the only success signal. Anything that goes wrong -- a garbage instruction, a
# trap, a wrong value -- leaves it unwritten or wrong.
        .equ SENTINEL, 0x3000
        .equ MAGIC,    0x600d
        .equ PHASEMARK, 0x3010
#define PTE_V 0x01
#define PTE_R 0x02
#define PTE_W 0x04
#define PTE_X 0x08
#define PTE_A 0x40
#define PTE_D 0x80

        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start:
        li      sp, 0x2f00

# ---- BARE phase ---------------------------------------------------------------------------------------
        .align  2
        li      t0, 0x111               # pc%4 == 0: the wide path
        li      t1, 0x222
        add     s1, t0, t1              # 0x333
        li      t2, 0x333
        bne     s1, t2, fail

        .option rvc
        c.nop                           # shift alignment
        .option norvc
        li      t0, 0x444               # now pc%4 == 2: the two-parcel fallback
        li      t1, 0x555
        add     s2, t0, t1              # 0x999
        li      t2, 0x999
        bne     s2, t2, fail

# ---- build an identity map and turn translation on ----------------------------------------------------
        la      t0, root
        la      t1, l1
        srli    t2, t1, 12
        slli    t2, t2, 10
        ori     t2, t2, PTE_V
        sd      t2, 0(t0)               # root[0] -> l1      (VPN[2] of a low VA is 0)
        la      t0, l1
        la      t1, l0
        srli    t2, t1, 12
        slli    t2, t2, 10
        ori     t2, t2, PTE_V
        sd      t2, 0(t0)               # l1[0] -> l0        (VPN[1] is 0)

        la      t0, l0                  # l0[i] -> 4 KiB leaf at i*4096, identity, for 16 pages
        li      t1, 0
        li      t2, PTE_V|PTE_R|PTE_W|PTE_X|PTE_A|PTE_D
        li      t3, 16
        li      t4, (1 << 10)
1:      or      t5, t1, t2
        sd      t5, 0(t0)
        add     t1, t1, t4
        addi    t0, t0, 8
        addi    t3, t3, -1
        bnez    t3, 1b
        fence

        # tell the bench the translated phase is about to begin. It watches this word rather than
        # reaching into the core, so the test depends on no internal signal.
        li      t0, PHASEMARK
        li      t1, 1
        sw      t1, 0(t0)
        fence

        la      t0, sv39_phase
        csrw    mepc, t0
        li      t1, (3 << 11)
        csrc    mstatus, t1             # MPP = 00
        li      t1, (1 << 11)
        csrs    mstatus, t1             # MPP = 01, S-mode
        la      t2, root
        srli    t2, t2, 12
        li      t6, 8
        slli    t6, t6, 60              # MODE = Sv39
        or      t6, t6, t2
        csrw    satp, t6
        sfence.vma
        mret

# ---- SV39 phase: every fetch below is translated ------------------------------------------------------
        .align  2
sv39_phase:
        li      t0, 0x666               # pc%4 == 0 under translation: the post-walk wide issue
        li      t1, 0x777
        add     s3, t0, t1              # 0xddd
        li      t2, 0xddd
        bne     s3, t2, fail

        .option rvc
        c.nop
        .option norvc
        li      t0, 0x888               # pc%4 == 2 under translation: post-walk fallback, two parcels
        li      t1, 0x999
        add     s4, t0, t1              # 0x1221
        li      t2, 0x1221
        bne     s4, t2, fail

        # every phase agreed: write the sentinel
        li      t0, SENTINEL
        li      t1, MAGIC
        sw      t1, 0(t0)
        fence
halt:   j       halt

fail:   li      t0, SENTINEL
        li      t1, 0xbad
        sw      t1, 0(t0)
        fence
fhalt:  j       fhalt

        .section .data, "aw", @progbits
        .align 12
root:   .zero 4096
        .align 12
l1:     .zero 4096
        .align 12
l0:     .zero 4096
