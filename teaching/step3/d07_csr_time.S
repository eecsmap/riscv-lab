# d07 (step-3 edition): a CSR this core does not implement must be an illegal instruction, never a fabricated
# value. The original d07 used `cycle`, which the core has implemented since CPU-SU; `time` (0xC01) is the
# counter it still does not have -- there is no timer inside the core, mtime lives in the CLINT.
#include "testmac.h"
        .section .text, "ax", @progbits
        .globl main
main:   li      s1, 0x5A5A5A5A
        .option push
        .option norvc
        csrr    s1, time
        .option pop
        FAIL_CODE(38, s1)
