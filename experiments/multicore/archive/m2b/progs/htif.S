# HTIF console and exit, shared by the M3 programs. tohost = device<<56 | command<<48 | payload;
# the host writes 0 back once it has taken the command (fesvr htif.cc). Console is device 1 command 1;
# exit is device 0 command 0 with payload (code<<1)|1.
        .section .text, "ax", @progbits
        .option norvc
        .globl htif_putc
htif_putc:
        la      t0, tohost
1:      ld      t1, 0(t0)
        bnez    t1, 1b
        li      t1, 1
        slli    t2, t1, 56
        slli    t3, t1, 48
        or      t2, t2, t3
        or      t2, t2, a0
        sd      t2, 0(t0)
        ret
        .globl htif_puts
htif_puts:
        mv      s10, a0
        mv      s11, ra
1:      lbu     a0, 0(s10)
        beqz    a0, 2f
        call    htif_putc
        addi    s10, s10, 1
        j       1b
2:      mv      ra, s11
        ret
        .globl htif_exit
htif_exit:
        la      t0, tohost
1:      ld      t1, 0(t0)
        bnez    t1, 1b
        slli    t1, a0, 1
        ori     t1, t1, 1
        .globl exit_store
exit_store:
        sd      t1, 0(t0)
2:      j       2b
        .section .htif, "aw", @progbits
        .align 6
        .globl tohost
tohost: .dword 0
        .align 6
        .globl fromhost
fromhost: .dword 0
# ---- MC-M2b additions: hex printing (hart 0 only, like everything else here)
        .section .text, "ax", @progbits
        .option norvc
        .globl htif_puthex
htif_puthex:                    # a0 = 64-bit value, printed as 16 hex digits
        mv      s8, a0
        mv      s9, ra
        li      s7, 60
1:      srl     a0, s8, s7
        andi    a0, a0, 15
        li      t4, 10
        blt     a0, t4, 2f
        addi    a0, a0, 39
2:      addi    a0, a0, 48
        call    htif_putc
        addi    s7, s7, -4
        bgez    s7, 1b
        mv      ra, s9
        ret
