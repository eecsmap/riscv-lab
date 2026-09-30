# PIPE-P4c frequency reference for the TWO-hart image. P3b's freq_spin.S assumed one hart; on the dual SoC the boot
# ROM sends BOTH harts to 0x80000000, where two copies of that program would share a stack and race on tohost. This
# one uses the M2b dual entry (start.S: a stack per hart, main(hartid)): hart 1 records its mhartid, raises a flag and
# parks in WFI; hart 0 waits for the flag (so the run also shows hart 1 came up), then spins for exactly SPIN_CYCLES
# of its own `cycle` CSR and reports the same line as freq_spin.S (freq_judge.py parses it unchanged), plus hart 1's id.
#include "dual.h"
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   bnez    a0, hart1
        WAIT_EQ(h1_here, 1, t0)
        li      s5, CLINT_MTIME
        ld      s3, 0(s5)                 # mtime before
        csrr    s1, cycle                 # cycle before
        li      t0, SPIN_CYCLES
        add     s2, s1, t0                # target
1:      csrr    t1, cycle
        bltu    t1, s2, 1b
        ld      s4, 0(s5)                 # mtime after
        sub     s6, t1, s1                # cycles actually spun (>= SPIN_CYCLES)
        sub     s4, s4, s3                # mtime units across the spin (s7-s11 are NOT used: M2b's htif_puthex
                                          # clobbers s7-s9 and htif_puts s10-s11; the first sim run printed -4)
        la      a0, l_cyc
        call    htif_puts
        mv      a0, s6
        call    htif_puthex
        la      a0, l_mt
        call    htif_puts
        mv      a0, s4
        call    htif_puthex
        la      a0, l_h1
        call    htif_puts
        la      t0, h1_id
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, marker
        call    htif_puts
        li      a0, 0
        call    htif_exit
hart1:  la      t0, h1_id
        sd      a0, 0(t0)
        fence   rw, rw
        la      t0, h1_here
        li      t1, 1
        sw      t1, 0(t0)
park:   wfi
        j       park
        .section .rodata
l_cyc:  .asciz "FREQ-SPIN cycles=0x"
l_mt:   .asciz " mtime_delta=0x"
l_h1:   .asciz " hart1_id=0x"
marker: .asciz "\nTEACHING-FREQ-SPIN-OK\n"
        .section .data
        .align 3
h1_id:  .dword 0xffffffffffffffff
h1_here: .word 0
