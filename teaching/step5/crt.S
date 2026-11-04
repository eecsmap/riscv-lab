# Step 5 start code for C programs: stack, zero bss, call main, report main's return value as the exit code.
# The boot ROM jumps here (0x8000_0000) with mret once the host has loaded the program and woken the core.
        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start: la      sp, _stack_top
        la      t0, _bss_start
        la      t1, _bss_end
1:      bgeu    t0, t1, 2f
        sd      zero, 0(t0)
        addi    t0, t0, 8
        j       1b
2:      call    main
        call    htif_exit               # a0 = main's return value; never returns
