# PIPE-P0 TESTPLAN — architectural-equivalence verification of the pipeline core

Principle: the oracle is the **architectural commit stream** (pc, raw insn, len, rd, rd value), the trap stream (interrupt, cause,
epc, tval) and the **memory effect stream** (every port request's address/write/size/wdata/wmask in order, and the final memory
image) — never cycle-by-cycle equality with the multicycle core. The accepted multicycle core is the reference for every program
that has no spec-derived self-check. Every random test carries its seed in its output name; every run is bounded by cycles and
wall time; every negative is a real defect knob in the RTL, not a mutated log.

## 0. What is reused (exists in `mc-v1-dual`)
| asset | anchor | use |
|---|---|---|
| standalone core harness: memory model with fixed / back-pressure / seeded-random ready & response delays, protocol monitors (withdrawn request, same-cycle answer, load carrying wdata, unique response), interrupt injector by microarchitectural moment, external writer for atomics, ELF backdoor, commit outputs | `tests/cpu/tb/tcpu_harness.v:1-110` (parameters `READY_DELAY`, `RESP_DELAY`, `RANDOM`, `SEED`, `IRQ_POINT`…) | P1/P2 core level; the multicycle core runs in the same harness as the reference |
| stage suites, RTL directory as a parameter | `experiments/multicore/archive/m1/tests/core-suites/run-cpu-{c,m,su,sv39,a}-rtl.sh` (e.g. `run-cpu-c-rtl.sh:4-5,44`) | P2: point at `rtl/cpu/pipeline` (with the shared files) |
| M2-3 regression (c01–c10, i01–i09, j01–j02; CSR forms/WARL/counters/targets/handler faults/ecall/priority/masking/mip level/wfi/mret re-entry/epc redirect/sync-first/store-exact/enabled-boundary/store-once) | `tests/cpu/tests2/*.S`, runner `cpu-c/scripts/run-m23-with-c.sh` and its per-stage copies | P1 (subset that needs no M/C/S) and P2 (all) |
| stage programs: M `m01_muldiv m02_irq_muldiv boot09`; C `c01_compressed c02_boundary boot10`; SU `su01…su11`; SV39 `sv01…sv07 sv09 boot11`; A `a01_matrix a02_lrsc a03_except a04_irq a05_misa_probe boot12` | `experiments/teaching-cpu/cpu-*/tests` | P2 |
| SoC-level: RD2 harness event log `EV REQ/RESP/COMMIT/TRAP/IRQLEVEL` per hart, `busy`, restart injector, per-hart counters | `soc/scala/teaching/RD2Soc.scala:361-400,700-750`; checkers `archive/m2a/tests/score2.py`, `archive/m2b/tests/dual_check.py`, `archive/m3/tests/m3_check.py`, `archive/perf/tests/perf_check.py` | P2 (single) / P4 (dual) |
| boot/xv6 flow: `rd2-build-sim-fast.sh`, M3/M4 `run-xv6.sh` + profiles, M2b dual programs (6 gates + drain), IPS probes `perf02/03/04/06` + `compare-probes.py` / `roi-compare.py` | `tools/xv6-boot/scripts`, `archive/m3`, `archive/m2b/progs`, `archive/m1/tests` | P2/P3/P4 |
| I-cache / TLB unit benches (21 + tlb checks) | `IPS-campaign/tests` (in `worktrees/ips-cache`) | P2 regression of the shared units after the 2nd TLB port |
| lint: no SoC reader of implementation state | `archive/m1/tests/lint-stable-obs.sh` | every phase |
| board procedure (M5 / perf tooling, production `ips-*.sh`) | `archive/m5-board`, `archive/perf/board` | P3/P4, separate authorisation |

**Known baseline (stated so it cannot silently change):** the project never ran the official `riscv-tests` suite (planned in
`m2-prep/TEST_PLAN.md:44`, not done; Spike not built); the ISA regression baseline is the M2-3 suite + stage suites, all recorded
`fails=0` (`cpu-sv39/REPORT.md:36`, `m2-3/REPORT.md:54`). `ext03_a` does not complete in the *simulation* harness (`ips-install.sh`
step 5 note; a board gate only). A pipeline run must report exactly these baselines, and any new "fails=0" must name the suite it
came from.

## 1. New, small, and why
| new asset | why the existing one is not enough |
|---|---|
| `commit-diff.py`: compares two commit/trap/request streams (multicycle vs pipeline) after normalising cycle numbers; reports the first divergence with 8 lines of context on each side | today's runners compare a core's records across *its own* delay profiles; nothing compares two cores |
| `gen-hazard.py`: seeded random RV64I(+M in P2) sequence generator with hazard templates (back-to-back RAW on rs1/rs2/both, load-use at distance 0/1/2, branch after load, store→load same address, x0 as rd/rs, JALR chains, 2-byte/4-byte mixes in P2), self-terminating via `tohost`; no self-check — the oracle is the multicycle run | existing programs are directed; hazards need density |
| pipeline fault knobs (in `rtl/cpu/pipeline/tcpu_core.v`, each one real defect): `FAULT_NO_FWD_EXMEM`, `FAULT_NO_FWD_MEMWB`, `FAULT_NO_WB_BYPASS`, `FAULT_NO_LOADUSE_STALL`, `FAULT_FLUSH_KEEPS_ID` (redirect leaves the ID instruction), `FAULT_STORE_UNDER_OLDER_TRAP` (§3.3 check skipped), `FAULT_STALE_RESP_ACCEPTED` (epoch check skipped), `FAULT_IRQ_AT_EX` (interrupt attached to an instruction past ID), `FAULT_CSR_NO_DRAIN`, `FAULT_SPEC_MMIO_FETCH`, `FAULT_X0_FWD` | the negative for every rule in CONTRACT §2–§5; each must be caught by a named positive test below |
| harness additions (parameters only): `IRQ_POINT` 13 = "a fetch request outstanding while a redirect is resolving", 14 = "MEM response outstanding while WB traps"; a `RESP_ERR_AT_ADDR` (already `TAIL_ERR`/`FETCH_ERR_ADDR` exist) for data | the multicycle moments 1–12 (`tcpu_harness.v:42-51`) do not name pipeline-only overlaps |

## 2. Assertions and monitors (every run, both cores)
Existing in the harness/bridge: valid irrevocable (`REQ_WITHDRAW` self-test), no answer in the request cycle (`MEM_SAME_CYCLE`),
load with wdata (`LOAD_WDATA_LEAK`), unique/matched response (`RD2BridgeV2.scala:77,157-158`), one outstanding per hart (bridge
`sIdle` gate). Added for the pipeline: (a) at most one of commit/trap per cycle; (b) `commit_pc` sequence = program order (each
commit's pc equals the previous npc as computed from the commit record: pc+len, branch target, xepc, trap vector); (c) no request
issued while WB holds a trap or an interrupt-marked instruction (§3.3) — checked from the event log: a `REQ` with `fetch=0` may not
occur in the same cycle as a `TRAP`, and no `REQ fetch=0` whose instruction never commits may exist unless it errors; (d) a
response whose epoch is stale is never followed by a commit that consumed its data — checked as "no commit's insn came from a
discarded fetch" via the harness's stale-response marker; (e) `mcycle` monotonic, `minstret` = number of commits (from `c04/d08`
already); (f) timeouts: every core run `+max-cycles` bounded and the harness's drain limit (`cpu_boot_main.cpp:28`).

## 3. P1 — RV64I + minimal traps, standalone harness
| id | case | oracle | negative caught by |
|---|---|---|---|
| P1.1 | `t01–t03`, `d01–d08` (existing RV64I directed) × {min, fixed back-pressure (READY_DELAY 3, RESP_DELAY 4), random seeds 1..5} | commit stream = multicycle's; final memory image equal | — |
| P1.2 | `gen-hazard.py` seeds 1..50, 2k instructions each, 3 profiles | commit-diff vs multicycle | `FAULT_NO_FWD_EXMEM`, `FAULT_NO_FWD_MEMWB`, `FAULT_NO_WB_BYPASS`, `FAULT_NO_LOADUSE_STALL`, `FAULT_X0_FWD` each fail ≥ 1 seed |
| P1.3 | branch flush: taken branch with a store as the next sequential instruction (`j02`-style), JALR chain into a store | the store never appears in the request stream; commit stream equal | `FAULT_FLUSH_KEEPS_ID` |
| P1.4 | same-cycle exception + interrupt: `IRQ_POINT` 5/7 on an instruction that faults (illegal / misaligned load), and at point 14 | exactly one trap, interrupt first if it was pending at ID, epc/cause/tval per §3.2 (`i08_sync_first` + new variants) | `FAULT_IRQ_AT_EX` |
| P1.5 | load-use + back-pressure: RESP_DELAY 1..8 sweep with a load-use chain | equal commits; CPI grows by exactly the delay | `FAULT_NO_LOADUSE_STALL` |
| P1.6 | unreturned request meets flush: a redirect/trap while a fetch request is outstanding (`IRQ_POINT` 13; `FETCH_ERR_ADDR` on the wrong-path fetch) | the stale response (and its error) is discarded; no trap from the wrong path; next commit correct | `FAULT_STALE_RESP_ACCEPTED` |
| P1.7 | store under an older trap: a store immediately after `ecall`/faulting load (`i09_store_exact`, `c07/c08`) | no request for the store | `FAULT_STORE_UNDER_OLDER_TRAP` |
| P1.8 | error paths: fetch access fault, load/store access fault (`TAIL_ERR`, `FETCH_ERR_AFTER`) | precise cause/tval/epc; no register/CSR change | — |
| P1.9 | CPI gate: `perf02 bare_alu` ROI ≤ 2.0, `bare_load` ≤ 4.5 in the RESP_DELAY=3 profile (CONTRACT §7) | ROI cycle counts from the commit stream | — |
| P1.10 | lint-stable-obs; `dbg_impl` first-cycle assert both ways (config multicycle vs pipeline file list) | pass / refuse | planted reference; swapped file list |

## 4. P2 — full ISA set, single core, then xv6
| id | case | oracle |
|---|---|---|
| P2.1 | M: `m01 m02 boot09`, long division (DIV by 1, by 0, INT_MIN/-1, 64-cycle chains with a pending interrupt: `m02`) | commit-diff; interrupt taken after the instruction (§2.4) |
| P2.2 | C: `c01 c02 boot10` + straddle (`c02_boundary`, `sv05` in P2.5): page-boundary 32-bit instruction whose second parcel faults / is on another page | epc = pc, tval = pc+2; `FETCH_ERR_ADDR` at either parcel |
| P2.3 | CSR / traps / S/U: `c01–c10`, `i01–i09`, `j01–j02`, `su01–su11`: CSR RMW atomicity vs `mcycle` (c04/d07), enables changing (i03/i06), WFI, delegation, MPRV | commit-diff + the suites' own checks; `FAULT_CSR_NO_DRAIN` caught by `i06/j01` |
| P2.4 | Sv39: `sv01–sv07 sv09 boot11` + IPS `tlb01_sfence` cases; new: fetch-side and data-side TLB miss in the same cycle (walker arbitration), speculative fetch across a page boundary whose PTE is in MMIO space (must wait), `sfence` with a refill in flight | walks serialised, one request outstanding; fault ownership; `FAULT_SPEC_MMIO_FETCH` caught |
| P2.5 | fence.i vs refill: self-modifying probe from STAGE3 (`store; fence.i; execute`) with the store timed inside the refill window | the new instruction executes; I-cache bench still 21/21 |
| P2.6 | A: `a01–a05 boot12` in the harness (model) and the SoC atomic subset (`archive/m1/tests/atomic-soc-subset.sh`); trap while LR in flight impossible by construction — asserted | commit-diff; backend traces unchanged |
| P2.7 | SoC boot: the 4 M3 ELFs, boot09–12, hello; R-BOOT/RD2 drain scenarios (`archive/m2a` regress subset for N=1) | existing checkers 0 findings |
| P2.8 | single-core xv6 (validation kernel + deploy kernel) via `run-xv6.sh` profiles `m3dual-a`(n1), `m4smoke`, `usertests exectest` | `m3_check.py --n1` PASS; boot-to-shell cycle count reported next to the multicycle's (M3 `single-a`) |
| P2.9 | throughput evidence: `perf02/03/04/06` ROIs via `rd2-probes.sh` + `compare-probes.py` against the cache-stage numbers | reported; P1.9 gates re-checked in the SoC memory profile |

## 5. P3 — 40 MHz implementation and board (board part needs separate authorisation)
P3.1 offline: `RD2BoardConfig` with `CORE_IMPL=pipeline` through the accepted `build-atomic.sh`/`build-board.sh` chain (hierarchy audit
extended to check the pipeline file hash by CORE_IMPL), `check-impl-reports.py` PASS at 40 MHz or the timing report with the failing
path named; utilisation next to 14,554 LUT (multicycle cache stage). P3.2 board (after the user's hand-back and authorisation, two cold
cycles, ends in the user's configuration): 8 single-core gates + IPS probes (existing `ips-install.sh` pattern with a `pipeline`
variant), then `perf-board` and `perf02` ROIs; report IPS and fixed-work T1 next to the multicycle's 26.588 s / 40.548 s (perf
RESULTS.md); state the MUL caveat of CONTRACT §7.

## 6. P4 — dual pipeline
`NUM_CORES=2, CORE_IMPL=pipeline`: M2b six gates + drain (`dual_check.py`), M3 dual xv6 (`m3_check.py`), fixed-work S2 with the same
perf tooling; the backend/bridge untouched, so `score2.py` scenarios re-run unchanged as regression.

## 7. Exit criteria per phase
A phase passes when every row's oracle holds under all three delay profiles, every named negative is caught by the named positive,
the lint passes, all runs were bounded, and the report lists the baselines of §0 verbatim (no suite reported green that was not run).
