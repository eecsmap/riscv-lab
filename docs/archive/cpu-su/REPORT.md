# CPU-SU — implementation report (Bare-address M/S/U)

Claude, 2026-09-18. Delegation `codex-cpu-su-implementation` (acked). Deliverables: `DESIGN.md`, this
report, the RTL diffs, `scripts/` (five reproducible entry points), the run directories named below,
`HASHES.txt`/`HASHES-VERIFY.txt`. The prep assets were synchronised to `CODEX_DECISIONS.md` first
(`cpu-su-prep/SPEC.md`, `DECISIONS.md`, `TEST_PLAN.md`, su09 read-backs, three new tests su10–su12,
handler support for software STI/SEI and the harness's test controller); `build2/ref-run2` were kept and
the updated tests were rebuilt as `build3` and re-run as `ref-run3`. No Rocket/board artefact, boot
software, or default configuration changed; nothing was synthesised.

## 1. Gates (every entry point refuses to overwrite an existing output directory)

| Gate | Entry point | Run | Result |
|---|---|---|---|
| Core: su01–su11 × {min, fixed-backpressure, seeded-random}, exit 0, no protocol errors, **`priv = M` at exit read from the real CSR port**; commit records byte-identical across profiles for the nine programs without asynchronous events (su02 without the value column: it reads `cycle`); su05/su06 (CLINT-timed) judged by their own order/result/count checks | `scripts/run-cpu-su.sh` | `core-run3/` | `CPU_SU_DONE fails=0` |
| Core: an M-level interrupt aimed at a U-mode instruction with MIE = 0 (su12): `enabled=1`, fired while `priv = U` (latched), the target retired exactly once before the interrupt, `x7 = 0x31000` visible, `mepc = target + 4`, MPP = U | same | `core-run3/logs/su12-aimed.log` | `CHAIN OK`, `FIRE STATE OK` |
| Core: named negatives — `FAULT_NO_DELEG` rejected by su01 check 11 (the delegated U ecall never reached S), `FAULT_S_IRQ_IN_M` by su05 check 14 (the S-level interrupt was handled at M level: 4 M interrupts, not 3), `FAULT_SRET_SPP` by su03 check 1 (SPP still set after sret); the RV64I control passes on all three fault cores | same | `core-run3/` | exits 11 / 14 / 1, controls 0 |
| Regression: the accepted M2-3 suite on the M/S/U core (25 builds, 93 runs) with **copies** and recorded diffs — runner (misa, mstatus-at-end 0xA00000000, unit+decompressor), c02_warl (misa I+M+C+S+U, write-all-ones 0xA000A19AA, clear reads 0xA00000000, mepc bit 1), c03 (the unimplemented-address case is menvcfg; mideleg is real now), c06 (C), i04_mip_level (a write of all ones to mip sets the three software bits next to the MTIP level) | `scripts/run-m23-with-su.sh` | `m23-run2/` | `M2_3_DONE fails=0` |
| CPU-C entry point on the new core (`MISA`/`M23` environment hooks; c01's own misa check built from a copy with the recorded diff; the M programs regenerated for the new misa) | `cpu-c/scripts/run-cpu-c.sh` | `c-gate-run2/` | `CPU_C_DONE fails=0` (gates 2–5 of CPU-C, incl. the fixed-up IRQ/negatives/fetch-error checks and the M2-3 copy with the S/U expectations) |
| SoC: the R-BOOT generated RTL (unchanged, `2986e75d…`) re-verilated with the M/S/U core; the four M3 ELFs (unchanged) through `check-m3`/`check-axi` 4/4; boot09 and boot10 from copies with one misa line changed (diffs recorded); the original `hello.riscv` unchanged (`sum(1..100) = 5050`, `PASS`); **su01, su05, su06 through ROM/TSI/DDR/HTIF with the real CLINT** — su06 is the xv6 timer path on the real device (M timer → SSIP → S clears; 919836 cycles, three rounds at 4000 ticks) | `scripts/run-soc-su.sh` | `soc-run2/` | `SOC_SU_DONE fails=0` |
| The prep references with the updated tests (su09 read-backs after the rulings; su10/su11 recorded, not gated) | `cpu-su-prep/scripts/reference-run.sh` | `cpu-su-prep/ref-run3/` | `SU_REFRUN_DONE fails=0`: su01–su07 0/0, su08/su09 1/1 as predicted; su10 times out on both references (they implement `wfi` as a real wait — an allowed choice; the SPEC's no-op is another); su11 fails check 1 on both (their `mip` write masks differ from the ruling) |

Hash chain: `HASHES.txt` (source → RTL copies in `core-run3/rtl` → simulators → ELFs → logs; the prep sources; the
CPU-C entry points; the R-BOOT generated RTL), `HASHES-VERIFY.txt` from a real `sha256sum -c`.

## 2. Runs that failed, kept

* `core-run1/` (fails=3): su02 in the byte-identical set (its `cycle` value propagates through the handler's
  save/restore — comparison rule changed, not the test); the FIRE line printed the level at exit instead of at
  the fire (harness now latches `fire_priv`); `FAULT_NO_DELEG` tripped su03 check 1 from U-mode rather than
  a delegation-specific check (moved to su01 check 11); `FAULT_S_IRQ_IN_M` was rejected by a trap storm (the
  fault re-entered the M handler at its first instruction) — the fault now respects MIE in M so su05's count
  check 14 is what rejects it. `core-run2/` (fails=1): the su02 comparison only.
* `m23-run1/` (fails=2): c02_warl's clear-all read-back is 0xA00000000, not 0 (UXL/SXL are read-only 2);
  i04_mip_level expects the pre-ruling "mip holds nothing" — both are expectation changes, recorded as copies.
* `soc-run1/`: boot10 failed its embedded misa check (copy added, as for boot09); the log ends in a bash
  parse error because the script was edited while that run was still executing (bash reads scripts
  incrementally) — the run's results up to su06 are real (all pass), and `soc-run2/` is the clean run.
* `c-gate-run1/` (fails=6): c01's own misa check (34) on all six c01 runs — the copy hook was added.
* Debugging on the way (not in the delivery tree): su11 first stormed because the S handler could not quiet a
  delegated software STI/SEI (it now masks the `sie` bit and leaves the pending bit to M), and its
  "waits for MIE" case forgot that `mret` had copied MPIE = 1 into MIE.

## 3. What the SoC runs show about the real CLINT

su05's msip interrupts and su06's timer rounds arrive from the real CLINT (`IRQLEVEL` events show msip and
mtip levels rising and being quieted), the boot MSIP/MRET chain is intact (`check-m3 boot`), and AXI
causality holds (`check-axi`). The harness's CLINT model is only a stand-in for the core-level runs.


## What is not claimed

* No Sv39, PTW, TLB, PMP, A extension, `time`/Sstc, vectored xtvec, S-level PLIC context. `misa.A = 0`.
* xv6 cannot run at this step (its `satp` write is ignored by design, D-2).
* The core-level CLINT model resets `mtimecmp`; the real device does not — the SoC runs use the real one.
* `su10` (wfi in U) and `su11` (software STIP/SEIP, SUM = 0) are SPEC-derived and verified on the
  teaching core; the references answer them differently where the spec allows or where they deviate
  (recorded in `cpu-su-prep/ref-run3`), so they are not reference gates.
