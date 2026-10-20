# MCU-0 crt0: stack, zero bss, call main. main never returns; if it does, spin.
        .section .text.start, "ax", @progbits
        .globl _start
_start: la      sp, _stack_top
        la      t0, _bss_start
        la      t1, _bss_end
1:      bgeu    t0, t1, 2f
        sd      zero, 0(t0)
        addi    t0, t0, 8
        j       1b
2:      call    main
3:      j       3b
        # the tools expect a tohost word in every image; this program never writes it
        .section .htif, "aw", @progbits
        .align 6
        .globl tohost
tohost: .dword 0
