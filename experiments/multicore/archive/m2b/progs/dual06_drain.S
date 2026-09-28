# dual06 v2 (drain with two real cores that have DRAM WRITES in flight). Each hart streams `sd` into its own
# SCRATCH region that lies OUTSIDE the ELF image (so the host's reload after the reset does not rewrite it):
# word i of hart h = 0xA5 <<56 | h<<48 | i. Every 16th word also does an amoadd on a scratch word. The harness
# injects the soft reset while both harts have a transaction in flight during this store stream; the host
# reloads the ELF and re-wakes; the SECOND run finds the epoch word (also outside the image) set to MAGIC and,
# before streaming again, counts how many words of its region from index 0 hold the pattern (the survived
# prefix) -- that count is reported and the checker equates it with the number of writes that hart issued
# before the hold (including the one in flight), each of which must also appear exactly once on the AXI side.
#include "dual.h"
#define NWORDS 2048
#define SCRATCH   0x80020000        /* hart h: SCRATCH + h*0x4000 (16 KiB each); both far beyond the image */
#define AMOW      0x80028000        /* hart h: AMOW + h*64 */
#define EPOCHW    0x80028100        /* one word: MAGIC after the first run has started */
#define MAGIC     0x5EC0D0D0
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   mv      s0, a0
        li      s2, SCRATCH
        slli    t0, s0, 14
        add     s2, s2, t0                      # own scratch base
        li      s6, AMOW
        slli    t0, s0, 6
        add     s6, s6, t0                      # own amo word
        li      s7, EPOCHW
        # hart 0 decides the epoch and publishes it in `ep`; hart 1 waits for it (the epoch word is shared)
        bnez    s0, 1f
        ld      t0, 0(s7)
        li      t1, MAGIC
        li      t2, 1
        beq     t0, t1, 0f
        li      t2, 0
        sd      t1, 0(s7)                       # first run: mark it
0:      la      t0, ep
        sd      t2, 0(t0)
        fence   rw, rw
        la      t0, ep_ready
        li      t1, 1
        sw      t1, 0(t0)
1:      WAIT_EQ(ep_ready, 1, t0)
        la      t0, ep
        ld      s8, 0(t0)                       # s8 = 1 on the second run
        beqz    s8, stream
        # ---- second run: count the survived prefix of the own region (from the FIRST run's stream)
        li      t0, 0
        mv      t1, s2
        li      t3, 0xA5
        slli    t3, t3, 56
        slli    t4, s0, 48
        or      t3, t3, t4
2:      ld      t2, 0(t1)
        or      t5, t3, t0
        bne     t2, t5, 3f
        addi    t0, t0, 1
        addi    t1, t1, 8
        li      t6, NWORDS
        bne     t0, t6, 2b
3:      la      t1, survived
        slli    t2, s0, 3
        add     t1, t1, t2
        sd      t0, 0(t1)
        fence   rw, rw
stream: # ---- the store stream: word i = pattern | i; amoadd every 16th
        li      s4, 0
        mv      s5, s2
        li      t3, 0xA5
        slli    t3, t3, 56
        slli    t4, s0, 48
        or      t3, t3, t4
4:      or      t1, t3, s4
        sd      t1, 0(s5)
        andi    t2, s4, 15
        bnez    t2, 5f
        li      t2, 1
        amoadd.d zero, t2, (s6)
5:      addi    s5, s5, 8
        addi    s4, s4, 1
        li      t6, NWORDS
        bne     s4, t6, 4b
        BARRIER(b1, NHARTS, t0)
        bnez    s0, park
        la      a0, msg_ok
        call    htif_puts
        la      t0, ep
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_sv
        call    htif_puts
        la      t0, survived
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_sp
        call    htif_puts
        la      t0, survived
        ld      a0, 8(t0)
        call    htif_puthex
        la      a0, msg_nl
        call    htif_puts
        li      a0, 0
        call    htif_exit
park:   wfi
        j       park
        .section .data
        .align 6
b1:     .word 0
        .word 0
        .align 3
ep:        .dword 0
ep_ready:  .dword 0
survived:  .dword 0, 0
msg_ok:   .asciz "M2B-DRAIN-OK epoch=0x"
msg_sv:   .asciz " survived=0x"
msg_sp:   .asciz " 0x"
msg_nl:   .asciz "\n"
