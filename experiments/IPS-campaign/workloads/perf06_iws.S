# Instruction working set: one that FITS the frozen 1 KiB I-cache and one that cannot.
#
# The cache stage needs a workload it must miss in, or "fewer external instruction reads" is measured
# against nothing. Two ROIs in one binary, the same shape perf03 uses:
#
#   RESIDENT   a 32-instruction body   =   128 bytes   -- one eighth of the 1 KiB cache
#   EXCEEDS    a 1024-instruction body =  4096 bytes   -- four times its capacity, so a direct-mapped
#                                                         1 KiB cache conflicts on every pass
#
# Both bodies are `addi` on one register: no loads, no stores, no branches inside the body. Whatever
# separates the two ROIs is instruction FETCH and nothing else. On the baseline core, which has no
# cache, the two should cost the same per instruction; that is the point of running it there first.
#
# .option norvc throughout: every instruction is 4 bytes, so the footprint is exactly countable and the
# assembler may not shrink the body into something smaller than the cache.
#include "m3lib.h"

        .equ RESIDENT_BODY, 32
        .equ RESIDENT_ITERS, 2000
        .equ EXCEEDS_BODY, 1024
        .equ EXCEEDS_ITERS, 64

# Retirement per ROI, exactly: iterations 1..N-1 retire BODY + addi + beqz + j, the last retires
# BODY + addi + beqz, and the two trailing csrr fall inside the window --
#   N*(BODY+3) - 1 + 2  =  N*(BODY+3) + 1
        .equ RESIDENT_RETIRED, RESIDENT_ITERS * (RESIDENT_BODY + 3) + 1
        .equ EXCEEDS_RETIRED,  EXCEEDS_ITERS  * (EXCEEDS_BODY  + 3) + 1

        .section .text.start, "ax", @progbits
        .globl _start
        .option norvc
_start: la      sp, _stack_top
        la      s8, results

        call    measure_resident
        sd      a0, 0(s8)
        sd      a1, 8(s8)
        call    measure_exceeds
        sd      a0, 16(s8)
        sd      a1, 24(s8)

        # Each window must have retired exactly what its shape predicts. If it did not, the window did
        # not run as described and its cycle count is about some other program.
        li      t3, RESIDENT_RETIRED
        ld      t5, 8(s8)
        bne     t5, t3, fail
        li      t3, EXCEEDS_RETIRED
        ld      t5, 24(s8)
        bne     t5, t3, fail

        la      s2, labels
        la      s3, results
        li      s4, 4
3:      mv      a0, s2
        call    htif_puts
        ld      a0, 0(s3)
        call    puthex
        addi    s3, s3, 8
4:      lbu     t0, 0(s2)
        addi    s2, s2, 1
        bnez    t0, 4b
        addi    s4, s4, -1
        bnez    s4, 3b

        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit
fail:   la      a0, failmark
        call    htif_puts
        li      a0, 1
        call    htif_exit

# ---- RESIDENT: 128 bytes of body, re-entered RESIDENT_ITERS times.
        .align 6
measure_resident:
        li      t6, RESIDENT_ITERS
        csrr    t4, cycle
        csrr    t5, instret
1:      .rept   RESIDENT_BODY
        addi    t1, t1, 1
        .endr
        addi    t6, t6, -1
        beqz    t6, 2f
        j       1b
2:      csrr    a0, cycle
        csrr    a1, instret
        sub     a0, a0, t4
        sub     a1, a1, t5
        ret

# ---- EXCEEDS: 4096 bytes of body. The backward branch is `j`, not `bnez`, because a conditional
# branch reaches only +/-4 KiB and the assembler would relax it into a different instruction sequence --
# which would change the retirement count this probe asserts.
        .align 6
measure_exceeds:
        li      t6, EXCEEDS_ITERS
        csrr    t4, cycle
        csrr    t5, instret
1:      .rept   EXCEEDS_BODY
        addi    t1, t1, 1
        .endr
        addi    t6, t6, -1
        beqz    t6, 2f
        j       1b
2:      csrr    a0, cycle
        csrr    a1, instret
        sub     a0, a0, t4
        sub     a1, a1, t5
        ret

# ---- a0 as 16 hex digits then a newline.
puthex: mv      s5, a0
        mv      s7, ra
        li      s6, 60
1:      srl     t0, s5, s6
        andi    t0, t0, 15
        li      t1, 10
        blt     t0, t1, 2f
        addi    t0, t0, 87
        j       3f
2:      addi    t0, t0, 48
3:      mv      a0, t0
        call    htif_putc
        addi    s6, s6, -4
        bgez    s6, 1b
        li      a0, 10
        call    htif_putc
        mv      ra, s7
        ret

        .section .rodata, "a", @progbits
labels: .asciz "IWS-CYC-RESIDENT="
        .asciz "IWS-INS-RESIDENT="
        .asciz "IWS-CYC-EXCEEDS="
        .asciz "IWS-INS-EXCEEDS="
marker:   .asciz "TEACHING-PERF-IWS-OK\n"
failmark: .asciz "TEACHING-PERF-IWS-FAIL\n"

        .section .data, "aw", @progbits
        .align 3
results: .zero 32
