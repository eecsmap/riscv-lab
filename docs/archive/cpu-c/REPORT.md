# CPU-C — the RV64 integer C extension on the teaching core: report

Delegation: `codex-cpu-c-extension` (acked). Simulation only: nothing synthesised, no board, no default
bitstream/PS/SD change; `TeachingBoardTop.TeachingBoardConfig.v` untouched; shared `tests2/`, `run-m2-3.sh`,
`ZynqAdapter.scala`, testchipip, rocket-chip, `TeachingCpuSoc.scala` untouched (copies with recorded diffs).
Scope: integer C only (I+M+C). No A/F/D/S/U/Sv39/PMP/Zc*.

Entry points (each refuses to overwrite an existing output dir):
* `scripts/build-cdecode.sh <dir>` — decompressor unit test (`unit-run1/`)
* `scripts/run-cpu-c.sh <dir>` — every core-level gate in one run (`core-run3/`, `CPU_C_DONE fails=0`)
* `scripts/run-soc-c.sh <dir>` — the SoC gate (`soc-run2/`, `SOC_C_DONE fails=0`)
* `HASHES.sh` — source → RTL → simulator → ELF → log chain (`HASHES.txt`, `HASHES-VERIFY.txt`)

## What was built (`DESIGN.md`, `ENCODINGS.md`)

* `rtl/tcpu_cdecode.v` — a combinational 16→32 decompressor; every RV64 integer C encoding is expanded to
  its base instruction, HINTs to `addi x0,x0,0`, and reserved / FP / custom parcels are flagged illegal.
* `rtl/tcpu_core.v` — serial halfword fetch: the first parcel is a 2-byte request at `pc`; if bits[1:0]==11
  a second 2-byte request at `pc+2` follows (states `S_IF2_REQ`/`S_IF2_WAIT`); `insn_len` 2/4; the raw
  parcel is what `mtval` and the commit record carry; `pc+2` has its own range check.
* `rtl/tcpu_csr.v` — `misa` = `0x8000_0000_0000_1104`; `mepc` masks bit 0 only (IALIGN=16).
* Testbench: `commit_len`, IRQ points 9/10 (second parcel request / response outstanding),
  `FETCH_ERR_ADDR` (fail the fetch of exactly one address, either parcel), `+core-reset-at-op=if2`,
  named faults `FAULT_C_IMM` (addi4spn imm bits 2/3 swapped) and `FAULT_C_REG` (compact regs → x0..x7),
  and a model of the reset bridge for core-only resets (below).

## Gates

**1. Decompressor unit (`unit-run1/`).** Independent C++ reference written from the field lists in
`ENCODINGS.md`, all 49152 parcels of the three non-11 quadrants: 38157 legal, 394 HINT, 10601 illegal,
0 disagreements. Both named faults are rejected (1024 and 16232 disagreements, first case printed).

**2. Every integer C instruction (`core-run3/`, gate 2).** `tests/c01_compressed.S` executes all 31 integer
C mnemonics with result checks; exit 0 under the min, fixed-backpressure and seeded-random memory profiles,
216 commit records byte-identical across the three, 135 of them 2-byte. Coverage checker
(`scripts/check-c-coverage.py`, from the commit trace and objdump): 31/31 mnemonics, 32-bit instructions
starting at every pc%8 (0,2,4,6), 5 HINT-shaped retirements. The M programs still pass on the C core
(`m01` regenerated with `--misa=0x...1104`, 410 checks × 3 profiles; `m02` IRQ in `S_MUL`).

**3. Boundaries (gate 3).** `tests/c02_boundary.S` with `link-c02.ld`: starts at pc%8 = 2/4/6, a 32-bit
instruction straddling the 4 KiB boundary at `0x80000ffe`, the all-zero parcel and a reserved parcel
(cause 2, `mtval` = the parcel), `c.ebreak` (cause 3), `mret` to a halfword address: exit 0 with exactly
3 traps and the straddle retired. Fetch errors: a bus error on the *first* parcel of the straddling
instruction gives cause 1, `mepc=0x80000ffe`, `mtval=0x80000ffe`; on the *second* parcel cause 1,
`mepc=0x80000ffe`, `mtval=0x80001000`; the instruction never retires.

**4. Interrupts and reset in the middle of a fetch (gate 4).** A persistent IRQ raised while the second
parcel is requested (`FIRE state=IF2_REQ`) or outstanding (`state=IF2_WAIT`) on an rv64i program: exactly
one interrupt, handler `mepc` at the instruction after the one being fetched, program result correct.
A core-only reset in `S_IF2_WAIT` on c01 and c02 under all three profiles: no commit before the reset
vector, the interrupted instruction retires once on the re-run, and the stale answer (when the memory
answers after the restart — the slower profiles) is swallowed by the bridge model (`model=1`).

**Named negatives.** `FAULT_C_IMM` and `FAULT_C_REG` cores fail c01 at check 6 (the addi4spn/compact-reg
checks) and still pass the RV64I `t01` control. `c01` originally used `addi4spn ... 8+4=12`, whose imm bits
2 and 3 are both set and so the swap was invisible (found by `core-run1`); the offset is now 8.

**5. Regression and SoC (gate 5).** The M2-3 suite on the C core (`core-run3/m23/`,
`scripts/run-m23-with-c.sh`): `M2_3_DONE fails=0`, 25 builds. Recorded changes (diffs kept): the runner copy
(builds include muldiv+cdecode, misa), `c02_warl` copy (misa value; `mepc` written `0x80000006` now reads
back `...06` — IALIGN=16), `c06_targets` copy (`jalr` to a 2-byte target is now legal, `expect-traps=0`).
SoC (`soc-run2/`): the R-BOOT generated RTL (unchanged, `2986e75d…`) re-verilated with the C core; the four
M3 ELFs (unchanged, `m4-prep/sim-regression-2` set) pass `check-m3`/`check-axi` 4/4; `boot09_muldiv`
(copy, one misa line changed, diff recorded) prints `M3-MULDIV-OK`; `tests/boot10_rvc.S` (rv64imc, 28
compressed instructions) prints `M3-RVC-OK`; and the original `xv6-on-rocket-pynq-z1/riscv-test/hello.riscv`
— audited: I+C mnemonics only, console via the fesvr syscall proxy, exit via `tohost` — runs unmodified and
prints `sum(1..100) = 5050 (expected 5050)` / `PASS`, `HOSTDONE exit_code=0`.

## Runs that failed, kept

* `core-run1/` (fails=5): `dbg_req_is_fetch` covered the first parcel only, so `FETCH_ERR_ADDR` could not
  hit a second parcel and the M2-3 `dir-*` cases counted second parcels as data requests; the core-reset
  case tripped the "request withdrawn" protocol monitor (a reset core drops its offer — bridge business);
  the `FAULT_C_IMM` negative was invisible (see above). Fixes in `core-run1-to-run2.diff`.
* `core-run2/` (fails=2): the bridge model flagged a stale answer due in the reset cycle for later and then
  waited for a response that had already gone out (c02/min hung). Fix in `core-run2-to-run3.diff`.
* `soc-run1/` (fails=1): the original `boot09` checks `misa == I+M`; on the C core it is I+M+C. Copy with
  the one changed line, diff in `soc-run2/prog/boot09_muldiv.diff`.
* M2-3 attempts that died on Verilator's "attempted to destroy locked Thread Pool" were retried, never scored.

## Post-acceptance fix-ups (Codex review, 2026-09-18; `fixups-run2/`, `CPU_C_FIXUPS_DONE fails=0`)

Three verification points Codex asked to be firmed up after accepting CPU-C, re-run on the delivered
`core-run3` simulators and ELFs (hashed in `fixups-run2/inputs.sha256`) by `scripts/run-cpu-c-fixups.sh`;
the same changes are folded into `scripts/run-cpu-c.sh` for future full runs (not re-run in full):

1. **IRQ during the second parcel with interrupts enabled.** The injection is aimed at the instruction
   right after the first `csrrs ... mstatus` in `i01` (derived from the disassembly at run time, not a
   hard-coded address): a 32-bit `lui t2,0x31`. Both IF2_REQ and IF2_WAIT: `enabled=1`, the target retired
   exactly once before the interrupt, `x7 = 0x31000` visible in the register file, `mepc = target + 4`
   (`CHAIN OK`, `FIRE STATE OK`).
2. **Named negatives with the exact check number.** The expected `tohost` (6) is derived from `c01`'s
   source (the first check after `c.addi4spn`); both fault cores exit 6, the RV64I control passes.
   `fixups-run1/` is kept: the first derivation matched a comment line and expected 4 — a runner bug, fixed.
3. **Fetch errors: zero retirements of the faulting PC from real evidence.** `+expect-commit-count=<pc>:0`
   and the commit trace agree: 40 instructions retired before the trap, the straddling PC 0 times, for
   both the first- and second-parcel error; the control run retires it exactly once.

The bridge-model wording stands as Codex stated it: the core-side reset cases use the testbench's stale-
response model and are not a re-proof of the real RD2 bridge's reset windows with the new core; the
run-time rule that a valid request is never withdrawn is unchanged.

## Not claimed

* No resource/timing numbers; nothing synthesised.
* Fetch is two serial halfword transactions for a 32-bit instruction (D1: simplest correct thing, not fast).
* HINTs retire as `addi x0,x0,0`; no Zc*, no `c.flw/c.fld` (illegal), no misaligned-fetch of any kind.
