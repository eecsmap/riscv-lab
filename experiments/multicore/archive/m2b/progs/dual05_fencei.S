# dual05 (T3.6, C10): cross-hart code modification. X (in .codebuf, its own 64-byte-aligned line) starts as
# `li a0,1; ret`. Hart 1 calls X four times first (the I-cache is warm: the trace shows one line fill, then no
# fetch of X). Hart 0 then writes `li a0,2` over the first word, fences, and raises a flag. Hart 1 (a) calls X
# WITHOUT fence.i and records the result -- an experiment on this implementation, reported as observed --
# then (b) executes fence.i and calls X: this one MUST return 2 (the new code), which is the ISA's promise.
#include "dual.h"
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   mv      s0, a0
        bnez    s0, hart1
        # ---- hart 0
        WAIT_EQ(warm, 1, t0)
        la      t0, X
        li      t1, 0x00200513                  # addi a0, zero, 2
        sw      t1, 0(t0)
        fence   rw, rw
        la      t0, flag
        li      t1, 1
        sw      t1, 0(t0)
        WAIT_EQ(done, 1, t0)
        la      t0, r_fence
        ld      t1, 0(t0)
        li      t2, 2
        bne     t1, t2, f60
        la      a0, msg_ok
        call    htif_puts
        la      t0, r_nofence
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_f
        call    htif_puts
        la      t0, r_fence
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_nl
        call    htif_puts
        li      a0, 0
        call    htif_exit
f60:    la a0, msg_fail; call htif_puts; FAIL(60)
hart1:  la      s2, X
        li      s3, 4
1:      jalr    ra, 0(s2)                       # warm the I-cache with the OLD code
        la      t0, warm_sum
        ld      t1, 0(t0)
        add     t1, t1, a0
        sd      t1, 0(t0)
        addi    s3, s3, -1
        bnez    s3, 1b
        fence   rw, rw
        la      t0, warm
        li      t1, 1
        sw      t1, 0(t0)
        WAIT_EQ(flag, 1, t0)
        jalr    ra, 0(s2)                       # (a) no fence.i: whatever this implementation does
        la      t0, r_nofence
        sd      a0, 0(t0)
        fence.i
        jalr    ra, 0(s2)                       # (b) after fence.i: must be the new code
        la      t0, r_fence
        sd      a0, 0(t0)
        fence   rw, rw
        la      t0, done
        li      t1, 1
        sw      t1, 0(t0)
park:   wfi
        j       park
        .section .codebuf, "awx", @progbits
        .align 6
        .globl X
X:      addi    a0, zero, 1
        ret
        .fill 14, 4, 0x00000013                 # nops to the end of the 64-byte line
        .section .data
        .align 3
warm:      .dword 0
flag:      .dword 0
done:      .dword 0
warm_sum:  .dword 0
r_nofence: .dword 0
r_fence:   .dword 0
msg_ok:   .asciz "M2B-FENCEI-OK nofence=0x"
msg_f:    .asciz " fence=0x"
msg_nl:   .asciz "\n"
msg_fail: .asciz "M2B-FENCEI-FAIL\n"
