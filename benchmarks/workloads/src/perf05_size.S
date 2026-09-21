# Performance probe: does the size of an access change what it costs?
#
# B0 measures one DRAM round-trip at roughly 18-19 cycles and shows the achieved bandwidth to be a small
# fraction of what the 64-bit HP port could carry. Two explanations were on the table: the access
# GRANULARITY (a 2-byte parcel fetch uses a quarter of one 64-bit beat) or the CONCURRENCY (one
# outstanding access, so bandwidth is size divided by latency however wide the bus is).
#
# This discriminates. The same loop, same address, same alignment, seven times, differing in exactly one
# instruction: an ALU baseline, then loads of 1, 2, 4 and 8 bytes, then stores of 1 and 8.
#
#   all seven equal      -> cost is pure latency. Size is irrelevant and widening accesses buys nothing;
#                           only fewer round-trips or more of them in flight can help.
#   cost rises with size -> the transfer itself is on the critical path and granularity matters.
#   sb dearer than sd    -> sub-word writes are being turned into read-modify-write somewhere below.
#
# The address is one 8-byte-aligned word, so every access is naturally aligned and no case is penalised
# for alignment rather than for size.
#include "m3lib.h"

        .equ ITERS, 10000

        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start

        .macro MEASURE name, insn
\name:  mv      t6, a0
        csrr    t4, cycle
        csrr    t5, instret
1:      \insn
        addi    t6, t6, -1
        bnez    t6, 1b
        csrr    a0, cycle
        csrr    a1, instret
        sub     a0, a0, t4
        sub     a1, a1, t5
        ret
        .endm

_start: la      sp, _stack_top
        la      s8, results
        la      s9, scratch

        .macro RUN name, slot
        li      a0, ITERS
        call    \name
        sd      a0, (\slot * 16)(s8)
        sd      a1, (\slot * 16 + 8)(s8)
        .endm

        RUN m_alu, 0
        RUN m_lb,  1
        RUN m_lh,  2
        RUN m_lw,  3
        RUN m_ld,  4
        RUN m_sb,  5
        RUN m_sd,  6

        li      t3, (ITERS * 3 + 2)
        li      t4, 7
        la      t0, results
        addi    t0, t0, 8
2:      ld      t5, 0(t0)
        bne     t5, t3, fail
        addi    t0, t0, 16
        addi    t4, t4, -1
        bnez    t4, 2b

        la      s2, labels
        la      s3, results
        li      s4, 14
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

        MEASURE m_alu, "addi t1, t1, 1"
        MEASURE m_lb,  "lb   t1, 0(s9)"
        MEASURE m_lh,  "lh   t1, 0(s9)"
        MEASURE m_lw,  "lw   t1, 0(s9)"
        MEASURE m_ld,  "ld   t1, 0(s9)"
        MEASURE m_sb,  "sb   x0, 0(s9)"
        MEASURE m_sd,  "sd   x0, 0(s9)"

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
labels: .asciz "SIZE-CYC-ALU="
        .asciz "SIZE-INS-ALU="
        .asciz "SIZE-CYC-LB="
        .asciz "SIZE-INS-LB="
        .asciz "SIZE-CYC-LH="
        .asciz "SIZE-INS-LH="
        .asciz "SIZE-CYC-LW="
        .asciz "SIZE-INS-LW="
        .asciz "SIZE-CYC-LD="
        .asciz "SIZE-INS-LD="
        .asciz "SIZE-CYC-SB="
        .asciz "SIZE-INS-SB="
        .asciz "SIZE-CYC-SD="
        .asciz "SIZE-INS-SD="
marker:   .asciz "TEACHING-PERF-SIZE-OK\n"
failmark: .asciz "TEACHING-PERF-SIZE-FAIL\n"

        .section .data, "aw", @progbits
        .align 3
results: .zero 112
scratch: .dword 0x0123456789abcdef
