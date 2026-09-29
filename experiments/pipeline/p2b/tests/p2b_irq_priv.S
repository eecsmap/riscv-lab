# PIPE-P2b: an M-level software interrupt raised (by the harness, after N retirements) while the hart moves
# M -> S -> U -> M. M runs with MIE = 0, so the interrupt can only be taken once the hart is below M (below M an
# M-level interrupt is always enabled): the xRET that lowers the privilege is where a pending line becomes takeable.
# Independent checks: every block instruction ran exactly once (the counter), exactly one M interrupt, taken with
# MPP = S or U, mepc inside the S or U block, mcause = MSI. Replaces the multicycle-state aimed injection of su12.
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
        li      t0, MSTATUS_MIE | MSTATUS_MPIE
        csrc    mstatus, t0
        li      s2, 0
        .rept 8
        addi    s2, s2, 1                   # M, interrupts not takeable here
        .endr
        ENTER_S(s_blk)
s_blk:  .rept 16
        addi    s2, s2, 1                   # S
        .endr
        ENTER_U_S(u_blk)
u_blk:  .rept 16
        addi    s2, s2, 1                   # U
        .endr
        la      a6, back                    # RET_M(back), spelled out so its ECALL has a label: U ends there
        li      a7, SVC_RET_M
        la      a5, u_end
u_end:  ecall
back:   SPIN(50)
        CHECK_EQ(s2, 40, 1)
        LOAD_VAR(t1, m_irq_count)
        CHECK_EQ(t1, 1, 2)
        # the M log holds the interrupt and the final ecall; find the interrupt entry (cause bit 63 set)
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
        srli    t4, t4, 11                  # MPP of the interrupt: S (1) or U (0), never M (MIE = 0 there)
        andi    t4, t4, 3
        li      t5, 3
        CHECK_NE_R(t4, t5, 4)
        la      t5, s_blk                   # mepc inside the S or U block
        bltu    t3, t5, 92f
        la      t5, u_end
        bgtu    t3, t5, 92f
        PASS
92:     li      a0, 5
        call    tt_exit
