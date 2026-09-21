# Performance probe: is the instruction fetch really two memory round-trips?
#
# tcpu_core.v fetches ONE 16-bit parcel at a time. S_IF_REQ issues a `core_req_size = 2'd1` read at pc;
# when the parcel turns out not to be compressed, S_IF2_REQ issues a SECOND read at pc+2. There is
# no aligned-32-bit fast path. So a 32-bit instruction costs two round-trips and a compressed one costs
# a single round-trip -- and that, not any property of the memory, would be why an instruction fetch
# appeared to cost about twice what a data load costs in perf01 and perf02.
#
# This measures the same loop twice in one binary:
#
#   A  three 32-bit instructions     S_IF_REQ + wait + S_IF2_REQ + wait + EXEC + WB + ARCH  = 5 + 2L
#   B  three COMPRESSED instructions S_IF_REQ + wait + EXEC + WB + ARCH                     = 4 + 1L
#
# Both retire exactly three instructions per iteration, so the comparison is per-instruction like for
# like. Then
#
#   L  = CPI_A - CPI_B - 1        one memory round-trip, in cycles
#   FSM = CPI_B - L               the fixed state overhead per instruction
#
# If the hypothesis is wrong -- if the two-parcel path is not what costs the time -- the two CPIs come out
# equal and this probe says so.
#include "m3lib.h"

        .equ ITERS, 10000

        .section .text.start, "ax", @progbits
        .globl _start
        .option norvc
_start: la      sp, _stack_top
        la      s8, results

        li      a0, ITERS
        call    measure_32
        sd      a0, 0(s8)
        sd      a1, 8(s8)

        li      a0, ITERS
        call    measure_c
        sd      a0, 16(s8)
        sd      a1, 24(s8)

        # both windows must have retired the same, and exactly what was intended
        li      t3, (ITERS * 3 + 2)
        ld      t5, 8(s8)
        bne     t5, t3, fail
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

# ---- A: three 32-bit instructions per iteration. norvc is in force, so the assembler may not shrink them.
        .option norvc
measure_32:
        mv      t6, a0
        csrr    t4, cycle
        csrr    t5, instret
1:      addi    t1, t1, 1
        addi    t6, t6, -1
        bnez    t6, 1b
        csrr    a0, cycle
        csrr    a1, instret
        sub     a0, a0, t4
        sub     a1, a1, t5
        ret

# ---- B: the same three instructions, compressed. c.bnez takes its source from x8-x15 only, so the
# counter is a5 and the accumulator a4. Written as explicit c.* mnemonics rather than left to the
# assembler's discretion: what is being measured is the parcel count, so it may not be a matter of taste.
        .option rvc
measure_c:
        mv      a5, a0
        csrr    t4, cycle
        csrr    t5, instret
1:      c.addi  a4, 1
        c.addi  a5, -1
        c.bnez  a5, 1b
        csrr    a0, cycle
        csrr    a1, instret
        sub     a0, a0, t4
        sub     a1, a1, t5
        ret
        .option norvc

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
labels: .asciz "FETCH-CYC-32BIT="
        .asciz "FETCH-INS-32BIT="
        .asciz "FETCH-CYC-COMPRESSED="
        .asciz "FETCH-INS-COMPRESSED="
marker:   .asciz "TEACHING-PERF-FETCH-OK\n"
failmark: .asciz "TEACHING-PERF-FETCH-FAIL\n"

        .section .data, "aw", @progbits
        .align 3
results: .zero 32
