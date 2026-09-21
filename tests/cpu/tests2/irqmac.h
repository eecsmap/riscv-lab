// Shared definitions for the M2-3 interrupt tests.
#define IRQ_MMIO   0x60000000        // the harness' test interrupt controller: write 1s to quiet sources
#define IRQ_ARM    0x60000008        // arm the injector: the next chosen moment raises the line
#define MIE_MSIE   (1 << 3)
#define MIE_MTIE   (1 << 7)
#define MIE_MEIE   (1 << 11)
#define MSTATUS_MIE (1 << 3)
#define CAUSE_MSI  3
#define CAUSE_MTI  7
#define CAUSE_MEI  11

// WAIT_IRQ(n, code): spin until the handler has counted n interrupts, with a bound so a core that never
// accepts one fails the test rather than hanging the simulation.
#define WAIT_IRQ(n, code, c0, c1, c2)   \
        li   c2, 200000;                \
        la   c0, irq_count;             \
71:     ld   c1, 0(c0);                 \
        li   t3, n;                     \
        bge  c1, t3, 72f;               \
        addi c2, c2, -1;                \
        bnez c2, 71b;                   \
        FAIL_CODE(code, c0);            \
72:
