# dual07 (T3.7 long-run progress): each hart runs an independent stream of >= 1,000,000 instructions -- a loop
# of 11 instructions (ALU, a load and a store to its own array, an amoadd on its own word every 64th
# iteration), 100,000 iterations -- then barrier; hart 0 reports both iteration counts. The retired-instruction
# evidence is the harness's per-hart counter (HARTS retired0/retired1), not this marker.
#include "dual.h"
#define ITER 100000
        .section .text, "ax", @progbits
        .option norvc
        .globl main
main:   mv      s0, a0
        slli    s1, s0, 12
        la      s2, arr
        add     s2, s2, s1                      # own 4 KiB array
        la      s3, own_amo
        slli    t0, s0, 6
        add     s3, s3, t0                      # own amo word (64 B apart)
        li      s4, ITER
        li      s5, 0                           # checksum
loop:   andi    t0, s4, 511
        slli    t0, t0, 3
        add     t1, s2, t0                      # &arr[h][i mod 512]
        ld      t2, 0(t1)
        add     t2, t2, s4
        xor     t2, t2, s5
        sd      t2, 0(t1)
        add     s5, s5, t2
        andi    t3, s4, 63
        bnez    t3, 1f
        amoadd.d zero, s4, (s3)
1:      addi    s4, s4, -1
        bnez    s4, loop
        la      t0, done_iter
        slli    t1, s0, 3
        add     t0, t0, t1
        li      t2, ITER
        sd      t2, 0(t0)
        la      t0, sum
        add     t0, t0, t1
        sd      s5, 0(t0)
        fence   rw, rw
        BARRIER(b1, NHARTS, t0)
        bnez    s0, park
        la      a0, msg_ok
        call    htif_puts
        la      t0, done_iter
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_sp
        call    htif_puts
        la      t0, done_iter
        ld      a0, 8(t0)
        call    htif_puthex
        la      a0, msg_sum
        call    htif_puts
        la      t0, sum
        ld      a0, 0(t0)
        call    htif_puthex
        la      a0, msg_sp
        call    htif_puts
        la      t0, sum
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
        .align 6
own_amo: .dword 0
        .fill 7, 8, 0
        .dword 0
        .fill 7, 8, 0
        .align 3
done_iter: .dword 0, 0
sum:       .dword 0, 0
        .align 12
arr:    .fill 1024, 8, 0
msg_ok:  .asciz "M2B-LONG-OK iter=0x"
msg_sp:  .asciz " 0x"
msg_sum: .asciz " sum=0x"
msg_nl:  .asciz "\n"
