# Directed-test startup: deliberately does NO data access before main, so "data requests that reached the
# bus" is a clean measurement of what the instruction under test did.
        .section .text.start, "ax", @progbits
        .globl _start
_start: la      sp, _stack_top
        call    main
3:      j       3b
        .globl  tt_exit
tt_exit: slli   a0, a0, 1
        ori     a0, a0, 1
        la      t0, tohost
        sd      a0, 0(t0)
4:      j       4b
        .section .htif, "aw", @progbits
        .align 6
        .globl tohost
tohost: .dword 0
        .align 6
        .globl fromhost
fromhost: .dword 0
