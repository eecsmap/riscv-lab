# Performance probe: measured CPI, and what a load and a store actually cost.
#
# Nothing here is estimated. The core implements mcycle and minstret (tcpu_csr.v), so cycles and retired
# instructions are read from the hardware on either side of each loop and the ratio IS the CPI. The three
# loops are identical in shape -- three instructions, same branch, same counter -- and differ in exactly
# one instruction. The difference between their CPIs is therefore the cost of that one instruction, and
# of nothing else.
#
#   A   addi            the baseline: no data access, so this is fetch cost alone. With no instruction
#                       cache every fetch is a DDR read, which is why this is not 1.
#   B   ld              A plus one data read
#   C   sd              A plus one data write
#
# A fourth loop reports mcycle and mtime across the same window, giving the RTC divider as a measured
# ratio. The absolute clock does not need measuring here and deliberately is not: it is 125 MHz from the
# board oscillator on pin H16 (base.xdc constrains it at 8 ns) through an MMCM at x8/25, so 40 MHz by
# construction. What has never been checked on hardware is the consequence -- the audit in m4-prep
# derives mtime = 40 MHz / 100 = 400 kHz against a device tree that declares a 1 MHz timebase, a factor
# of 2.5. This loop measures the 100 directly. Instructions per second then follow from 40 MHz / CPI.
#
# Values are printed as fixed-width hex, one per line, and the marker is printed last and only if every
# loop retired the number of instructions it was supposed to -- so the marker means the measurements are
# of the loops described here, not of something that took a branch nobody intended.
#include "m3lib.h"

        .equ ITERS,    10000        # per measured loop
        .equ CALITERS, 20000        # enough mtime ticks to pin the divider, few enough to simulate

        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top
        la      s8, results
        la      s9, scratch

# ---- A. ALU only: fetch cost with no data access -----------------------------------------------------
        li      t0, ITERS
        li      t1, 0
        csrr    s0, mcycle
        csrr    s1, minstret
1:      addi    t1, t1, 1
        addi    t0, t0, -1
        bnez    t0, 1b
        csrr    s2, mcycle
        csrr    s3, minstret
        sub     s2, s2, s0
        sub     s3, s3, s1
        sd      s2, 0(s8)
        sd      s3, 8(s8)

# ---- B. one load added -------------------------------------------------------------------------------
        li      t0, ITERS
        csrr    s0, mcycle
        csrr    s1, minstret
2:      ld      t1, 0(s9)
        addi    t0, t0, -1
        bnez    t0, 2b
        csrr    s2, mcycle
        csrr    s3, minstret
        sub     s2, s2, s0
        sub     s3, s3, s1
        sd      s2, 16(s8)
        sd      s3, 24(s8)

# ---- C. one store added ------------------------------------------------------------------------------
        li      t0, ITERS
        csrr    s0, mcycle
        csrr    s1, minstret
3:      sd      x0, 0(s9)
        addi    t0, t0, -1
        bnez    t0, 3b
        csrr    s2, mcycle
        csrr    s3, minstret
        sub     s2, s2, s0
        sub     s3, s3, s1
        sd      s2, 32(s8)
        sd      s3, 40(s8)

# ---- D. calibration: mcycle and mtime across one long spin -------------------------------------------
        li      t2, CLINT_MTIME
        ld      s4, 0(t2)
        csrr    s0, mcycle
        li      t0, CALITERS
4:      addi    t0, t0, -1
        bnez    t0, 4b
        csrr    s2, mcycle
        li      t2, CLINT_MTIME
        ld      s5, 0(t2)
        sub     s2, s2, s0
        sub     s5, s5, s4
        sd      s2, 48(s8)
        sd      s5, 56(s8)

# ---- the loops must have retired what they were supposed to ------------------------------------------
# Each measured loop body is 3 instructions x ITERS, plus the two csrr that close the window. If a loop
# retired anything else it did not run as described, and then its cycle count is a number about some
# other program. Refusing here is the difference between a measurement and a plausible-looking figure.
        # Computed by the assembler, not by a mul: this probe has no business needing the M extension,
        # and the scope check would be right to object if it did.
        li      t3, (ITERS * 3 + 2)
        ld      t5, 8(s8)
        bne     t5, t3, fail
        ld      t5, 24(s8)
        bne     t5, t3, fail
        ld      t5, 40(s8)
        bne     t5, t3, fail

# ---- report ------------------------------------------------------------------------------------------
        la      a0, l_cyc_alu
        call    htif_puts
        ld      a0, 0(s8)
        call    puthex
        la      a0, l_ins_alu
        call    htif_puts
        ld      a0, 8(s8)
        call    puthex

        la      a0, l_cyc_ld
        call    htif_puts
        ld      a0, 16(s8)
        call    puthex
        la      a0, l_ins_ld
        call    htif_puts
        ld      a0, 24(s8)
        call    puthex

        la      a0, l_cyc_st
        call    htif_puts
        ld      a0, 32(s8)
        call    puthex
        la      a0, l_ins_st
        call    htif_puts
        ld      a0, 40(s8)
        call    puthex

        la      a0, l_cyc_cal
        call    htif_puts
        ld      a0, 48(s8)
        call    puthex
        la      a0, l_mt_cal
        call    htif_puts
        ld      a0, 56(s8)
        call    puthex

        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit

fail:   la      a0, failmark
        call    htif_puts
        li      a0, 1
        call    htif_exit

# ---- a0 printed as 16 hex digits then a newline.
# htif_putc clobbers t0-t3 and a0 and preserves ra; htif_puts additionally uses s10/s11. So the state that
# must survive the call lives in s5-s7, and nothing above may rely on those once reporting starts.
puthex: mv      s5, a0
        mv      s7, ra
        li      s6, 60
1:      srl     t0, s5, s6
        andi    t0, t0, 15
        li      t1, 10
        blt     t0, t1, 2f
        addi    t0, t0, 87              # 'a' - 10
        j       3f
2:      addi    t0, t0, 48              # '0'
3:      mv      a0, t0
        call    htif_putc               # clobbers ra; s7 is what the return address lives in
        addi    s6, s6, -4
        bgez    s6, 1b
        li      a0, 10
        call    htif_putc
        mv      ra, s7
        ret

        .section .rodata, "a", @progbits
l_cyc_alu: .asciz "PERF-CYC-ALU="
l_ins_alu: .asciz "PERF-INS-ALU="
l_cyc_ld:  .asciz "PERF-CYC-LD="
l_ins_ld:  .asciz "PERF-INS-LD="
l_cyc_st:  .asciz "PERF-CYC-ST="
l_ins_st:  .asciz "PERF-INS-ST="
l_cyc_cal: .asciz "PERF-CYC-CAL="
l_mt_cal:  .asciz "PERF-MTIME-CAL="
marker:    .asciz "TEACHING-PERF-OK\n"
failmark:  .asciz "TEACHING-PERF-FAIL\n"

        .section .data, "aw", @progbits
        .align 3
results:   .zero 64
scratch:   .dword 0x0123456789abcdef
