# MC-M2b common entry: every hart arrives here from the boot ROM (mret to 0x80000000 with a0 = mhartid).
# Each hart takes its own 4 KiB stack from mhartid and calls main(hartid). Nothing is zeroed here.
        .section .text.start, "ax", @progbits
        .option norvc
        .globl _start
_start:
        csrr    a0, mhartid
        la      sp, _stack_base
        addi    t0, a0, 1
        slli    t0, t0, 12
        add     sp, sp, t0
        # a default trap vector: an unexpected trap must FAIL visibly, not re-enter the ROM (whose mtvec the
        # ROM left pointing at itself, which would restart the program silently). Programs that expect traps
        # install their own handler.
        la      t0, trap_default
        csrw    mtvec, t0
        call    main
1:      j       1b
        .align 2
        .globl trap_default
trap_default:
        csrr    t0, mhartid
        slli    t0, t0, 5
        la      t1, trap_rec
        add     t1, t1, t0
        csrr    t2, mcause
        sd      t2, 0(t1)
        csrr    t2, mepc
        sd      t2, 8(t1)
        csrr    t2, mtval
        sd      t2, 16(t1)
        li      t2, 1
        sd      t2, 24(t1)
        csrr    t0, mhartid
        bnez    t0, 2f
        la      a0, trap_msg
        call    htif_puts
        li      a0, 99
        call    htif_exit
2:      j       2b
        .section .data
        .align 3
        .globl trap_rec
trap_rec: .dword 0, 0, 0, 0, 0, 0, 0, 0
trap_msg: .asciz "M2B-TRAP-FAIL unexpected trap on hart 0\n"
