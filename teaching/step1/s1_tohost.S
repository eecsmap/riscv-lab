# Step 1: the first instructions to retire. Only addi, auipc, sd and jal appear here, because that is all
# a step-1 core implements. The assembler is told -march=rv64i, so anything else is refused at build time.
#
# The program computes 2 + 3 - 5 + 1 = 1 and stores it to tohost. The harness ends the run when tohost
# becomes non-zero and reads it as (code << 1) | 1: the value 1 is code 0, PASS. If addi is wrong the value
# is something else and the testbench prints the code it decoded -- the arithmetic is the test.
#
# Addresses are formed with auipc + addi, never lui: the image lives at 0x8000_0000, and lui would
# sign-extend that to 0xFFFF_FFFF_8000_0000, which a correct core must refuse as an address (d01 later).
        .section .text.start, "ax", @progbits
        .globl _start
_start:
        addi    a0, zero, 2
        addi    a0, a0, 3
        addi    a0, a0, -5
        addi    a0, a0, 1               # a0 = 1: (code 0 << 1) | 1
1:      auipc   t0, %pcrel_hi(tohost)
        addi    t0, t0, %pcrel_lo(1b)
        sd      a0, 0(t0)
2:      jal     zero, 2b                # the run is over; spin until the testbench stops the clock

        .section .htif, "aw", @progbits
        .align 6
        .globl tohost
tohost: .dword 0
        .align 6
        .globl fromhost
fromhost: .dword 0
