# PIPE-P3b frequency reference: spin for exactly SPIN_CYCLES core cycles (the `cycle` CSR), then report and exit.
# The ARM times two builds of this program (short and long) with its own clock; the difference of the two elapsed
# times is SPIN_CYCLES(long) - SPIN_CYCLES(short) core cycles, so f = delta cycles / delta PS seconds, independent
# of mtime and of the CPU's own idea of time. The program also prints the CLINT mtime delta across the spin (a
# cross-check: mtime = cycles / 100 on this SoC), and the measured cycle count.
#include "m3lib.h"
        .section .text.start, "ax", @progbits
        .globl _start
        .option norvc
_start: la      sp, _stack_top
        li      s5, CLINT_MTIME
        ld      s3, 0(s5)                 # mtime before
        csrr    s1, cycle                 # cycle before
        li      t0, SPIN_CYCLES
        add     s2, s1, t0                # target
1:      csrr    t1, cycle
        bltu    t1, s2, 1b
        ld      s4, 0(s5)                 # mtime after
        sub     s6, t1, s1                # cycles actually spun (>= SPIN_CYCLES)
        sub     s7, s4, s3                # mtime units across the spin
        la      a0, l_cyc
        call    htif_puts
        mv      a0, s6
        call    puthex
        la      a0, l_mt
        call    htif_puts
        mv      a0, s7
        call    puthex
        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit
# puthex: a0 as 16 hex digits
puthex: addi    sp, sp, -32
        sd      ra, 0(sp)
        sd      s0, 8(sp)
        sd      s1, 16(sp)
        mv      s0, a0
        li      s1, 60
2:      srl     a0, s0, s1
        andi    a0, a0, 15
        li      t0, 10
        blt     a0, t0, 3f
        addi    a0, a0, 'a' - 10
        j       4f
3:      addi    a0, a0, '0'
4:      call    htif_putc
        addi    s1, s1, -4
        bgez    s1, 2b
        ld      ra, 0(sp)
        ld      s0, 8(sp)
        ld      s1, 16(sp)
        addi    sp, sp, 32
        ret
        .section .rodata
l_cyc:  .asciz "FREQ-SPIN cycles=0x"
l_mt:   .asciz " mtime_delta=0x"
marker: .asciz "\nTEACHING-FREQ-SPIN-OK\n"
