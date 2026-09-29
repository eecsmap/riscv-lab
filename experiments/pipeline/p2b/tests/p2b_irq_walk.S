# PIPE-P2b: an M-level interrupt raised (after N retirements) while S-mode code with Sv39 translation loads from 12
# different 4 KiB pages right after an sfence.vma -- more pages than the TLB has entries, so data-side walks run
# through most of the block. M has MIE = 0, so the interrupt is taken in S. Independent checks: every load ran
# once with its value (the sum), exactly one M interrupt, MPP = S, mepc inside the S block. Replaces sv07's
# multicycle-state aimed injection (an interrupt while a PTE read is outstanding); the runner reports how many
# raises landed while a PTE read was on the port.
#include "sv_env.h"
#define IRQ_MMIO 0x60000000
#define VA(k) (TEST_REGION + (k) * 4096)
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   call    su_init
        li      t0, IRQ_MMIO
        la      t1, irq_mmio_clear
        sd      t0, 0(t1)
        TEST_ROOT(root0, l1_0, l0_0)
        .irp k, 1,2,3,4,5,6,7,8,9,10,11,12
        MAP4K(l0_0, \k, pg\k, PTE_RW_AD)
        la      t0, pg\k
        li      t1, \k
        sd      t1, 0(t0)
        .endr
        li      t0, IE_MSIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE | MSTATUS_MPIE
        csrc    mstatus, t0
        ENABLE_SV39(root0)
        li      s2, 0
        ENTER_S(s_blk)
s_blk:  sfence.vma
        .irp k, 1,2,3,4,5,6,7,8,9,10,11,12
        li      t0, VA(\k)
        ld      t1, 0(t0)
        add     s2, s2, t1
        .endr
s_end:  la      a6, back
        li      a7, SVC_RET_M
        la      a5, u_ecall
u_ecall: ecall
back:   DISABLE_SV39
        SPIN(50)
        CHECK_EQ(s2, 78, 1)
        LOAD_VAR(t1, m_irq_count)
        CHECK_EQ(t1, 1, 2)
        LOAD_LOG(t2, m_log, 0, LOG_CAUSE)
        bltz    t2, 5f
        LOAD_LOG(t2, m_log, 1, LOG_CAUSE)
        LOAD_LOG(t3, m_log, 1, LOG_EPC)
        LOAD_LOG(t4, m_log, 1, LOG_STATUS)
        j       6f
5:      LOAD_LOG(t3, m_log, 0, LOG_EPC)
        LOAD_LOG(t4, m_log, 0, LOG_STATUS)
6:      li      t5, (1 << 63) | IRQ_MSI
        CHECK_EQ_R(t2, t5, 3)
        srli    t4, t4, 11
        andi    t4, t4, 3
        CHECK_EQ(t4, 1, 4)                  # MPP = S
        la      t5, s_blk
        bltu    t3, t5, 92f
        la      t5, u_ecall
        bgtu    t3, t5, 92f
        PASS
92:     li      a0, 5
        call    tt_exit

        .section .data, "aw", @progbits
        .balign 4096
        .globl root0, l1_0, l0_0
root0:  .space 4096
l1_0:   .space 4096
l0_0:   .space 4096
        .irp k, 1,2,3,4,5,6,7,8,9,10,11,12
pg\k:  .space 4096
        .endr
