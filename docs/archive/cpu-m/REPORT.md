# CPU-M — RV64 integer multiply/divide on the teaching core

**Scope held:** the multicycle single-port core gains the 13 M instructions and nothing else — no C, A,
S/U, Sv39 or PMP; Rocket, the board boot chain and the default configurations are untouched; nothing was
synthesised or put on the board. Resources and timing are **not** reported: nothing here has been through
Vivado, and guessing would be worse than silence.

Design: `DESIGN.md`. Sources: `teaching-cpu-work/cpu/rtl/tcpu_muldiv.v` (new), `tcpu_core.v` (decode,
`S_MUL`, dispatch/writeback), `tcpu_csr.v` (misa), the testbench (`tcpu_harness.v` injection point 8,
`tcpu_top.v`/`tcpu_main.cpp` parameter plumbing and state name).

## Gate 1 — the unit against an independent reference (`unit-run1/`)

`unit/tb_muldiv.cpp` drives `tcpu_muldiv` alone. The reference is C++ 128-bit arithmetic with the RISC-V
rules written out (division by zero, the single signed overflow, remainder sign, W narrowing and sign
extension); it shares no algorithm with the RTL. Per operation: a 19×19 grid of edge operands (0, 1, −1,
±max/min, sign boundaries, 32-bit-shaped values, high-carry patterns) plus **256 fixed-seed random pairs**
(seed 20260917, mixed full-width / small / 32-bit-shaped / byte-sized operands).

| build | cases | failures | note |
|---|---|---|---|
| clean | 8022 | **0** | start-to-done **65 cycles**, min = max, all 13 operations |
| `FAULT_W_SEXT` (named negative) | 8022 | 882 | first: `MULW 1 × −1 got 0x00000000ffffffff want 0xffffffffffffffff` |
| `FAULT_MULH_SIGN` (named negative) | 8022 | 513 | first: `MULH 1 × −1 got 0 want −1` |

The contract is checked on every case: `busy` rises the cycle after `start`, a second `start` while busy
(with poisoned operands) is ignored, `done` is exactly one cycle wide with the result on it, the result is
held afterwards. Reset in the middle of a divide: busy/done fall, **no `done` appears in the next 80
cycles**, and a fresh operation afterwards is correct (`RESET MID-OP` line). Every vector and result is in
`unit-run1/*.vectors`.

## Gate 2 — instruction level, three timing profiles (`core-run2/`)

`tests/gen_m01.py` writes `m01_muldiv.S` with expectations computed in Python from the architectural
rules: 30 operand pairs × 13 operations, rs1 = rs2, rd = rs1, rd = rs2, rd = x0 (x0 stays 0 and the sources
are untouched), a seven-instruction dependency chain through the unit, and `misa` read-back — **410
checks**, each with its own exit code. Run on the min / fixed-backpressure / seeded-random-delay memory
profiles: exit 0 on all three, **zero protocol errors**, and the **3450 commit records** (pc, encoding, rd,
value) are byte-identical across the three profiles. `misa` reads `0x8000_0000_0000_1100` (I + M).

## Gate 3 — a persistent interrupt during a long operation (`core-run2/logs/m02-*`)

`tests/m02_irq_muldiv.S` arms the harness injector (new point 8: the core is in `S_MUL`), then executes
`mulh`, later `div`. Both configurations (fast memory, and 2/8-cycle delays):

```
IRQ hits=201 fires=2   FIRE cycle=1156 pc=0x80000290 state=MUL   INTERRUPT COUNT OK   IRQ COVERAGE OK
```

The line was raised while the core was in `S_MUL` (201 such cycles seen, 2 raises), exactly two interrupts
were taken, the multiply's and the divide's results are the expected ones, and `mepc` recorded by the
handler equals the label **after** each long instruction — it retired first. Multiply and divide each have
their own hit.

## Gate 4 — regressions and named negatives

* Cores built with `FAULT_W_SEXT` / `FAULT_MULH_SIGN` fail `m01` with tohost codes **247** and **36** — the
  specific W-extension and signed-high-half checks — and still pass the RV64I `t01_alu` (controls).
* The accepted M2-3 regression (I, CSR, exceptions, interrupts, fault injections, monitors — 24 simulator
  builds) is re-run on the M core via a copy of its runner that differs in **two recorded lines**
  (`m23-run1/run-m2-3-with-m.diff`): the unit's source file is added to every build, and `c02_warl`'s
  `misa` expectation gains the M bit. Result: see `m23-run1/` (filled in below).

  **Result** (`m23-run2/`): `M2_3_DONE fails=0` on the first attempt — every carried-forward gate (4
  programs × 3 profiles, ROI trace, CSR forms/WARL/illegal, counters, exceptions, handler fault, the
  CPU-level fault injections and their controls, the monitor self-tests, the interrupt matrix, the argument
  checks) passes on the M core. Three recorded lines changed in total: two in the runner copy
  (`run-m2-3-with-m.diff`) and one in a *copy* of `c02_warl.S` (`c02_warl.diff`) — the program's own
  `misa` comparison. The accepted `tests2/` directory and `run-m2-3.sh` are not edited, so the RV64I
  regression still means what it meant.
  The first attempt (`m23-run1/`, kept) failed exactly there: `csr-warl` exited with the program's check
  code 5 because the unpatched program still compared `misa` against the I-only value while the harness's
  CSR check already expected I + M. That is the expectation change, made visible rather than deleted.

## Gate 5 — the SoC (`soc-run1/`)

The R-BOOT simulator (`restart-boot/build3/gen-sim/RD2Harness.RD2BootConfig.v`, unchanged: the core is a
Verilog black box to Chisel) was re-verilated with the M-capable core sources. The four unchanged M3 ELFs
pass the accepted `check-m3`/`check-axi` gates (4/4), and a new program `tests/boot09_muldiv.S` — built for
rv64im and run through ROM/TSI/DDR/HTIF — prints `M3-MULDIV-OK` and exits 0. Its constants (a 64×64
product's low and high halves, signed and unsigned, a signed division and remainder, division by zero,
the 32-bit overflow, and a 200-iteration multiply loop) were computed in Python from the same rules and
are shown in the runner log; two of my hand-written first guesses were wrong and were replaced by the
generated values before the run, which is the point of not writing expected values by hand.

Hash chain: `soc-run1/sim/inputs.sha256` (generated RTL, core Verilog, simulator main, binary),
`soc-run1/prog/inputs.sha256` (ELF), `HASHES.txt` over everything.

## Closeout (Codex review, two items) — `core-run2/`

**One entry point.** The tail of `run-cpu-m.sh` used to splice its own copy of the accepted M2-3 runner and
got it wrong twice over: its substitution assumed `tcpu_csr.v` was followed by a line continuation, so the
generated script never included `tcpu_muldiv.v` (`core-run1/logs/m23.log` records that build failure), and
it never patched the *program's* own `misa` expectation. The fixed `scripts/run-m23-with-m.sh` is now the
only way that regression is invoked; the entry point calls it and records its exit. Its recorded changes:
six lines in the runner copy (the unit file in the builds, the `+expect-csr` value, and the tests2 path
redirected to a patched copy) and one line in the copy of `c02_warl.S`.

**Negatives pinned to their check numbers, derived.** `gen_m01.py` now applies each fault's model to its own
reference and reports the first check that rejects it (`FAULT_CODES wsext=247 mulhsign=36`); the entry point
demands exactly those exit codes from the faulted cores, not "any non-zero" — and they are the codes the
review observed.

**A core reset while a long operation is in progress.** New harness input `bd_core_rst` resets the core —
and with it the unit, which takes the core's reset — and nothing else: the memory model keeps its contents
and counters (the existing memory reset boundary). The main aims it at the k-th cycle the core is in
`S_MUL` on the named family, decoding the instruction at the live PC from the loaded ELF:

| | reset landed | evidence |
|---|---|---|
| multiply | cycle 87, pc `0x80000050`, `mul` (`0x026283b3`), state `S_MUL` | no commit before the reset vector; the interrupted instruction retired once, in the re-run; program exit 0, zero protocol errors |
| divide | cycle 16359, pc `0x80001424`, `div` (`0x0262c3b3`), state `S_MUL` | same |

The commits are the core's own (the check reads `commit_valid`); nothing is synthesised on the host side.

The unified run (`core-run2/`, `CPU_M_DONE fails=0`) covers gates 2, 3, 3b and 4 end to end; the SoC gate
(`soc-run1/`) stands, since the four core source files hash identically before and after this closeout
(only the testbench changed).

## What is not claimed

* No resource or timing numbers; nothing synthesised.
* The unit is 65 cycles for every operation, including a multiply by 0 or a divide by 1 — no early-out,
  by choice (D2: readability first).
* Interrupt pulses that fall while a long operation is in progress are not remembered; a level is what the
  CPU samples at its boundary, as before.
