# CPU-SV39 — implementation report (serial Sv39 walk, no TLB)

Claude, 2026-09-18. Delegation `codex-cpu-sv39-implementation` (acked). Deliverables: `DESIGN.md` (written
first, with the test table), this report, the RTL diffs (`tcpu_csr.pre-sv39-to-sv39.diff` 36 lines,
`tcpu_core.pre-sv39-to-sv39.diff` 143 lines, and the new `rtl/tcpu_ptw.v`), `scripts/` (build, core gate,
M2-3 copy-runner, SoC gate, reference comparison, SU copies), the run directories below, `HASHES.txt` /
`HASHES-VERIFY.txt`. No Rocket/board artefact, boot software or default configuration changed; nothing
synthesised. No A, PMP or TLB.

## 1. What was built (details in `DESIGN.md`)

* `rtl/tcpu_ptw.v`: the walker. Canonical check, three levels of 8-byte physical PTE reads over the single
  port, the spec's validity/leaf/superpage/permission/A-D rules with software-managed A/D (no PTE is ever
  written), page faults 12/13/15 and access faults 1/5/7 (PTE address or PA beyond the 32-bit physical
  space, or a PTE read answered with a bus error), the PA assembled per level.
* `rtl/tcpu_csr.v`: `satp` real (MODE 0/8, the whole write ignored for other modes, ASIDLEN 0, all 44 PPN
  bits stored and read back); SUM writable; the walker's inputs exported.
* `rtl/tcpu_core.v`: the request outputs are muxed between the core and the walker; one new state
  `S_XLATE` used for the first parcel, the second parcel (translated on its own) and data; the frozen
  order kept (misaligned on the VA before translation, the Bare range check for untranslated accesses);
  an M fetch is never translated, data uses `MPRV ? MPP : priv`; a store that faults never reaches the bus;
  interrupts still only at `S_IF_REQ`, so a walk is never interrupted.
* Testbench: injection point 11 (a PTE read outstanding), reset family `ptw`, state name `XLATE`.

## 2. Gates

| Gate | Entry point | Run | Result |
|---|---|---|---|
| Core: sv01–sv06 × {min, fixed-backpressure, seeded-random}; exit 0, no protocol errors, `priv = M` and `satp = 0` at exit from the real CSR port; commit records byte-identical across profiles (all six are deterministic: no CLINT timing) | `scripts/run-cpu-sv39.sh` | `core-run2/` | `CPU_SV39_DONE fails=0`; records 495 / 376 / 1205 / 1670 / 557 / 683 identical |
| Core: the faulting instructions of sv03 never retired (commit counts of the exported labels from the trace: the RO store, the U-page load, the S-page load/store from U, the MPRV load — 0; the jalr whose *target* faults — 1) | same | `core-run2/logs/sv03-noretire.log` | all `COMMIT COUNT OK` |
| Core: an interrupt raised while a PTE read is outstanding (sv07, injection point 11): the walk completes, the load retires with its value, the interrupt is taken once at the next boundary with MPP = S; `enabled=1`, `outstanding=1` at the fire | same | `core-run2/logs/sv07-irq-ptw.log` | `CHAIN OK`, `FIRE STATE OK: XLATE`, `outstanding=1 priv=1` at the fire |
| Core: a core-only reset during a walk (sv02, `+core-reset-at-op=ptw`, three profiles): no commit before the reset vector, the interrupted instruction retires once on the re-run, the bridge model discards the stale PTE answer where one was due | same | `core-run2/logs/sv02-reset-ptw-*.log` | `CORE-RESET OK` ×3 (those three landings had no answer due); the sweep below exercises the discard |
| Core: named negatives — `FAULT_PTW_NO_PERM` rejected by sv03 check 5 (an execute-only page became readable without MXR; the read-only store still faults on D = 0), `FAULT_IF2_NO_XLATE` by sv05 check 1 (the straddler's second half came from the physically adjacent page instead of the mapped one), `FAULT_PPN_TRUNC` by sv04 check 8 (a leaf onto PA 0x1_8000_0000 read DRAM instead of faulting); the RV64I control passes on all three | same | `core-run2/` | exits 5 / 1 / 8, controls 0 |
| Core: the CPU-SU tests on the Sv39 core, three profiles — su08/su09/su11 as copies with recorded diffs (satp stores MODE 8; SUM in the read-backs; SUM writable), the rest unchanged | same | `core-run2/su-copies/*.diff` | all 33 runs exit 0 |
| Core: reset sweep — a core-only reset at each of the first 12 walk cycles under the fixed and the random profile (24 runs on the `core-run2` simulators): every run `CORE-RESET OK`, 12 of them with a stale PTE answer discarded by the bridge model | `scripts/run-reset-sweep.sh` | `reset-sweep1/` | `RESET_SWEEP_DONE fails=0` |
| Regression: the accepted M2-3 suite on the Sv39 core (copies as for CPU-SU plus the walker in every build and SUM in c02_warl's read-back) | `scripts/run-m23-with-sv39.sh` | `m23-run1/` | `M2_3_DONE fails=0` (attempt 2; attempt 1 was a Verilator thread-pool internal error, retried, not scored) |
| CPU-C entry point on the Sv39 core (`MISA`/`M23` hooks) | `cpu-c/scripts/run-cpu-c.sh` | `c-gate-run1/` | `CPU_C_DONE fails=0` (incl. `M23_WITH_SV39_DONE attempt=1`) |
| SoC: the R-BOOT generated RTL (unchanged) re-verilated with the Sv39 core; the four M3 ELFs 4/4; boot09/boot10 misa copies; the original `hello.riscv`; su01/su05/su06 with the real CLINT; **boot11**: S-mode Sv39 fetch through the identity map, data through an alias page checked physically from M, a delegated load page fault handled in S, `M3-SV39-OK` over HTIF | `scripts/run-soc-sv39.sh` | `soc-run1/` | `SOC_SV39_DONE fails=0`; boot11 `HOSTDONE exit_code=0`, 48215 cycles, `check-m3` with 2 sync traps (the page fault and the S ecall) |
| References: the same six ELFs on the Rocket model (unreset state zeroed, as established in CPU-SU) and qemu spike | `scripts/reference-run.sh` | `ref-run1/` (build1), `ref-run2/` (build2: sv04's high PPN moved to 0x1_8000_0000) | sv01/02/03/05/06: 0/0 on both; sv04 recorded: Rocket exits 103 (its priv-1.10 PTW ignores the reserved high bits: case 3 does not fault, so the tval check after it sees the previous fault), qemu 105 (it sets A/D in hardware, so case A = 0 does not fault) — both configuration differences named in the design |

The identity pass on both references matters: the page tables the tests build, the alias, the straddling
instruction across non-contiguous pages, the permission matrix, SUM/MXR/MPRV, the remap/SFENCE/satp
switch are all interpreted the same way by two independent implementations and by this walker.


## 2b. The non-leaf reserved-bit fix (Codex review, `codex-cpu-sv39-nonleaf-fix`)

Codex's independent PTW test (`codex-review/nonleaf.cpp`) showed a non-leaf PTE with U, A or D set was
descended instead of faulting — DESIGN §3 step 4 had even said "ignored". The v20240411 rule (§10.3.1:
reserved on a non-leaf; §10.3.4 step 3: a set reserved bit is a page fault of the access's class) is now
in the walker (`tcpu_ptw.v`, one condition: `level == 0 || pte_u || pte_a || pte_d` on the non-leaf branch;
G and RSW are untouched, leaf U/A/D unchanged), the DESIGN text is corrected, and a permanent test exists:

* `tests/sv09_nonleaf.S`: U, A, D each alone × the root pointer (level 2) and the last-table pointer (level
  1) × load / store / fetch = 18 faults with cause 13/15/12, `tval` = the VA, `epc` = the instruction (the
  fetch case: the target), the faulting store leaves the page untouched (checked from M), G/RSW on the same
  pointers and a normal leaf as controls; the runner checks from the commit trace that the 18 faulting
  accesses never retired (`nl_ld`/`nl_st` 0 times, `nl_j` 6 — the jalr is fine, its target's fetch faults).
* The same ELF on the walker **before** the fix (`old-rtl/tcpu_ptw.v`, hashed, built as `obj_oldptw`)
  fails at its first case, check 11 (U on the root pointer did not fault; the walk descended), while an
  ordinary program (sv02) still passes on it — the new test fails for the named defect, not by timeout.

Everything was re-run into new directories with the fixed walker; the earlier runs are kept:

| Gate | Run | Result |
|---|---|---|
| Core (sv01–sv06 + sv09 × 3 profiles, identical records; sv03/sv09 retire counts; sv07 IRQ during a PTE read; reset during a walk; the three named negatives + controls; the old-walker proof; the CPU-SU tests with the three copies) | `core-run4/` | `CPU_SV39_DONE fails=0`; sv09 records 2220 identical; `sv09-on-old-walker exit=11`, `sv02-on-old-walker exit=0` |
| Reset sweep on the `core-run4` simulators (24 runs) | `reset-sweep3/` | `RESET_SWEEP_DONE fails=0`, 12 with a stale PTE answer discarded (`reset-sweep2/` on the `core-run3` simulators: the same) |
| M2-3 regression copy | `m23-run2/` | `M2_3_DONE fails=0` (attempt 1) |
| CPU-C entry point | `c-gate-run2/` | `CPU_C_DONE fails=0` |
| SoC (4 M3, boot09/10 copies, hello, su01/su05/su06 real CLINT, boot11) | `soc-run2/` | `SOC_SV39_DONE fails=0` |
| References (build3, with sv09) | `ref-run3/` | sv01/02/03/05/06 0/0; sv04 recorded as before; **sv09: qemu 0** (it implements the v20240411 rule), Rocket 11 (its priv-1.10 PTW descends through non-leaf U/A/D — the very behaviour the fix removes) |

## 3. Runs that failed, kept

* `core-run1/` (fails=3), all on the test/runner side: the MXR re-read is a separate instruction from the
  labelled execute-only load (its retire count is 0, not 1); the permission-bypass negative is caught by
  sv03 check 5 (the read-only store still faults on D = 0, so check 2 passes even with permissions
  skipped); the truncation negative needs a high PPN that would alias into real memory once truncated
  (0x1_8000_0000; the first choice 0x1_0000_0000 aliased into nothing and faulted anyway).
* Development iterations before the delivery tree: sv01 first let S execute U-marked identity pages (S
  never executes a U page — the U alias gigapage was introduced); sv03 converted an already-aliased
  address twice, and its MPRV = 1 / MPP = U case showed that an M handler running with MPRV = 1 has its own
  loads translated as U (the test now enters M through a stub that clears MPRV first, as firmware does);
  sv04/sv05/sv06 expectation corrections (trap counts, an `sh` offset, a non-delegated access fault).
* `core-run3/`: stopped at the old-walker build because the runner reused the name `SV` for the test list and
  the path (a runner bug, fixed; its `core-run3/obj_*` simulators are complete and `reset-sweep2/` used them).
* `m23-run1/` attempt 1: Verilator "attempted to destroy locked Thread Pool" — infrastructure, retried.

## 4. What is not claimed

* No TLB or translation cache (every access pays the full walk: three PTE reads); no A/D hardware update
  (a PTE with A = 0, or D = 0 on a store, faults — as this SoC's Rocket, unlike qemu's default).
* No PMP, no A extension, no `time`, no Svnapot/Svpbmt/Svadu; no vectored xtvec; no S-level PLIC context.
* xv6 is not booted here: it needs the A extension (spinlocks) and the PMP start-up lines (D-6), both
  separate tasks; the SoC program `boot11` shows the S-mode Sv39 path an OS uses (translated fetch, an
  alias, a delegated page fault) on the real SoC.
* Nothing about performance; nothing on the board.
