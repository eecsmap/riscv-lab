# M2-1: the teaching CPU's execution core, on a standalone harness

Delegation: `codex-m2-1-execution-core`, then `codex-m2-1-corrections` after review.
Accepted run: `run-f`. Independent re-derivation: `src/check-m2-1.py`. First-round report: `REPORT-round1.md`.
Review that rejected the first round: `CODEX_REVIEW.md`.

## The four blocking findings, and what was actually wrong

### 1. An illegal JALR was executed

`is_jalr` tested only the opcode. JALR is defined for `funct3 = 000` alone, so seven encodings per address
were being accepted and jumped to. Codex reproduced it independently with `codex-jalr-illegal.S`, which the
old core ran to a passing exit.

Fixed by folding the funct3 test into `is_jalr`, which takes the bad encodings out of `known_op` and makes
`illegal` fire. The evidence is Codex' own counterexample plus one program per illegal funct3, and each run
requires three separate things: the trap is cause 2, the faulting PC never appears in the commit stream, and
the link register still holds the sentinel it was given before the instruction.

| case | trap | retired at the faulting PC | link register x9 |
|---|---|---|---|
| `codex-jalr.i.elf` | cause 2 at 0x80000030, tval 0x29067 | 0 | n/a |
| funct3 = 1..7 | cause 2 at 0x80000038, tval 0x2{9,a,b,c,d,e,f}4e7 | 0 | 0x5a5a5a5a, unchanged |

### 2. A load carried a write payload

`S_EXEC` assigned `req_wdata <= rs2_val << lshift` for loads and stores alike. The rs2 field of a load is
immediate bits, not a register selector, so a read request was putting an unrelated register's contents on
the bus. PHYSICAL_PORT_V1 requires a read to carry no payload.

Fixed to `is_store ? (rs2_val << lshift) : 0`, and a monitor now rejects any accepted read whose `wdata` or
`wmask` is non-zero. `d06_loadpayload.S` makes the leak observable rather than theoretical: it loads from
offset 8, whose rs2 field names x8, having first put 0xDEADBEEF in x8. With `LOAD_WDATA_LEAK=1` the monitor
reports exactly that value and the run cannot exit 0:

    PROTO ERROR: read request carried a write payload wdata=00000000deadbeef wmask=00

Without the injection the same program is clean.

### 3. The run was judged before the last transaction finished

The driver polled the tohost word through the backdoor and stopped the moment it appeared. The memory model
writes on accept, so that is before the response and before the store retires — every positive run in the
first round shows one more request than responses.

The value is now latched and the run continues until that store has been answered and has retired. Two
controls show the difference is real, each failing for its own reason rather than by a generic timeout:

| control | what it does | result |
|---|---|---|
| `tail-err` | the write to the completion address returns with `error` | store access fault, cause 7, exit 4 — no pass, although the value is already in memory |
| `tail-drop` | that write is never answered | `TAIL INCOMPLETE ... req=19 resp=18, retired 0 of the store`, exit 10 |

Every positive run in `run-f` ends with `req == resp`.

### 4. Two CSRs were fabricated

The core accepted reads of `cycle` and `mcycle` and answered 0. It has no cycle counter. Those encodings are
gone and now trap as illegal (`d07_csr_cycle`, cause 2). The counter that does exist is still read under both
of its real names, and `d08_minstret_ok` checks that it advances by exactly the three instructions between
two reads, so removing the fabrication did not quietly remove the real thing.

### The other boundary raised: commit versus the register file

The observation port is not self-certifying any more. The register file has a debug read port, and one cycle
after every commit the harness reads the architectural register the commit claimed to write and compares it
with `commit_rd_data`. A disagreement is counted and fails the run. `check-m2-1.py` requires zero of these in
every positive run. Timing, stated exactly: `S_WB` schedules `rf_we`, so the write lands at the end of the
next cycle, which is the same cycle in which `commit_valid` is high; the read-back therefore samples the
register after that edge.

## What was built

An RV64I multi-cycle core that reaches memory only through PHYSICAL_PORT_V1, on a harness that is
deliberately not the M1 SoC: no TileLink, no bridge, no Rocket.

| piece | file | role |
|---|---|---|
| core | `src/rtl/tcpu_core.v` | 8-state machine, fetch and data through one physical port |
| registers | `src/rtl/tcpu_regfile.v` | 31x64, x0 not stored, two debug read ports |
| harness | `src/tb/tcpu_harness.v` | memory model, timing profiles, protocol and observation monitors |
| driver | `src/tb/tcpu_main.cpp` | ELF pre-load, completion judgement, commit records |
| runner | `src/run-m2-1.sh` | builds the programs and all ten simulator variants, runs the matrix |
| checker | `src/check-m2-1.py` | re-derives every verdict from the raw logs |

Scope: the RV64I base, `fence` as a no-op, and one CSR form — `csrrs rd, minstret|instret, x0`. Everything
else in SYSTEM traps. A trap halts; M-mode trap handling is M2-2, which is why `t04_trap` is a declared-scope
case rather than a passing one: it traps at the first `csrw mtvec` with cause 2 and that instruction does not
retire, and the checker requires exactly that.

## Results

Twelve positive runs, four programs across three timing profiles, all exit 0, no protocol error, no
observation error, and `req == resp` in every one.

| profile | req.ready held low | response latency |
|---|---|---|
| min | 0 cycles | 1 cycle, the earliest the contract allows |
| fixed | 2 cycles | 5 cycles |
| random | 0-7, LFSR seed 12345 | 1-8, same LFSR |

The comparison across profiles is now the full commit record — pc, instruction word, destination register and
written value — not a retirement count:

| program | commit records, identical across all three profiles |
|---|---|
| t01_alu | 84 |
| t02_branch | 75 |
| t03_ldst | 94 |
| t05_roi | 79 |

t03_ldst cycle counts, min / fixed / random: 742 / 1432 / 1309. The checker requires the records to match
byte for byte, to be non-trivial in length, and to contain register writes.

### The ROI trace

Window `(0x80000050, 0x80000060]`: opened once the starting `csrr` has retired, closed including the ending
`csrr`. The 49 expected PCs come from the disassembly via `m2-prep/tests/expected-trace.py`, never from the
counter being measured. All three profiles match all 49 entries, and the program's own `roi_measured` reads
back 49.

### Faults, and what rejected them

| injection | program | exit | what caught it |
|---|---|---|---|
| x0 becomes writable | t01_alu | 1 | `CHECK_X0_ZERO` |
| loads stop sign-extending | t03_ldst | 3 | t03 check 3: `lw` of 0xffffffff must read as -1 |
| loads stop sign-extending | t02_branch | 0 | nothing: the fault is narrow, this program has no loads |
| a load carries a write payload | d06 | 5 | the read-payload monitor, quoting the leaked value |
| final store answered with error | d08 | 4 | store access fault |
| final store never answered | d08 | 10 | the completion check, with its own reason |
| none (check-structure control) | t01n_x0check | 1 | the comparison sees a non-zero value |

The x0 injection has no narrow control, and the first attempt to write one was wrong: `j label` assembles to
`jal x0, label`, so on a writable-x0 core every jump leaves a return address in x0 and every later
`li rd, imm` is poisoned. t02_branch is therefore required to fail there, and only "not zero" is claimed
about its exit code. See `run-a/SUPERSEDED.md`.

### The monitors are not vacuous

| injection | monitor output | exit |
|---|---|---|
| memory answers combinationally in the accept cycle | 23 counts of "response in the request handshake cycle" | 4 |
| core drops req.valid once before its handshake | 1 count of "request withdrawn before the handshake" | 4 |
| a load carries a write payload | 1 count naming 0xdeadbeef | 5 |

### Directed boundary tests

| test | required behaviour | observed |
|---|---|---|
| d01_highpa | bits [63:32] set must not be truncated | cause 7, zero data requests on the bus |
| d02_misaligned | a misaligned load traps before issuing anything | cause 4, zero data requests on the bus |
| d03_badbranch | an untaken branch with a misaligned target must not trap | falls through, passes |
| d04_illegal | an unimplemented encoding must not retire | cause 2, faulting PC absent from the commit stream |
| d05 x 7 | every illegal JALR funct3 | cause 2, no retirement, link register untouched |
| d07 / d08 | no fabricated CSR, the real counter still advances | cause 2 / passes |

## Evidence layout

    run-f/            the accepted run: logs, per-case exit files, commit records, ELFs, disassembly, hashes
    run-e/            the rejected first submission, kept as the negative control for the checker
    run-a..d/         earlier superseded runs, each with SUPERSEDED.md
    src/              sources, tests and both scripts, with SRC.sha256
    CODEX_REVIEW.md   the review that rejected round one
    REPORT-round1.md  the first-round report, unedited

`check-m2-1.py` reports 0 findings on `run-f` and 101 on `run-e`, which is what makes the new checks worth
anything: unfinished tails, absent commit records, and every one of the four blocking cases show up there.

Identity chain: `src/SRC.sha256` -> `run-f/source.sha256` (verified equal) -> `run-f/sim.sha256` (each of the
ten simulator binaries and its generated C++) -> `run-f/elf.sha256` -> `run-f/commits.sha256`.
`run-f/tools.txt` records Verilator 5.022, riscv64 gcc 13.2.0 and the host compiler.

Reproduce into a directory that does not exist, then re-derive:

```
teaching-cpu-work/cpu/run-m2-1.sh <newdir>
teaching-cpu-work/cpu/check-m2-1.py <newdir>
```

Both refuse a populated directory, and each case's exit code is written to its own file before any other
shell command runs.

## What this does not show

- No M-mode trap handling, so no test takes a trap and returns from it. That is M2-2.
- The ELF is pre-loaded through a backdoor port. This is not the ROM boot path M0 documented, and nothing is
  claimed about reset behaviour beyond the core starting at its reset PC.
- No compressed instructions: the `.ic` flavours were not run. The core is rv64i only.
- The core is not connected to the M1 bridge or the SoC.
- The teaching CPU's own sources were changed in this round — that is the deliverable. What was not touched
  is the Rocket and Sodor source in the chipyard tree, the board flow and the PS/rootfs.
