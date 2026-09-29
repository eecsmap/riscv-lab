# PIPE-P2b REPORT — privilege, Sv39 and A in the pipeline core, the SoC selection, single-core xv6 in simulation

Task `codex-pipe-p2b-single-xv6`. Worktree `worktrees/pipe-single`, branch `pipe-single`, local commits only (no
push, no tag, no Vivado, no board). Shared and multicycle RTL are unchanged: section G of every P2b run compares all
13 compiled shared/multicycle files byte for byte with tag `mc-v1-dual`.

| commit | checkpoint |
|---|---|
| `affc3a3` | 1: M/S/U privilege through the shared CSR unit (`PIPE_EXT_SU`) |
| `f5c2add` | 2: integrated Sv39 — pipeline TLB `tcpu_tlb2`, the unchanged walker through `tcpu_ptw_wrap`, PTE owner metadata |
| `35c05eb` | 3: A (LR/SC/AMO) through the existing req/resp atomic backend (`MISA_A=1`) |
| `79f21e4` | 4: Scala/SoC explicit pipeline selection, `SOURCES.pipe`, generated-RTL identity of every existing configuration |
| (this commit) | 5: single-core xv6 through the RD2 simulator (gates `m4smoke`, `perf-short`), SoC boot / R-BOOT / drain on the pipeline, the hart wrapper's PTE classification for the SoC busy rule; this report |

Evidence directories are under `runs/` (not in git, hashes in `results/`); every number below is copied from a file in
`results/` (`results/SHA256SUMS` lists them). Manifests: sources compiled per simulator set `results/cp*-src-sims-*.sha256`
and `results/cp*-rd2sim-*-inputs.sha256`, `rtl/cpu/pipeline/SOURCES.pipe`; test ELFs `results/cp*-elf-run-*.sha256`,
`results/cp5-soc-2-prog.sha256`; generated SoC Verilog `results/cp4-gen-2-generated.sha256`,
`results/cp5-gen-3-pipe-generated.sha256`; xv6 kernel, disk and simulator hashes in each `results/cp5-xv6-*.txt`.

**Status: P2b complete in simulation** — all five checkpoints pass their gates. Not claimed: anything on the board,
timing, area or frequency.

## 1. Build identity
`tcpu_core_pipe` has the same 61 ports and parameter names as `tcpu_core`. Extensions are parameters, each 0 or 1:
`PIPE_EXT_M`, `PIPE_EXT_C` (P2a), `PIPE_EXT_SU` (S/U **and** Sv39, as in the reference: the shared CSR unit accepts an
Sv39 `satp` whenever S exists), `MISA_A`. Defaults are the accepted P1 configuration. A mechanism that is asked for
and not built is refused at elaboration by a missing-module error that names it; `results/cp3-identity-sims-4.txt`
(11 checks, all failing for their named reason) covers: SU, Sv39 and A injections without their extension,
`PIPE_EXT_SU=2`, `MISA_A=2`, the C decoder or the TLB source missing, `TLB_ENTRIES=4` (the TLB is 8 entries as the reference), knob 22
without SU, `PIPE_FAULT=24`, and the define with the multicycle list. The P1 identity check moved from `MISA_A=1`
(now legal) to `MISA_A=2`.

## 2. Checkpoint 1 — privilege (`affc3a3`)
As the reference core: TSR = TVM = TW = 0, so SRET and SFENCE.VMA are legal in S and M and illegal in U, MRET needs M,
WFI is legal everywhere. SRET and SFENCE.VMA serialise (freeze, drain, flush, refetch). misa gains S and U.

| section | result (`results/cp2-run-3-*.txt`, identical in run-4) |
|---|---|
| SA: CPU-SU su01–su11 × 3 timings | pipeline exit = reference exit everywhere; the reference keeps its recorded baseline (su08 1, su09 8, su11 24 = "SU 9"), and the pipeline fails them identically |
| SB: differential | 24/24 `DIFF_OK` (strict on the deterministic programs; equality only for the baseline three) |
| SC: `p2b_irq_priv.S` — an M interrupt at every position across M → S → U → M (replaces su12's state-aimed injection) | 69/69 self-checks PASS, 69/69 aligned and identical; without the interrupt the test fails its check 2 |
| SD: CPU-SU injections (no delegation, S interrupt in M, SRET keeps SPP) on both cores | 6/6 caught as the first failure signal; 6/6 controls pass |

## 3. Checkpoint 2 — Sv39 (`f5c2add`)
* `tcpu_tlb2` (pipeline-owned) is the reference policy with two lookup ports (F1 fetch, MEM data): leaf PTE bits
  cached (never a verdict), round-robin, full flush on every sfence.vma and satp write, only a successful walk fills,
  flush wins over fill.
* Fetch translates in F1 per 8-byte word; a miss walks, speculatively unless nothing older is in flight — then the
  wrapper forwards only cacheable PTE addresses. Data translates in MEM's first cycle (MPRV honoured); a data miss
  walks only when MEM is the oldest instruction and preempts a fetch walk. Every translation used goes through the
  shared `tcpu_permcheck`.
* The unchanged `tcpu_ptw` runs inside `tcpu_ptw_wrap` (abort by reset, killed PTE transactions drain, P2a unit
  bench). The drain waits for the walker.
* **Owner metadata:** a PTE transaction is IF-PTE (13) or D-PTE (14) on `dbg_state`; the harness traces it as `PTE`,
  never as a data request, so the differential compares data requests only and never has to guess.

| section | result (`results/cp2-run-3-*.txt`, identical in run-4) |
|---|---|
| VA: CPU-SV39 sv01–06, sv09 × 3 | all exit 0 on both cores; the faulting instructions of sv03 (7 checks) and sv09 (3) never retire |
| VB: differential incl. 20 generated programs whose body runs in S under Sv39 (4 KiB-mapped code, 12-page alias, random sfence.vma) and `p2b_walk_preempt` | 84/84 `DIFF_OK` |
| VC: `p2b_irq_walk.S` — an interrupt at **every cycle** of an S-mode block of data walks (replaces sv07) | 445/445 PASS and aligned; 121 raises landed while a PTE read was outstanding |
| VD: knobs 21 TLB_NO_FLUSH, 22 TLB_HIT_NO_PERM, 23 DRAIN_NO_WALKER; CPU-SV39 injections on both cores | all caught as named; `FAULT_IF2_NO_XLATE` on the pipeline diverges first at the straddler 0x30002ffe; 9/9 controls pass |
| VE coverage (summed over VB) | 1,284 data walks, 513 fetch walks, 18 fetch walks preempted by data, 24 aborted, 24 killed PTE transactions, 498 TLB flushes |

`FAULT_PTW_NO_PERM` (the walker skips its leaf checks) is **not observable on the pipeline by construction**: the
pipeline re-checks every translation with `tcpu_permcheck`; knob 22 removes that check and is caught. The verdict
records this as a note, not a pass.

## 4. Checkpoint 3 — A (`35c05eb`)
* An A instruction is a MEM-stage memory operation issued on the port with the V2 side-band (`req_amo` = AmoOp code,
  `req_lrsc` = 1 LR / 2 SC). The backend performs the read-modify-write and holds the reservation; the core asks and
  waits.
* **Oldest only, no speculative writes, no early retirement.** The request is allocated only when nothing older can
  still trap (`PIPE ASSERT oldest-issue` checks it every time); the instruction retires only after its response (the
  harness's early-retire monitor and `PIPE ASSERT data-response` watch it). An interrupt that arrives meanwhile is
  taken after it.
* Results: LR and AMOs write the old value, `.W` sign-extended; SC writes the backend's fail bit. Address = rs1, no
  offset; misaligned → load (LR) / store-AMO (SC, AMO) misaligned; translation access type LR load, SC store,
  AMO both (as the reference).
* The reservation is dropped on reset and on every trap (`resv_clear`), as the reference.
* **aq/rl** are accepted and have no effect, and none is needed: memory is serialized — one hart, at most one
  outstanding request, an atomic issued only as the oldest instruction and retired only after its response, a
  serial backend — so every access is performed in program order and globally ordered before the next one begins.
  That satisfies acquire, release and both. This is an argument for this memory system only; it does not hold for
  a second hart, a store buffer or more than one outstanding request (P4).

| section | result (`results/cp3-run-4-*.txt`) |
|---|---|
| AA: CPU-A tests scored by the unchanged CPU-A checkers, both cores | a01 138/138 cases at t0/t1/t2; a02 13 cases at t0/t1/t2 and under the external race (EXT_POINT=2 writes the reservation word between LR and SC: `ext_races=1`); a03 21 traps at t0/t1/t2; the runner's exit-code and completion self-tests refuse |
| AB: differential | 10/10 `DIFF_OK` |
| AC: `p2b_irq_amo.S` — an interrupt at **every cycle** of a block of AMOs (.D and .W) and an LR/SC loop (replaces a04's state-aimed injection); each AMO must be performed exactly once (5 watched writes) | 69/69 PASS and aligned; 28 raises landed inside an atomic access; without the interrupt the test fails its check 8 |
| AD: the five CPU-A injections on both cores, judged by `ajudge.py` (the named check must be the **first** failure) | 10/10 caught: W_NOSEXT and AMO_AS_LOAD by the a01 checker, SC_RESULT ("SC with no LR") and NO_RESV_CLEAR ("a trap between the LR and the SC drops it") by the a02 checker, EARLY_RETIRE by the harness monitor `A_OBS_FAIL early-retire`; 10/10 controls pass |

Guards: `selftest-p2b.py` mutates one line of every section summary (34 mutants, each refused for its own section,
plus a missing file) and feeds `ajudge.py` 9 synthetic runs (`results/cp3-selftest-run-4.txt`).

Regressions on the same tree (`results/cp3-regressions.txt`): P2b checkpoint 1/2 sections identical to run-3; P2a
run-7 PASS, identical to run-6; P1 run-11 PASS, identical to run-10 (and so to the accepted run-5).

## 5. Checkpoint 4 — explicit selection in the SoC (`79f21e4`)
* `TcpuCoreBlackBox(impl)`: `"multicycle"` → `tcpu_core` with exactly the parameter map it always had;
  `"pipeline"` → `desiredName = tcpu_core_pipe` plus `PIPE_EXT_M/C/SU = 1`; anything else throws with the value.
  `TeachingCpuV2`, `TeachingHart` pass it; `RD2Params.coreImpl` selects it (default `multicycle`).
* Refused at elaboration, message with the value (`results/cp4-gen-2-refusals.txt`): unknown CORE_IMPL
  (`P2bUnsupportedImplConfig`), pipeline × 2 (`MC1UnsupportedPipelineConfig`, redefined from pipeline × 1 which now
  exists; name kept for the MC regressions), pipeline on the V1 path (`P2bUnsupportedPipeV1Config`); the existing
  NUM_CORES 4 and 0 refusals still refuse.
* New `RD2PipeXv6FastConfig` and `RD2PipeBootConfig`.
* **Old configurations unchanged** (`results/cp4-gen-2-judge.txt`): generated before (scala at `35c05eb`) and after
  from private commons: RD2AtomicXv6Fast, RD2DualXv6Fast, RD2AtomicBoot, RD2DualBoot, RD2Boot (V1 path),
  RD2AtomicBoard, RD2DualBoard (the last two as `RD2BoardTop`). Raw Verilog differs in 726–2,930 lines, all scala
  source locators (`// @[…]` and the TileLink monitors' `(connected at RD2Soc.scala:l:c)` strings); normalized, all
  seven are **identical**, with `tcpu_core` and no `tcpu_core_pipe`. The pipeline configurations instantiate
  `tcpu_core_pipe` once, with `MISA_A(1) PIPE_EXT_SU(1) PIPE_EXT_M(1) PIPE_EXT_C(1)`, and never `tcpu_core`.
  `selftest-judge-gen.sh` (7 mutants: a changed statement, a changed assertion string, a pipeline in an old
  configuration, the multicycle core in a pipeline configuration, A off, a refusal that elaborated, a missing
  output) — all refused.
* **No -I fallback.** `rtl/cpu/pipeline/SOURCES.pipe` lists the pipeline's 11 source files and its include.
  `build-rd2-pipe-sim.sh` copies exactly those into the build and puts only an include-only directory on the search
  path; it refuses Verilog that instantiates `tcpu_core`. Negatives (`results/cp4-rd2sim-1.txt`): the multicycle
  configuration's Verilog is refused; a manifest without `tcpu_tlb2.v` fails with `Cannot find file containing
  module: 'tcpu_tlb2'` although the file sits in the RTL directory.
* Recorded honestly: gen-1 failed before and after alike (the boot ROM is read through `../common` beside the
  private common; M4 had that symlink); the first gen-2 judgement failed the three trace-on configurations on the
  monitors' embedded locator, which the judge now normalizes (re-run on the stored Verilog, no regeneration).

## 6. Checkpoint 5 — single-core xv6 in the RD2 simulator
**Simulator.** `RD2PipeXv6FastConfig` (the multicycle `RD2AtomicXv6FastConfig` with `coreImpl = pipeline`: same
hart wrapper, V2 bridge, serial atomic backend, CLINT/PLIC, block device, drain; TileLink monitors off, as the
multicycle xv6 configuration) generated in `runs/gen-3`, built by `build-rd2-pipe-sim.sh` from `SOURCES.pipe`
(`runs/rd2sim-2`, simulator `3b993e80…`; inputs `results/cp5-rd2sim-2-inputs.sha256`), with the same C++ main,
serial and block-device models and flags as the accepted single-core simulator (`multicore/m3/runs/sim-single`).

**Reference.** `m3/runs/sim-single` (`d7ecb822…`): its core sources equal tag `mc-v1-dual` file for file, and its
SoC Verilog is normalized-identical to today's `RD2AtomicXv6FastConfig` (gen-2/gen-3 "after"). The multicycle
perf-short reference is the accepted `perf/runs/tb-single-short`, re-judged in a directory of symlinks
(`runs/xv6-perf-short-multi-ref`; the original is untouched); the multicycle m4smoke reference was run here on the
same inputs (`runs/xv6-m4smoke-multi-ref-1`).

**Gates**, each through the accepted runner with a fresh disk copy (`soc/run-xv6-p2b.sh`, which also refuses a
kernel or disk whose hash is not the named one and checks the runner recorded exactly those inputs):
* `m4smoke` (b0compute, m3par2, m3fs): `multicore/m4/tests/run-xv6.sh`, kernel `kernel-deploy-4` `1e4749c0…`, disk
  `fs-deploy.img` `d8e50269…`; judge `m4/tests/m3_check.py --n1` (production check-xv6 with `--require-commands`,
  per-hart evidence, console sanity, per-command semantics).
* `perf-short` (mtimetest, perfcompute 20000, perfarray 1): `multicore/perf/tests/run-xv6.sh`, measurement kernel
  `d713744a…`, disk `fs-perf.img` `d558e444…`; judges `m3_check.py --n1` (the unchanged M4 file, placed beside a link
  to the perf tools because M4's check-xv6 does not know this profile: `soc/perfjudge/`) and
  `perf/tests/perf_check.py --min-dmtime 1 --sizes compute=20000,array=1`.

| run (`results/cp5-*.txt`) | runner | judges | retired | traps | user-mode commits | cycles | cycles/retired | fixed work (mtime units = 100 cycles) |
|---|---|---|---|---|---|---|---|---|
| pipeline m4smoke (`xv6-m4smoke-pipe-2`) | XV6_RC=0, 6/6 stages, deliberate stop | PASS | 28,075,984 | 301 | 4,264,205 | 129,929,543 | 4.63 | — |
| multicycle m4smoke (`xv6-m4smoke-multi-ref-1`) | XV6_RC=0 | PASS | 28,870,226 | 465 | 4,280,107 | 348,475,997 | 12.07 | — |
| pipeline perf-short (`xv6-perf-short-pipe-2`) | XV6_RC=0 | PASS / PASS | 16,410,389 | 257 | 2,364,058 | 73,795,178 | 4.50 | compute 83,457; array 75,472 |
| multicycle perf-short (`tb-single-short`) | XV6_RC=0 | PASS / PASS | 17,048,484 | 347 | 2,380,398 | 201,977,719 | 11.85 | compute 167,357; array 262,904 |

* Outputs are identical between the cores: b0compute `5ADF55920BF7696`, m3par2 children `f6d983767e3c5638` /
  `01d86a21f972f3fa`, m3fs ok; the eight perf children's checksums; the same as the accepted M4/perf records.
* The fixed-work regions: compute 83,457 vs 167,357 mtime units (2.01× fewer cycles), array 75,472 vs 262,904
  (3.48×); `mtime()` read cost 63 vs 132 units; spin100k 79 vs 134 cycles/iteration. Whole-run totals (2.68× and
  2.74×) include the idle scheduler spinning while the runner types each command in wall-clock time, so they are
  not fixed work: two pipeline m4smoke runs differ by 0.2 % in total cycles with identical user-mode commits
  (`cp5-xv6-m4smoke-pipe-1.txt` vs `-2`). Simulation only; no board, frequency or area statement (P3).
* Wall time on this host: pipeline m4smoke 765 s, perf-short 440 s; multicycle 1,926 s and 1,180 s.

**Retirement association, busy/settle, reset-drain in the SoC.** The SoC counts a hart busy while a request is
offered or outstanding, and after a *data* response until the next commit or trap (`RD2Soc` `awaitingRetire`,
"a response with isFetch = 0"); the host's final settle and the event trace use it. The multicycle core may call its
PTE reads data (one instruction in flight: the next commit or trap is the walker's). On the pipeline that would let a
PTE read's response be "retired" by an unrelated older instruction. The hart wrapper therefore publishes, for the
pipeline only, `isFetch = dbg_req_is_fetch || dbg_state ∈ {13 IF-PTE, 14 D-PTE}` — the owner metadata the core-level
harness already uses, held by the walker wrapper through the response cycle (`TeachingCpuBlackBox.scala`,
`TeachingCpuV2`). A data request is issued only by the oldest instruction (asserted in the core), so after its
response the next commit or trap is exactly that instruction. Found after the first xv6 runs (gen-2 / rd2sim-1 /
`*-pipe-1`, kept as evidence); gen-3 changes exactly those three terms of the pipeline configurations
(`results/cp5-gen-2-to-3-pipe.diff`), every existing configuration is again normalized-identical
(`results/cp5-gen-3-judge.txt`), and both gates were re-run on the new simulator (the table). The reset-drain
itself is the bridge's: it holds the CPU in reset only after its own outstanding TileLink transaction has
completed — real outstanding work, and on this port at most one.

**SoC boot, restart and drain on the pipeline** (`soc/chain-cp5c.sh`, traced `RD2PipeBootConfig`, the accepted
checkers unchanged; `results/cp5-soc-2.txt`):
* S1, the CPU-A SoC programs exactly as `cpu-a/scripts/run-soc-a.sh` runs them on the atomic configuration (same
  ELFs, `results/cp5-soc-2-prog.sha256`): boot09 (M), boot10 (C), boot11 (S-mode Sv39), hello, boot12 (S-mode Sv39
  spinlock, LR/SC loop, AMOs) — `check-m3.py boot` and `check-axi.py` pass, no `PIPE ASSERT`; boot12's event score
  64 AMOs, 64 Get / 64 Put, 16 SC ok, 1 SC fail, 16 reservations, 0 fails.
* S2, the R-BOOT gates (`restart-boot/scripts/rboot-run.sh`: restarts with a read DMA / an accepted write DMA in
  flight, a queued unconsumed completion, three rounds, a stuck device, late recovery, the read-target negative and
  the counterexample): all pass, and the gate lines are identical to the multicycle's accepted `rboot-after.log`.
* S3, an R-BOOT restart during boot12's atomic phase (`check-drain.py`): the pipeline finishes boot12 at cycle
  46,788, so of the accepted restart points (chosen for the multicycle's timing) only 45,000 lands inside the run;
  50,000–60,000 are reported "not applicable" (the first run, soc-1, counted them as failures — no restart is
  asserted after the program ends; kept in `results/cp5-soc-1.txt`). Four more points inside the pipeline's own
  atomic phase (cycles 42,383–44,225): all five restarts landed with an atomic in flight, drained, and the rerun
  completed with every Get matched by its Put.
* Not covered by a negative control: the SoC checkers have no request-to-retirement association check, so the
  isFetch classification above is justified by construction (and by the core-level differential that already
  classifies PTE reads with the same metadata), not by a caught mutant.

## 7. Commands
```sh
P=experiments/pipeline/p2b
bash $P/scripts/build-p2b.sh $P/runs/sims-N             # 39 simulators + identity gate
bash $P/scripts/run-p2b.sh $P/runs/sims-N $P/runs/run-N # SA-SD, VA-VE, AA-AD, G; exit = p2bverdict.py
python3 $P/scripts/selftest-p2b.py $P/runs/run-N         # the guards can fail
bash $P/soc/gen-cp4.sh <base commit> $P/runs/gen-N       # before/after elaboration + judge-gen.sh
bash $P/soc/selftest-judge-gen.sh $P/runs/gen-N
bash $P/soc/chain-cp4-sim.sh $P/runs/gen-N $P/runs/rd2sim-N
bash $P/soc/run-xv6-p2b.sh m4smoke|perf-short $P/runs/rd2sim-N/sim-pipe/obj_dir/sim $P/runs/xv6-...
python3 $P/soc/xv6compare.py <label>=<run dir> ...        # the table of section 6
bash $P/soc/chain-cp5c.sh $P/runs/gen-N $P/runs/soc-N     # SoC boot programs, R-BOOT gates, drain during atomics
```
Every entry point exits non-zero on a failed check, a missing output or a timeout; each ran as a coord job. The
chain wrappers (`scripts/chain-cp3.sh`, `soc/chain-cp4-sim.sh`, `soc/chain-cp5.sh`, `soc/chain-cp5b.sh`) printed each
step's exit status but themselves exited 0 when they ran; they now exit non-zero when a step fails (edited after the
recorded runs, every recorded step had passed).

## 8. Not in P2b
Board, Vivado and timing (P3); a second pipeline hart (P4; refused today). The CPU-SU/M/C historical baselines
(SU 9, M 6, C 16) are unchanged and still not diagnosed; the pipeline reproduces them exactly.
