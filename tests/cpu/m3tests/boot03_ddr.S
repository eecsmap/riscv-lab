# M3-c: real DRAM through the real AXI path, with every access width the port supports and every byte
# alignment. The point is the byte lanes: a narrow access has to reach exactly the bytes it names and leave
# the rest alone, all the way out to the memory and back.
#include "m3lib.h"
        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top
        la      s0, buf
        # ---- 64-bit round trip
        li      t0, 0x0123456789abcdef
        sd      t0, 0(s0)
        ld      t1, 0(s0)
        CHECK_EQ_R(t1, t0, 1)
        # ---- 32-bit halves, and the sign behaviour of lw against lwu
        lw      t1, 0(s0)
        li      t2, 0xffffffff89abcdef
        CHECK_EQ_R(t1, t2, 2)
        lwu     t1, 0(s0)
        li      t2, 0x89abcdef
        CHECK_EQ_R(t1, t2, 3)
        lw      t1, 4(s0)
        li      t2, 0x01234567
        CHECK_EQ_R(t1, t2, 4)
        # ---- write one 32-bit half and leave the other untouched
        li      t0, 0x11112222
        sw      t0, 0(s0)
        ld      t1, 0(s0)
        li      t2, 0x0123456711112222
        CHECK_EQ_R(t1, t2, 5)
        # ---- halfwords at every 2-byte offset
        li      t0, 0x0123456789abcdef
        sd      t0, 0(s0)
        li      t0, 0xbeef
        sh      t0, 2(s0)
        ld      t1, 0(s0)
        li      t2, 0x01234567beefcdef
        CHECK_EQ_R(t1, t2, 6)
        lhu     t1, 2(s0)
        li      t2, 0xbeef
        CHECK_EQ_R(t1, t2, 7)
        lh      t1, 2(s0)
        li      t2, 0xffffffffffffbeef
        CHECK_EQ_R(t1, t2, 8)
        # ---- a byte at each of the eight lanes, checked one at a time
        li      t0, 0x0123456789abcdef
        sd      t0, 0(s0)
        li      s1, 0
        li      s2, 8
1:      add     t0, s0, s1
        li      t1, 0x5a
        sb      t1, 0(t0)
        lbu     t2, 0(t0)
        CHECK_EQ(t2, 0x5a, 9)
        addi    s1, s1, 1
        blt     s1, s2, 1b
        ld      t1, 0(s0)
        li      t2, 0x5a5a5a5a5a5a5a5a
        CHECK_EQ_R(t1, t2, 10)
        # ---- sign extension of lb
        li      t0, 0x80
        sb      t0, 0(s0)
        lb      t1, 0(s0)
        li      t2, 0xffffffffffffff80
        CHECK_EQ_R(t1, t2, 11)
        lbu     t1, 0(s0)
        CHECK_EQ(t1, 0x80, 12)
        # ---- a walk across a wider region, so the AXI path sees more than one address
        la      s0, buf
        li      s1, 0
        li      s2, 64
2:      slli    t0, s1, 3
        add     t0, s0, t0
        add     t1, s1, s1
        addi    t1, t1, 7
        sd      t1, 0(t0)
        addi    s1, s1, 1
        blt     s1, s2, 2b
        li      s1, 0
3:      slli    t0, s1, 3
        add     t0, s0, t0
        ld      t1, 0(t0)
        add     t2, s1, s1
        addi    t2, t2, 7
        CHECK_EQ_R(t1, t2, 13)
        addi    s1, s1, 1
        blt     s1, s2, 3b
        la      a0, okmsg
        call    htif_puts
        li      a0, 0
        call    htif_exit
        .section .rodata, "a", @progbits
okmsg:  .asciz "M3-DDR-OK\n"
        .section .data, "aw", @progbits
        .align 3
buf:    .space 1024
