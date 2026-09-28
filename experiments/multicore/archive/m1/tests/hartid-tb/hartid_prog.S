# MC-M1 T1.1: read mhartid and park it where the testbench can see it.
#   mem[0x3008..0x300f] <- mhartid (64-bit)
#   mem[0x3000..0x3003] <- 0x600d  (the sentinel that says "the store above landed")
        .section .text
        .globl  _start
_start:
        csrr    t0, mhartid
        li      t1, 0x3008
        sd      t0, 0(t1)
        li      t2, 0x600d
        li      t1, 0x3000
        sw      t2, 0(t1)
1:      j       1b
