# dual02 (T3.3): per-hart timer and software interrupts on the real CLINT. Each hart arms its OWN mtimecmp and
# counts its OWN mtip traps (5 each, re-armed from the handler); then hart 0 sends an IPI to hart 1 by writing
# msip[1]; hart 1's handler counts it and clears it. While hart 1 busy-waits for the IPI, hart 0 keeps running
# (a counted loop) -- both harts progress. Hart 0 checks: msip count 0 on itself, 1 on hart 1; >= 5 timer
# traps on each; no unexpected cause on either; hart 1 progressed while waiting.
#include "dual.h"
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   mv      s0, a0
        slli    s1, s0, 3                       # s1 = 8*h
        la      t0, handler
        csrw    mtvec, t0
        # arm: mtimecmp[h] = mtime + 300
        li      t1, CLINT_MTIME
        ld      t2, 0(t1)
        addi    t2, t2, 300
        li      t3, CLINT_MTIMECMP
        add     t3, t3, s1
        sd      t2, 0(t3)
        li      t0, MIE_MTIE | MIE_MSIE
        csrw    mie, t0
        li      t0, MSTATUS_MIE
        csrs    mstatus, t0
        la      t4, mtip_cnt
        add     t4, t4, s1
1:      ld      t0, 0(t4)
        li      t1, 5
        blt     t0, t1, 1b
        BARRIER(phase1, NHARTS, t0)
        bnez    s0, hart1
        # ---- hart 0: busy work while hart 1 waits for the IPI, then send it
        la      t4, prog
        li      t5, 3000
2:      ld      t0, 0(t4)
        addi    t0, t0, 1
        sd      t0, 0(t4)
        addi    t5, t5, -1
        bnez    t5, 2b
        li      t0, CLINT_MSIP + 4
        li      t1, 1
        sw      t1, 0(t0)                       # IPI to hart 1
        WAIT_EQ(done1, 1, t0)
        # ---- checks
        la      t0, msip_cnt
        ld      t1, 0(t0)
        bnez    t1, f20                         # hart 0 must not have seen a software interrupt
        ld      t1, 8(t0)
        li      t2, 1
        bne     t1, t2, f21                     # exactly one on hart 1
        la      t0, mtip_cnt
        ld      t1, 0(t0)
        li      t2, 5
        blt     t1, t2, f22
        ld      t1, 8(t0)
        blt     t1, t2, f23
        la      t0, bad_cause
        ld      t1, 0(t0)
        bnez    t1, f24
        ld      t1, 8(t0)
        bnez    t1, f25
        la      t0, prog
        ld      t1, 8(t0)
        beqz    t1, f26                         # hart 1 made progress while it waited
        la      a0, msg_ok
        call    htif_puts
        la      t0, mtip_cnt
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_sp
        call    htif_puts
        la      t0, mtip_cnt
        ld      a0, 8(t0)
        call    htif_puthex
        la      a0, msg_sp
        call    htif_puts
        la      t0, prog
        ld      a0, 8(t0)
        call    htif_puthex
        la      a0, msg_nl
        call    htif_puts
        li      a0, 0
        call    htif_exit
f20:    la a0, msg_fail; call htif_puts; FAIL(20)
f21:    la a0, msg_fail; call htif_puts; FAIL(21)
f22:    la a0, msg_fail; call htif_puts; FAIL(22)
f23:    la a0, msg_fail; call htif_puts; FAIL(23)
f24:    la a0, msg_fail; call htif_puts; FAIL(24)
f25:    la a0, msg_fail; call htif_puts; FAIL(25)
f26:    la a0, msg_fail; call htif_puts; FAIL(26)
hart1:  # busy-wait for the IPI, counting progress; the handler bumps msip_cnt[1]
        la      t4, prog
        addi    t4, t4, 8
        la      t5, msip_cnt
        addi    t5, t5, 8
3:      ld      t0, 0(t4)
        addi    t0, t0, 1
        sd      t0, 0(t4)
        ld      t1, 0(t5)
        beqz    t1, 3b
        fence   rw, rw
        la      t0, done1
        li      t1, 1
        sw      t1, 0(t0)
park:   wfi
        j       park
        # ---- the trap handler, shared text, per-hart state indexed by mhartid; saves what it uses on the
        # hart's own stack
        .align 2
handler:
        addi    sp, sp, -48
        sd      t0, 0(sp)
        sd      t1, 8(sp)
        sd      t2, 16(sp)
        sd      t3, 24(sp)
        sd      t4, 32(sp)
        csrr    t0, mcause
        csrr    t1, mhartid
        slli    t1, t1, 3
        li      t2, 0x8000000000000007
        beq     t0, t2, h_mtip
        li      t2, 0x8000000000000003
        beq     t0, t2, h_msip
        la      t3, bad_cause
        add     t3, t3, t1
        sd      t0, 0(t3)
        j       h_out
h_mtip: la      t3, mtip_cnt
        add     t3, t3, t1
        ld      t4, 0(t3)
        addi    t4, t4, 1
        sd      t4, 0(t3)
        li      t2, CLINT_MTIME
        ld      t2, 0(t2)
        addi    t2, t2, 300
        li      t3, 5
        blt     t4, t3, 4f
        li      t2, -1                          # done counting: park the comparator
4:      li      t3, CLINT_MTIMECMP
        add     t3, t3, t1
        sd      t2, 0(t3)
        j       h_out
h_msip: la      t3, msip_cnt
        add     t3, t3, t1
        ld      t4, 0(t3)
        addi    t4, t4, 1
        sd      t4, 0(t3)
        li      t3, CLINT_MSIP
        srli    t2, t1, 1                       # 4*h
        add     t3, t3, t2
        sw      zero, 0(t3)                     # clear own msip
h_out:  ld      t0, 0(sp)
        ld      t1, 8(sp)
        ld      t2, 16(sp)
        ld      t3, 24(sp)
        ld      t4, 32(sp)
        addi    sp, sp, 48
        mret
        .section .data
        .align 3
phase1:     .word 0
            .word 0
done1:      .dword 0
mtip_cnt:   .dword 0, 0
msip_cnt:   .dword 0, 0
bad_cause:  .dword 0, 0
prog:       .dword 0, 0
msg_ok:     .asciz "M2B-CLINT-OK mtip0=0x"
msg_sp:     .asciz " 0x"
msg_nl:     .asciz "\n"
msg_fail:   .asciz "M2B-CLINT-FAIL\n"
