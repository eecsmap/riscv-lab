// MC-M2b shared macros. Only hart 0 talks to the host (tohost is a single word; two writers would race).
#define CLINT_MSIP      0x02000000
#define CLINT_MTIMECMP  0x02004000
#define CLINT_MTIME     0x0200bff8
#define PLIC_BASE       0x0c000000
#define MIE_MSIE  (1 << 3)
#define MIE_MTIE  (1 << 7)
#define MSTATUS_MIE (1 << 3)
#define NHARTS 2
// FAIL(code): hart 0 only -- report code and exit
#define FAIL(code)  li a0, code; call htif_exit
// spin until the word at `sym` equals `val` (acquire: fence after the load)
#define WAIT_EQ(sym, val, tmp)  \
9:      lw   tmp, sym; li a7, val; bne tmp, a7, 9b; fence r, rw
// arrive at a barrier word: amoadd.w +1 then wait until it reads `n`
#define BARRIER(sym, n, tmp)  \
        la   tmp, sym; li a7, 1; amoadd.w.aqrl a7, a7, (tmp); \
8:      lw   a7, 0(tmp); li a6, n; bne a7, a6, 8b; fence rw, rw
