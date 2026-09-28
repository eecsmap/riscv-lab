# The interrupt arrives while the front end has nothing to give ID: the program jumps to code far away (every
# of it a cold I-cache miss) and the line is raised during that walk. Same independent checks as irq_basic.
#include "p1mac.h"
        .option norvc
        .text
        .globl main
main:
        li      t0, 8
        csrw    mie, t0
        csrsi   mstatus, 8
        li      a1, 0
        j       far_code
        .space  4096
far_code:
        .rept 8
        addi    a1, a1, 1
        j       1f
        .space  64
1:
        .endr
        li      t1, 200
2:      addi    t1, t1, -1
        bnez    t1, 2b
        csrci   mstatus, 8
        CHECK_EQ(a1, 8, 1)
        la      t0, irq_n
        ld      t0, 0(t0)
        CHECK_EQ(t0, 1, 2)
        LOG_ENTRY(0)
        li      gp, MSIP_CAUSE
        CHECK_REG(t4, gp, 3)
        li      a0, 0
        ret
