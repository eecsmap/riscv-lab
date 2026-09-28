# ROI kernels for the retirement-interval measurement. Each ROI is bounded by a label pair roiN_b / roiN_e;
# the runner measures cycles between the retirement of the first instruction after roiN_b and the retirement of
# the instruction at roiN_e, and the number of retirements in between (warm I-cache: each kernel runs twice and
# only the second pass is the ROI).
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        la      s0, pf_data
        li      s7, 2               # two passes
pass:
        # ---- ROI 1: 64 independent ALU instructions (steady-state II target = 1)
roi1_b: nop
        .rept 16
        addi    t0, t0, 1
        addi    t1, t1, 1
        addi    t2, t2, 1
        addi    t3, t3, 1
        .endr
roi1_e: nop
        # ---- ROI 2: 64 dependent ALU instructions (a chain through EX/MEM forwarding)
roi2_b: nop
        .rept 64
        addi    t4, t4, 1
        .endr
roi2_e: nop
        # ---- ROI 3: 16 load + dependent-use pairs (load-use)
roi3_b: nop
        .rept 16
        ld      t5, 0(s0)
        add     t6, t6, t5
        .endr
roi3_e: nop
        # ---- ROI 4: a taken-branch loop, 32 iterations of 2 instructions
        li      a2, 32
roi4_b: nop
1:      addi    a2, a2, -1
        bnez    a2, 1b
roi4_e: nop
        # ---- ROI 5: 16 independent stores
roi5_b: nop
        .rept 16
        sd      t0, 8(s0)
        .endr
roi5_e: nop
        addi    s7, s7, -1
        bnez    s7, pass
        li      a0, 0
        ret
        .data
        .align 3
pf_data: .dword 7, 0
