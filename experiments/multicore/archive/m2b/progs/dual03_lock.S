# dual03 (T3.4, C5/C6): the shared serial backend under two real harts.
#  P1 lock-protected counter: amoswap.d.aq spinlock, plain ld/addi/sd inside, 10000 per hart -> 20000
#  P2 LR/SC on ONE shared word, 10000 successful increments per hart -> 20000; failures counted per hart
#  P3 amoadd.d on one word, 10000 per hart -> 20000
#  P4 LR/SC on INDEPENDENT granules (64 B apart), 10000 per hart; no failure allowed (nobody else writes them)
#  P5 publish/acquire: hart 0 writes data, fence, flag; hart 1 waits flag, fence, reads data == f(flag); 2000 rounds
#  P6 error returns: hart 1 loads from 0x50000000 (nothing there) -> load access fault, cause 5, tval = address;
#     hart 0 stores to 0x50000008 -> store access fault, cause 7. Each hart's handler records cause/tval and
#     skips the instruction; the other hart's counters are untouched.
# Hart 0 reports every count in hex.
#include "dual.h"
#define N 10000
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   mv      s0, a0
        slli    s1, s0, 3
        la      t0, handler
        csrw    mtvec, t0
        # ---- P1
        li      s2, N
        la      s3, lock
        la      s4, counter
p1:     li      t0, 1
1:      amoswap.d.aq t1, t0, (s3)
        bnez    t1, 1b
        ld      t2, 0(s4)
        addi    t2, t2, 1
        sd      t2, 0(s4)
        amoswap.d.rl zero, zero, (s3)
        addi    s2, s2, -1
        bnez    s2, p1
        BARRIER(b1, NHARTS, t0)
        # ---- P2
        li      s2, N
        la      s3, lrsc_word
        la      s4, scfail_shared
        add     s4, s4, s1
p2:     lr.d    t0, (s3)
        addi    t0, t0, 1
        sc.d    t1, t0, (s3)
        beqz    t1, 2f
        ld      t2, 0(s4)
        addi    t2, t2, 1
        sd      t2, 0(s4)
        j       p2
2:      addi    s2, s2, -1
        bnez    s2, p2
        BARRIER(b2, NHARTS, t0)
        # ---- P3
        li      s2, N
        la      s3, amo_word
        li      t0, 1
p3:     amoadd.d zero, t0, (s3)
        addi    s2, s2, -1
        bnez    s2, p3
        BARRIER(b3, NHARTS, t0)
        # ---- P4
        li      s2, N
        la      s3, indep
        slli    t0, s0, 6
        add     s3, s3, t0                      # indep + 64*h
        la      s4, scfail_indep
        add     s4, s4, s1
p4:     lr.d    t0, (s3)
        addi    t0, t0, 1
        sc.d    t1, t0, (s3)
        beqz    t1, 3f
        ld      t2, 0(s4)
        addi    t2, t2, 1
        sd      t2, 0(s4)
        j       p4
3:      addi    s2, s2, -1
        bnez    s2, p4
        BARRIER(b4, NHARTS, t0)
        # ---- P5
        li      s2, 0
        la      s3, pub_data
        la      s4, pub_flag
        la      s5, pub_ack
        bnez    s0, p5c
p5p:    addi    s2, s2, 1                       # round r = 1..2000: data = 7r+1, then flag = r
        li      t0, 7
        mul     t0, t0, s2
        addi    t0, t0, 1
        sd      t0, 0(s3)
        fence   w, w
        sd      s2, 0(s4)
4:      ld      t1, 0(s5)
        bne     t1, s2, 4b
        li      t0, 2000
        bne     s2, t0, p5p
        j       p5end
p5c:    addi    s2, s2, 1
5:      ld      t1, 0(s4)
        bne     t1, s2, 5b
        fence   r, r
        ld      t0, 0(s3)
        li      t2, 7
        mul     t2, t2, s2
        addi    t2, t2, 1
        beq     t0, t2, 6f
        la      t3, bad_pub
        ld      t4, 0(t3)
        addi    t4, t4, 1
        sd      t4, 0(t3)
6:      fence   rw, w
        sd      s2, 0(s5)
        li      t0, 2000
        bne     s2, t0, p5c
p5end:  BARRIER(b5, NHARTS, t0)
        # ---- P6
        bnez    s0, 7f
        li      t0, 0x50000008
        sd      t0, 0(t0)                       # store access fault expected (skipped by the handler)
        j       8f
7:      li      t0, 0x50000000
        ld      t1, 0(t0)                       # load access fault expected
8:      BARRIER(b6, NHARTS, t0)
        bnez    s0, park
        # ---- hart 0: verify and report
        la      t0, counter
        ld      t1, 0(t0)
        li      t2, 2*N
        bne     t1, t2, f30
        la      t0, lrsc_word
        ld      t1, 0(t0)
        bne     t1, t2, f31
        la      t0, amo_word
        ld      t1, 0(t0)
        bne     t1, t2, f32
        la      t0, indep
        ld      t1, 0(t0)
        li      t2, N
        bne     t1, t2, f33
        ld      t1, 64(t0)
        bne     t1, t2, f33
        la      t0, scfail_indep
        ld      t1, 0(t0)
        bnez    t1, f34
        ld      t1, 8(t0)
        bnez    t1, f34
        la      t0, bad_pub
        ld      t1, 0(t0)
        bnez    t1, f35
        la      t0, err_cause
        ld      t1, 0(t0)
        li      t2, 7
        bne     t1, t2, f36
        ld      t1, 8(t0)
        li      t2, 5
        bne     t1, t2, f37
        la      t0, err_tval
        ld      t1, 0(t0)
        li      t2, 0x50000008
        bne     t1, t2, f38
        ld      t1, 8(t0)
        li      t2, 0x50000000
        bne     t1, t2, f39
        la      t0, err_n
        ld      t1, 0(t0)
        li      t2, 1
        bne     t1, t2, f40
        ld      t1, 8(t0)
        bne     t1, t2, f40
        la      a0, msg_ok
        call    htif_puts
        la      t0, counter
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_lrsc
        call    htif_puts
        la      t0, lrsc_word
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_amo
        call    htif_puts
        la      t0, amo_word
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_scf
        call    htif_puts
        la      t0, scfail_shared
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_sp
        call    htif_puts
        la      t0, scfail_shared
        ld      a0, 8(t0)
        call    htif_puthex
        la      a0, msg_nl
        call    htif_puts
        li      a0, 0
        call    htif_exit
f30: la a0, msg_fail; call htif_puts; FAIL(30)
f31: la a0, msg_fail; call htif_puts; FAIL(31)
f32: la a0, msg_fail; call htif_puts; FAIL(32)
f33: la a0, msg_fail; call htif_puts; FAIL(33)
f34: la a0, msg_fail; call htif_puts; FAIL(34)
f35: la a0, msg_fail; call htif_puts; FAIL(35)
f36: la a0, msg_fail; call htif_puts; FAIL(36)
f37: la a0, msg_fail; call htif_puts; FAIL(37)
f38: la a0, msg_fail; call htif_puts; FAIL(38)
f39: la a0, msg_fail; call htif_puts; FAIL(39)
f40: la a0, msg_fail; call htif_puts; FAIL(40)
park:   wfi
        j       park
        .align 2
handler:                                        # access faults only: record cause/tval, skip the instruction
        addi    sp, sp, -32
        sd      t0, 0(sp)
        sd      t1, 8(sp)
        sd      t2, 16(sp)
        csrr    t0, mcause
        csrr    t1, mhartid
        slli    t1, t1, 3
        la      t2, err_cause
        add     t2, t2, t1
        sd      t0, 0(t2)
        csrr    t0, mtval
        la      t2, err_tval
        add     t2, t2, t1
        sd      t0, 0(t2)
        la      t2, err_n
        add     t2, t2, t1
        ld      t0, 0(t2)
        addi    t0, t0, 1
        sd      t0, 0(t2)
        csrr    t0, mepc
        addi    t0, t0, 4
        csrw    mepc, t0
        ld      t0, 0(sp)
        ld      t1, 8(sp)
        ld      t2, 16(sp)
        addi    sp, sp, 32
        mret
        .section .data
        .align 6
lock:       .dword 0
        .align 6
counter:    .dword 0
        .align 6
lrsc_word:  .dword 0
        .align 6
amo_word:   .dword 0
        .align 6
indep:      .dword 0
        .fill 7, 8, 0
        .dword 0                                # indep + 64
        .fill 7, 8, 0
        .align 6
pub_data:   .dword 0
        .align 6
pub_flag:   .dword 0
        .align 6
pub_ack:    .dword 0
        .align 6
b1: .word 0
    .word 0
b2: .word 0
    .word 0
b3: .word 0
    .word 0
b4: .word 0
    .word 0
b5: .word 0
    .word 0
b6: .word 0
    .word 0
        .align 3
scfail_shared: .dword 0, 0
scfail_indep:  .dword 0, 0
bad_pub:       .dword 0
err_cause:     .dword 0, 0
err_tval:      .dword 0, 0
err_n:         .dword 0, 0
msg_ok:   .asciz "M2B-LOCK-OK lock=0x"
msg_lrsc: .asciz " lrsc=0x"
msg_amo:  .asciz " amo=0x"
msg_scf:  .asciz " scf_shared=0x"
msg_sp:   .asciz " 0x"
msg_nl:   .asciz "\n"
msg_fail: .asciz "M2B-LOCK-FAIL\n"
