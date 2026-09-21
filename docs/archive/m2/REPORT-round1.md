# M2-1: the teaching CPU's execution core, on a standalone harness

Delegation: `codex-m2-1-execution-core`. Accepted run: `run-e`. Independent re-derivation: `src/check-m2-1.py`.

## What was built

An RV64I multi-cycle core (`src/rtl/tcpu_core.v`, 330 lines) that talks to memory only through
PHYSICAL_PORT_V1, plus a harness that is deliberately *not* the M1 SoC: no TileLink, no bridge, no Rocket.
The point of the standalone harness is that a passing run here cannot be explained by anything the earlier
milestones already proved.

| Piece | File | Role |
|---|---|---|
| core | `src/rtl/tcpu_core.v` | 8-state machine, fetch and data both through one physical port |
| registers | `src/rtl/tcpu_regfile.v` | 31x64; x0 is not stored unless the fault parameter says so |
| harness | `src/tb/tcpu_harness.v` | memory model, timing profiles, protocol monitor |
| driver | `src/tb/tcpu_main.cpp` | ELF pre-load, tohost verdict, external commit checker |
| runner | `src/run-m2-1.sh` | builds the programs and every simulator variant, runs the matrix |
| checker | `src/check-m2-1.py` | re-derives every verdict from the raw logs |

The memory model answers from a registered path, so it can never respond in the request cycle. Loads and
stores are byte-lane masked. Out-of-range addresses come back with `error` set rather than silently reading 0.

## Scope, stated plainly

Implemented: the RV64I base, plus `fence` as a no-op, plus exactly one CSR form: `csrrs rd, <counter>, x0`
for `minstret`, `cycle` and their aliases, which is what the ROI test needs. Everything else in the SYSTEM
opcode traps as an illegal instruction. A trap halts the core; M-mode trap *handling* (mtvec, mepc, mret) is
M2-2's work, which is why `t04_trap` is not in the positive matrix. It is built and run as a declared-scope case: it
traps at the first `csrw mtvec` with cause 2, that instruction never retires, and `check-m2-1.py` requires
exactly that outcome, so the boundary is evidence rather than an assertion.

## Results

Twelve positive runs, four programs across three timing profiles, all exit 0 with no protocol error:

| profile | req.ready held low | response latency |
|---|---|---|
| min | 0 cycles | 1 cycle, the earliest the contract allows |
| fixed | 2 cycles | 5 cycles |
| random | 0-7, LFSR seed 12345 | 1-8, same LFSR |

The architectural result does not move with the timing, and the timings really do differ. Both are checked by
`check-m2-1.py`, not asserted here:

| program | instructions retired (all three profiles) |
|---|---|
| t01_alu | 83 |
| t02_branch | 74 |
| t03_ldst | 93 |
| t05_roi | 78 |

t03_ldst cycle counts, min / fixed / random:

    739 / 1425 / 1300

### The ROI trace

The window is `(0x80000050, 0x80000060]`: opened once the starting `csrr` has retired, closed including the
ending `csrr`. Both boundary conventions are in the code and in `run-e/t05-window.txt`. The expectation is 49
PCs derived statically from the disassembly by `m2-prep/tests/expected-trace.py`, never from the counter being
measured. Under all three profiles the recorded commit trace matches all 49 entries PC by PC, and the program's
own `roi_measured` reads back 49.

### Faults, and what rejected them

Every injection is rejected by a named architectural check with that check's own exit code. None is rejected
by a timeout or a build failure.

| injection | program | exit | what caught it |
|---|---|---|---|
| x0 becomes writable | t01_alu | 1 | `CHECK_X0_ZERO` |
| loads stop sign-extending | t03_ldst | 3 | t03 check 3: `lw` of 0xffffffff must read as -1 |
| none (check-structure control) | t01n_x0check | 1 | the comparison sees a non-zero value |
| loads stop sign-extending | t02_branch | 0 | nothing: the fault is narrow, this program has no loads |

The x0 injection has no equivalent narrow control, and the first attempt to write one was wrong. `j label`
assembles to `jal x0, label`, so on a writable-x0 core every jump leaves a return address in x0 and every
later `li rd, imm` is `addi rd, x0, imm` and is poisoned. t02_branch is therefore required to fail on that
core, and only "not zero" is claimed about its exit code, because the code itself is built through x0. The
withdrawn claim and its evidence are in `run-a/SUPERSEDED.md`.

### The protocol monitor is not vacuous

Three rules are checked continuously: the request payload is held unchanged until the handshake, one request
is outstanding at a time, and no response arrives in the request-handshake cycle. Two injected violations
prove the monitor can fire and that a violating run cannot exit 0:

| injection | monitor output | exit |
|---|---|---|
| memory answers combinationally in the accept cycle | 23 counts of "response in the request handshake cycle" | 4 |
| core drops req.valid once before its handshake | 1 count of "request withdrawn before the handshake" | 4 |

The first version of the same-cycle injection was a non-blocking assignment, so it took effect the next cycle
and was a legal one-cycle response. The monitor was right to stay silent, and the injection was rewritten to
drive the response combinationally. `run-c` keeps that failing evidence and doubles as the negative control
for the checker: `check-m2-1.py` must report it there and report nothing on `run-e`.

### Directed boundary tests

| test | required behaviour | observed |
|---|---|---|
| d01_highpa | an address with bits [63:32] set must not be truncated | trap cause 7, zero data requests on the bus |
| d02_misaligned | a misaligned load traps before issuing anything | trap cause 4, zero data requests on the bus |
| d03_badbranch | an untaken branch with a misaligned target must not trap | falls through, program passes |
| d04_illegal | an unimplemented encoding must not retire | trap cause 2, and the faulting PC never appears in the commit stream |

"Zero data requests" is measured on the bus side by a counter that excludes instruction fetches, and the
directed tests use a startup file that performs no data access at all, so the number is a clean measurement.
"Never retired" is checked by counting commits at the trapping PC, not by counting instructions.

## Evidence layout

    run-e/            the accepted run: logs, per-case exit files, ELFs, disassembly, source snapshot, hashes
    run-a..d/         superseded, each with SUPERSEDED.md saying what was wrong and why it is kept
    src/              the sources, tests and both scripts, with SRC.sha256

Identity chain: `src/SRC.sha256` -> `run-e/source.sha256` (the snapshot travelling with the run, verified
equal) -> `run-e/sim.sha256` (each simulator binary and its generated C++) -> `run-e/elf.sha256`.
`run-e/tools.txt` records Verilator 5.022, riscv64 gcc 13.2.0 and the host compiler.

To reproduce, into a directory that does not yet exist, then re-derive:

```
teaching-cpu-work/cpu/run-m2-1.sh <newdir>
teaching-cpu-work/cpu/check-m2-1.py <newdir>
```

Both refuse to reuse a populated directory, and every case's exit code is written to its own file before any
other shell command runs.

## What this does not show

- No M-mode trap handling, so no test that takes a trap and returns from it. That is M2-2.
- The ELF is pre-loaded through a backdoor port. This is not the ROM boot path that M0 documented, and no
  claim is made about reset behaviour beyond the core starting at its reset PC.
- No compressed instructions: the `.ic` flavours were not run. The core is rv64i only.
- The core is not connected to the M1 bridge or the SoC. Bringing it up behind TileLink is a separate step.
