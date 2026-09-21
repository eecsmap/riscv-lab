# M2-2: M-mode CSRs, synchronous exceptions and MRET

Delegation: `codex-m2-2-csr-traps`. Accepted run: `run-c`. Independent re-derivation: `src/check-m2-2.py`.
M2-1 stays where it is: `../m2/run-f` and `../m2/src` are untouched, and the whole M2-1 gate is re-run here.

## What changed in the core

A trap used to halt the machine. It now saves context and vectors to `mtvec`, and `MRET` returns. The core
gained a CSR file (`src/rtl/tcpu_csr.v`), the six Zicsr forms, `ECALL`/`EBREAK`, and the two counters that
really exist here.

### The CSR set, and what each one actually is

| CSR | behaviour |
|---|---|
| `mhartid` | read-only 0; a write is an illegal instruction |
| `misa` | fixed WARL: MXL = 2, the I bit and nothing else; a write is accepted and discarded, not trapped |
| `mstatus` | only MIE and MPIE are writable; MPP is hardwired to M; every other field reads 0 |
| `mtvec` | direct mode only: the low two bits are forced to 0, the 64-bit base is kept whole |
| `mepc` | low two bits forced to 0, on a trap and on a software write alike (no C extension here) |
| `mcause` `mtval` `mscratch` | readable and writable, full 64 bits |
| `mcycle` | a real counter: +1 every cycle out of reset, including cycles spent waiting on memory or taking a trap |
| `minstret` | +1 per normal retirement only |
| `cycle` `instret` | read-only aliases of the two above; a write is an illegal instruction |

Anything else is unimplemented: it traps rather than reading as zero. `mie`/`mip`, delegation, PMP and the
S-level CSRs are absent, so this does not yet cover everything a real BootROM touches.

Both counters are writable, and a software write wins over the automatic increment in the same cycle. A CSR
read returns the value *before* the instruction's own effect, which is why `csrr rd, minstret` does not see
its own retirement.

### Write intent is decided by the encoding

`CSRRW`/`CSRRWI` always write, and read only when `rd != x0`. `CSRRS`/`CSRRC` write only when the encoded
source is non-zero — that is the register *number*, so `csrrs t1, cycle, s0` with `s0 = 0` is still a write
and still traps on a read-only CSR, while `csrrs t1, mhartid, x0` is a pure read and must not. Address,
permission and write intent are all settled before any side effect.

### Timing, stated exactly

A CSR access happens entirely inside `S_WB`. The read is combinational in that cycle; the value written and
the destination-register value both derive from that same read, and both land on the next edge, together with
the retirement. That is what makes a read-modify-write atomic while `mcycle` is ticking underneath it.

To be unambiguous about what "together" means here, since the review asked for it: the CSR write enable and
the register-file write enable are both registered in `S_WB` and therefore take effect on the *following*
edge. "Atomic" is a claim about the values, not about the cycle in which they are scheduled -- the write
value and the destination value come from one and the same combinational read, so no increment of `mcycle`
can slip between them. This is a multi-cycle core's private arrangement and not a general pipelined commit
interface; when interrupts arrive, the boundary between an architectural update and its observation has to
be re-established rather than inherited from here. The
harness reads the real CSR registers through a debug port after that edge — `mepc`, `mcause` and `mtval` are
checked against the hardware registers, not against a copy of the `trap_*` outputs.

### Exception set and priority

Causes 0, 1, 2, 3, 4, 5, 6, 7 and 11. Fixed order when several could apply: an illegal encoding is decided
first, before anything derived from it; a data misalignment outranks a high physical address; a bus `error`
can only be reported once the response has come back. A branch that is not taken never has its target
checked. On entry the core writes `mepc`/`mcause`/`mtval`, sets MPIE from MIE, clears MIE, keeps MPP at M and
jumps to `mtvec`. The faulting instruction writes no register and does not retire; `commit_valid` and
`trap_valid` are never high together. `MRET` retires normally, restores MIE from MPIE, sets MPIE, and takes
its target from `mepc` — if that target then fails to fetch, the fault belongs to the target.

## Results (`run-c`, `M2_2_DONE fails=0`, checker 0 findings)

### t04_trap now does what its name says

It was a "declared scope" case in M2-1, passing only because the core stopped at the first CSR write. It now
runs to a real pass on all three timing profiles, entering the handler four times — causes 2, 4, 6 and 11 —
with the program itself verifying that `mepc` is the faulting instruction's address each time, and returning
through `MRET`. The checker requires all four causes to appear.

### The M2-1 gate, carried forward

Twelve positive runs, four programs across three timing profiles, all exit 0, no protocol error, no
observation error, `req == resp`, and the full pc/insn/rd/value commit records identical across profiles:
84 / 75 / 94 / 79 for t01/t02/t03/t05. Cycle counts still differ (742 / 1432 / 1309 for t03_ldst), so the
profiles are genuinely different. ROI unchanged: 49 static PCs matched, `roi_measured` = 49.

### The new semantics

| case | what it establishes |
|---|---|
| `csr-forms` | all six Zicsr forms, including that `csrrs` with a zero-valued register still writes and `csrrsi ..., 0` does not |
| `csr-warl` | `misa` = 0x8000000000000100 and `mstatus` = 0x1800 read back from the hardware, plus mtvec/mepc low-bit forcing |
| `csr-illegal` | six illegal CSR accesses (writes to `cycle`/`instret`/`mhartid`, a zero-set that is still a write, two unimplemented addresses) and four reads that must *not* trap |
| `counters` | `mcycle` advances and is writable with the write winning; `minstret` exact over a static sequence, writable, and counting from the written value |
| `trap-not-retired` | taking a trap moves `minstret` by exactly 4 over a span whose three handler instructions are named |
| `mret-counted` | `MRET` is counted, the faulting word is not — the latter checked externally, by PC |
| `ecall-ebreak` | causes 11 and 3, `mtval` 0 and the instruction's own address, and neither retires (external, by PC) |
| `access-faults` | causes 5, 7 and 1, each from a real `error` response to an issued request, not from a range check |
| `jump-targets` | a taken misaligned target gives cause 0 with `mtval` = the target; an untaken branch with a bad target does not trap |
| `handler-fault` | a handler that faults on entry is rejected on the trap-storm diagnostic and cannot reach a pass |

"Does not retire" is established from outside the program, by counting commits at that PC — a program cannot
observe its own non-retirement. The addresses come from the symbol table, not from parsing disassembly text.

### Fault injection: five, each rejected by a named check

| injection | program | exit | what caught it |
|---|---|---|---|
| `mepc` records the next instruction | t04_trap | 90 | the handler's own `mepc` comparison |
| taking a trap bumps `minstret` | c10 | 1 | c10 check 1: the span moved by 5 instead of 4 |
| writes to read-only CSRs let through | c03 | 1 | c03 check 1: the write to `cycle` did not trap |
| x0 becomes writable | t01_alu | 1 | `CHECK_X0_ZERO` |
| loads stop sign-extending | t03_ldst | 3 | t03 check 3 |

None is rejected by a timeout. Four controls show the blast radius is narrow: the same faulty cores still
pass programs that do not exercise the broken behaviour. The x0 fault is the exception and is required to
fail everywhere, for the reason recorded in `../m2/run-a/SUPERSEDED.md`.

### The driver no longer swallows a mistyped switch

Every option is on a whitelist and every value is fully consumed. Fourteen classes of bad input each stop the
run before the first cycle with exit 3: unknown option, misspelt option, trailing characters, overflow,
out-of-range value, missing value, missing `+elf`, unreadable ELF, unreadable expectation file, unwritable
output, malformed `+roi`, `+roi-expect` without a window, a non-option argument, and a value given to a
valueless switch. The first of those is the one Codex hit during the M2-1 review, where `+commit-out` was
silently ignored and the run still exited 0.

## Two M2-1 cases replaced, and why

- **`scope-t04`** asserted that t04 stops at the first CSR write because M-mode was not implemented. That
  premise is gone; t04 now runs its handler and passes, on all three profiles.
- **`csr-cycle-illegal`** asserted that reading `cycle` is illegal. That was right when `cycle` was a
  fabricated zero. `mcycle` is now a real counter and `cycle` is its read-only alias, so *reading* it is
  legal and *writing* it is not. `csr-illegal` covers the write, and also covers four reads that must not
  trap, which the old case could not distinguish.

Everything else from M2-1 is re-run unchanged: the JALR funct3 set, the read-payload monitor and its leak
injection, the tail-completion controls, the protocol-monitor self-tests, and the four directed boundary
tests. `tail-error` now runs with `+stop-at-trap` so its stated reason is the store access fault rather than
a downstream timeout — see `run-a/SUPERSEDED.md`.

## Evidence

    run-c/   the accepted run: logs, per-case exit files, commit records, ELFs, disassembly, symbols, hashes
    run-a/   superseded, with SUPERSEDED.md
    src/     sources, tests and both scripts, with SRC.sha256

`check-m2-2.py` reports 0 findings on `run-c` and 204 on `../m2/run-f`, which is what makes the new checks
worth anything: every M2-2 case is absent there and the older logs cannot even report a trap.

Identity chain: `src/SRC.sha256` -> `run-c/source.sha256` (verified equal) -> `run-c/sim.sha256` (thirteen
simulator binaries and their generated C++) -> `run-c/elf.sha256` -> `run-c/commits.sha256`.
`run-c/tools.txt` records Verilator 5.022, riscv64 gcc 13.2.0 and the host compiler.

    teaching-cpu-work/cpu/run-m2-2.sh <newdir>
    teaching-cpu-work/cpu/check-m2-2.py <newdir>

Both refuse a populated directory; each case's exit code is written to its own file before anything else runs.

## What this does not show

- No interrupts: `mie`/`mip` are unimplemented and trap, and nothing drives an interrupt line.
- No delegation, no PMP, no S or U mode, no MMU, no compressed instructions.
- The ELF is still pre-loaded through a backdoor port; this is not the ROM boot path.
- The core is not connected to the M1 bridge or the SoC, and nothing here has been near a board.
- The Rocket and Sodor sources in the chipyard tree, the board flow and the PS image are untouched. The
  teaching CPU's own sources did change — that is this milestone's deliverable.
