# PIPE-P2b: an M-level interrupt raised (by the harness, at a chosen CYCLE) across a block of atomics on one watched
# memory word -- three AMOs, an LR/SC retry loop, a .W AMO on a second word -- in M-mode with interrupts enabled.
# Replaces cpu-a a04's multicycle-state aimed injection. Independent checks: every AMO's old value and the final
# memory words are exact (each atomic applied once, whatever the interrupt did), exactly one M interrupt, mepc inside
# the block or the spin after it. A trap between the LR and the SC drops the reservation (resv_clear): the SC then
# fails and the loop retries, which is correct. The runner also requires the harness's own count of writes to the
# word: exactly 5 (the initial store, three AMOs and the one successful SC), and counts the raises that land inside
# an AMO.
#include "su_env.h"
#define IRQ_MMIO 0x60000000
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   call    su_init
        li      t0, IRQ_MMIO
        la      t1, irq_mmio_clear
        sd      t0, 0(t1)
        li      t0, IE_MSIE
        csrw    mie, t0
        la      s2, slot
        li      t0, 0x1000
        sd      t0, 0(s2)
        la      s3, slotw
        li      t0, 0x7ffffff0
        sd      t0, 0(s3)
        li      a1, 0x23
        li      a7, 0x20
        csrsi   mstatus, MSTATUS_MIE
        .globl  blk
blk:    amoadd.d a2, a1, (s2)               # old 0x1000, now 0x1023
        amoadd.d a3, a1, (s2)               # old 0x1023, now 0x1046
        amoswap.d a4, a1, (s2)              # old 0x1046, now 0x23
1:      lr.d    a5, (s2)
        addi    a5, a5, 1
        sc.d    a6, a5, (s2)                # retried until it succeeds: the word ends at 0x24
        bnez    a6, 1b
        amoadd.w s4, a7, (s3)               # old 0x7ffffff0 (as a word, positive), now 0x80000010
        amoadd.w s5, a7, (s3)               # old 0x80000010: sign-extended to 0xffffffff80000010 (SPIN uses t3)
        .globl  blk_end
blk_end:
        SPIN(100)
        .globl  spin_end
spin_end:
        csrci   mstatus, MSTATUS_MIE
        CHECK_EQ(a2, 0x1000, 1)
        CHECK_EQ(a3, 0x1023, 2)
        CHECK_EQ(a4, 0x1046, 3)
        ld      t1, 0(s2)
        CHECK_EQ(t1, 0x24, 4)
        CHECK_EQ(s4, 0x7ffffff0, 5)
        li      t4, 0xffffffff80000010
        CHECK_EQ_R(s5, t4, 6)
        lw      t1, 0(s3)
        li      t4, 0xffffffff80000030
        CHECK_EQ_R(t1, t4, 7)
        LOAD_VAR(t1, m_irq_count)
        CHECK_EQ(t1, 1, 8)
        LOAD_LOG(t2, m_log, 0, LOG_CAUSE)
        li      t5, (1 << 63) | IRQ_MSI
        CHECK_EQ_R(t2, t5, 9)
        LOAD_LOG(t3, m_log, 0, LOG_EPC)
        la      t5, blk
        bltu    t3, t5, 92f
        la      t5, spin_end
        bgtu    t3, t5, 92f
        PASS
92:     li      a0, 10
        call    tt_exit

        .section .data, "aw", @progbits
        .balign 8
        .globl  slot, slotw
slot:   .dword  0
slotw:  .dword  0
