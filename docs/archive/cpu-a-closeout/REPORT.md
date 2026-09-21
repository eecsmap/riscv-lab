# CPU-A closeout: the write-restart gate, strict exit codes, and the A-enabled regressions

Claude, 2026-09-19. Delegation `codex-cpu-a-closeout` (acked), from `cpu-a/CODEX_REVIEW.md`. Three items.
Nothing here reopens the A implementation, which Codex independently rebuilt and reproduced.

## Item 1 — `g2-write-inflight`: evidence first, and it changes the question

The delegation asked for the first causal difference between a passing old simulator and a failing one on
the same ELF, disk and trigger, with no presupposed root cause. That comparison is in `G2_EVIDENCE.md`;
the artefacts are in `evidence/` with `inputs.sha256`.

What it shows:

* Aligned by instruction rather than by cycle, the accepted-core run and the newer-core run **execute the
  same 297 program instructions**. The only difference is speed: the newer core fetches 16-bit parcels
  (CPU-C), so it reaches that point at cycle 8945 where the old core reaches it at 6404 — about 1.4×.
* The gate's trigger is a fixed cycle (9000). Injecting the restart into the **accepted `build3`
  simulator** at 6300, 6404 or 6450 — where the newer core is at cycle 9000 — makes **the accepted
  simulator fail the gate too**, 300000 cycles with no completion. The accepted core, the accepted RTL and
  the accepted host model reproduce the failure on their own.
* The discriminator is what the drain finds: a passing restart starts with `bdevInflight=0`, a failing one
  with `bdevInflight=1`.
* My first report's guess ("the device's completion never arrives") was **wrong**, and is corrected here:
  the data reaches the disk twice (the failing run's sectors 2 and 3 both hold the pattern, byte-identical
  to the passing run's sector 2), and the completion count the program polls is non-zero 120 times. The
  device completes; the program does not recognise it is done and re-submits until the budget runs out.

So the gate is not a CPU regression at any stage. It is a phase-sensitivity of the restart-boot scenario
itself, in accepted artefacts: either `boot07_blkdev_write`'s recovery path or the R-BOOT contract for a
device transfer that is in flight when the drain begins. The delegation says to raise a ruling before
changing an accepted chain, so **no fix is applied here** and the entry point no longer exempts the gate:
`scripts/run-soc-a.sh` requires all eight and reports the failure with a pointer to the evidence.

What any fix must preserve is already measured: sector 2 holding the 64 doublewords, the re-submission and
completion gates, and a restart with the device idle continuing to pass.

## Item 2 — a positive is only a pass when the process passed

* `check-a01.py` and `check-a02.py` now take `--rc` and `--log`, and fail unless the simulator exited 0,
  the log carries `TOHOST code=0`, and no monitor fired (`PROTOCOL ERRORS`, `OBSERVATION ERRORS`,
  `A_OBS_FAIL`, `TIMEOUT after`).
* `run-cpu-a.sh`'s `score` used to receive the exit code and ignore it; it now fails the run on a non-zero
  exit as well as on the checker's verdict, and passes `--rc`/`--log` to every positive checker.
* Two self-tests of the rule itself, inside the entry point: a clean data set scored with `--rc 3` must be
  refused ("a positive run must exit 0"), and a run whose log carries no completion signature must be
  refused. Both are refused.
* The five named negatives are unchanged: each is still only counted when its own named check fires.

`core-run3/`: `CPU_A_DONE scenarios=17 infra=0 fails=0` — the ten positives, the two new self-tests and the
five negatives.

## Item 3 — the frozen regressions on the A-enabled configuration

The earlier regressions ran with `MISA_A = 0`, which shows the old configurations still work but says
nothing about the new one. Both suites now run against `MISA_A = 1` as well, through an opt-in
(`MISA_A_ONE=1`) that is inert when unset:

* `run-cpu-sv39.sh` builds its simulators with `-GMISA_A=1`; `make-su-copies.sh` moves `su09_warl`'s misa
  expectation to `0x8000000000141105` **in the copy**, with the diff recorded as the existing copies are.
* `run-m23-with-sv39.sh` does the same for `c02_warl` and for the copied runner's `+expect-csr=8:` value.

Results: `regressA-sv39/` `CPU_SV39_DONE fails=0`, `regressA-m23/` `M2_3_DONE fails=0`. That the opt-in
really took effect is checked rather than assumed: `VTeachingTop__verFiles.dat` carries `MISA_A=1`, the
copied `su09_warl.S` and `c02_warl.S` carry `…141105`, and the copied runner carries
`+expect-csr=8:8000000000141105`. The genuine illegal-instruction and CSR gates are untouched; only the
misa literals moved, and only in copies.

At SoC level the program list is now the full one from the original task, on **both** configurations, each
with its own recorded misa copy: the four M3 programs, `boot11_sv39`, `boot09_muldiv`, `boot10_rvc`, the
original `hello.riscv`, and `su01_modes` / `su05_irq_modes` / `su06_timer_ssip` on the real CLINT — plus,
on the atomic configuration only, `boot12_amo` and the two `misa` probes. Every one of them is recorded
with its own real exit code and both checkers' verdicts, per configuration.

## What is not claimed

No synthesis, no board, no `xv6` or `start.c` change; the default Rocket, SD and PS chains are untouched.
The A implementation itself is unchanged from the accepted delivery.
