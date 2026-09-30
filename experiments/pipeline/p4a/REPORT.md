# PIPE-P4a REPORT — two pipeline harts, simulation acceptance

Task `codex-pipe-p4a-dual-simulation`. Branch/worktree `pipe-dual` created from tag `pipe-v1-single`
(`0c0f05d1b0852461030eae08dccce654546e7eff`); the `pipe-single` checkout, the board (single-pipeline image, the
user's disks) and every existing configuration are untouched. Offline only: no board, no Vivado, no push/tag.

**Status: all five required evidence items pass in simulation.** Evidence: `results/` (158 text files); runs
under `runs/` (not in git).

## 1. Design delta
**No RTL change.** The pipeline core, its TLB/walker, the shared CSR/muldiv/cdecode/icache and the whole multicycle
side are byte-identical to `pipe-v1-single`. The only source change is `soc/scala/teaching/RD2Soc.scala`:
* the pipeline's single-core restriction is removed — its hart count is the same `NUM_CORES` choice (1 | 2, the
  existing generic check) as the multicycle core's, so pipeline/2 is two `TeachingHart`s exactly as multicycle/2:
  per-hart `TeachingCpuV2` (its own BlackBox, TLB, I-cache, HART_ID), per-hart `RD2BridgeV2` (client name
  `teaching-phys-<i>`), per-hart CLINT/PLIC contexts, one shared serial `AtomicBackend` bound by client name,
  one aligned drain. Core implementation and hart count stay independent;
* new `RD2PipeDualXv6FastConfig` and `RD2PipeDualBootConfig`;
* the refusals keep meaning: `MC1UnsupportedPipelineConfig` is now pipeline × 4 (name kept for the MC regressions),
  `MC2UnsupportedQuadConfig` (multicycle × 4), `MC1UnsupportedZeroConfig`, `P2bUnsupportedImplConfig` (unknown
  core), `P2bUnsupportedPipeV1Config` (pipeline on the non-atomic path).

| | 1 hart | 2 harts |
|---|---|---|
| multicycle | `RD2AtomicXv6FastConfig` / `RD2AtomicBootConfig` / `RD2AtomicBoardConfig` | `RD2DualXv6FastConfig` / `RD2DualBootConfig` / `RD2DualBoardConfig` |
| pipeline | `RD2PipeXv6FastConfig` / `RD2PipeBootConfig` / `RD2PipeBoardConfig` | `RD2PipeDualXv6FastConfig` / `RD2PipeDualBootConfig` (board shape: P4b) |

Commits: `1200de5` (scala + generation judge), `8ce0491` (generation evidence, build scripts), and this report's
commit (suite, programs, xv6 chain, results).

## 2. Generation and build (`scripts/gen-p4a.sh`, `results/gen-1/`)
Fresh elaboration before (`pipe-v1-single`) and after, private commons:
* the ten existing configurations above (every shape of multicycle 1/2 and pipeline 1, plus the V1 `RD2BootConfig`)
  are **normalized-identical** (raw differences are scala source locators only);
* `RD2PipeDualXv6FastConfig` / `RD2PipeDualBootConfig`: exactly two `tcpu_core_pipe`, `HART_ID(0)` and `HART_ID(1)`,
  both with `MISA_A`/`PIPE_EXT_M`/`C`/`SU` = 1, nothing else passed, no `tcpu_core`;
* against multicycle/2 of the same shape, pipeline/2 differs in exactly two modules, `TeachingCpuV2` and
  `TeachingCpuV2_1` (10 lines each: the core instance and the wrapper's owner-metadata `isFetch` terms); the other
  152 (Xv6Fast) / 220 (Boot) modules are identical (`cmp-multi-dual*-vs-pipe-dual*.txt`);
* all five refusals refuse with their messages.
Simulators (`scripts/chain-sims.sh`, `results/sims-1/`): built from `rtl/cpu/pipeline/SOURCES.pipe` with an
include-only directory (no module auto-discovery), `m3_main.cpp` with two harts; the build refuses Verilog that
does not instantiate `tcpu_core_pipe` exactly twice.

## 3. Bare-metal dual suite (`scripts/run-dual-suite.sh`, `results/suite-1/`)
The accepted MC-M2b runner, programs and judge, unchanged, on the two-pipeline simulators:

| group | runs | result |
|---|---|---|
| traced SoC, **association checker on each hart** (P3b checker, one copy per hart) | dual01 boot, dual02 CLINT (5 timer + 1 software interrupt on hart 1), dual04 pbus/PLIC, dual05 fence.i, dual03 lock/LR-SC/AMO with the backend trace, dual06 soft reset with BOTH harts in flight + reload, dual08 (new: hart-1 store behind ECALL) | 7/7 PASS, `ASSOC H0` and `ASSOC H1` clean in every run |
| fast SoC | dual03 under 10 throttle timings, dual07 long run | 11/11 PASS |
| M2b injected-defect programs | neg01 no hart 1, neg02 wrong hart, neg03 wrong count, neg04 early report | 4/4 rejected |
| integration negatives | HART_ID swapped between the two harts (dual01, dual02); the core's knob 4 on hart 1 only (dual08) | 3/3 caught: both HART_ID runs rejected; knob 4 → first failure `ASSOC H1 FAIL association`, hart 0 clean |

* **Simultaneous requests, backpressure, ownership**: both harts issue concurrently through their own bridges; the
  per-hart association checker records each transaction's owner at its request handshake from that hart's core
  and requires every data response to be followed by its own requester's retirement — 161,105 / 159,292 data
  responses in dual03 alone (loads, stores, 58,952 / 59,995 AMOs, 23,994 / 24,547 LR/SC pairs), 0 failures. The
  per-hart outstanding-request contract (one at a time) is part of the checker (`protocol`).
* **Forward progress vs starvation** (bounded): the longest an offered request of either hart waited for the
  fabric was 18 / 18 cycles (dual03 traced), 18 / 22 (worst throttle timing), 15 / 11 (dual07), 258 / 253 (xv6);
  dual07 retires ≥ 1.2 M per hart. Contention is visible (SC failures, waits), starvation is not.
* **Reset/drain with both harts in flight** (dual06): 7,750 CPU DRAM writes, each bound to exactly one AXI write;
  the pre-hold writes of both harts (1,555 / 1,553) survive the reload; no stale response reached either core
  (association `stale`/`protocol` clean).

## 4. Atomics, reservations, ordering
* dual03 (both harts, lock + LR/SC counter + AMO counter + publish): every count exactly 20,000; SC failures on the
  shared words 3,994 (hart 0) and 4,547 (hart 1) — reservations really are lost to the other hart's accesses and
  retried; the backend trace floor (≥ 20,000 atomics) holds. Reservations are per hart in the unchanged accepted
  backend (slot by client name); its remote-store invalidation and kill groups were accepted in MC-M2a/M2b and the
  backend is unchanged here.
* **aq/rl under the shared serialized backend**: each pipeline hart has at most one memory request outstanding, an
  atomic is issued only when it is the oldest instruction and retires only after its response, and there is no
  store buffer and no data cache; every data access therefore completes at the memory/backend before the hart
  issues its next one, in program order. The backend and memory serve the two harts' accesses one at a time. The
  resulting order of all data accesses is a single interleaving that respects each hart's program order —
  sequential consistency for data — which satisfies every aq/rl bit and every FENCE on data. dual03's publish
  (store data, then flag, other hart reads flag then data) and the lock-protected counter exercise it. It does
  **not** extend to instruction fetch: FENCE.I invalidates only the executing hart's I-cache (dual05 checks the
  local case); there is no remote I-cache coherence. SFENCE.VMA is likewise local.

## 5. Interrupts, traps, Sv39
* Per-hart interrupts: dual02 (timer and software interrupts to hart 1 through its own CLINT slot); xv6 runs its
  timer on both harts (traps 125 / 253 in m4smoke).
* Precise traps with a store behind a trapping instruction on hart 1 (dual08) — and the knob-4 negative shows the
  per-hart checker localizes a violation to the right hart.
* Sv39/TLB on both harts: xv6 (kernel and user address spaces, per-hart TLB and walker) in both workloads below.
  The bare-metal dual programs run in M-mode without translation.
* Single-pipeline regression subset (the changed path is RD2Soc only; single-pipeline generated RTL is identical,
  §2): the P3b association set rebuilt from this tree's fresh `RD2PipeBootConfig` — 20/20 clean, five restarts with
  an atomic in flight drained, coverage identical to the accepted `assoc-3` (`results/xv6-1/single-assoc-*`).

## 6. Dual-pipeline xv6 (`scripts/run-xv6-dual.sh`, `results/xv6-1/`)
Accepted runners, named hash-checked inputs, the two-hart judge (`m3_check.py` without `--n1`: both harts reach
the scheduler, commit user-mode instructions, hart 1 ≥ 100,000; also verified to PASS the accepted multicycle dual
runs).

| run | kernel / disk | judge | retired h0 / h1 | user-mode h0 / h1 | total cycles |
|---|---|---|---|---|---|
| m4smoke (b0compute, m3par2, m3fs) | `1e4749c0…` / `d8e50269…` | PASS | 23,451,838 / 23,539,954 | 1,218,649 / 3,059,044 | 113,776,545 |
| perf-short | `d713744a…` / `d558e444…` | PASS / PASS (`perf_check`) | 15,975,890 / 14,354,973 | 1,006,858 / 1,370,694 | 71,954,765 |

"hart 1 starting" and user-mode commits growing on both harts through the run (PROGRESS samples); m3par2's two
children and m3fs both correct; the eight perf children's checksums are identical to the multicycle dual run.

**Fixed work, same measurement kernel and disk, simulation (mtime units = 100 core cycles):**

| configuration | perfcompute (80,000 iterations) | perfarray (65,536 updates) | source |
|---|---:|---:|---|
| multicycle × 1 | 167,357 | 262,904 | `multicore/perf/runs/tb-single-short` |
| multicycle × 2 | 93,304 | 158,021 | `multicore/perf/runs/tb-dual-short` |
| pipeline × 1 | 83,457 | 75,472 | `pipe-single` P2b `xv6-perf-short-pipe-2` |
| **pipeline × 2** | **46,470** | **51,664** | this run |

Two harts vs one: compute 1.80× on the pipeline (1.79× multicycle); array 1.46× (1.66× multicycle). Pipeline × 2 vs
multicycle × 2: compute 2.01×, array 3.06×. The array workload is memory-bound: with faster cores, the two harts'
requests saturate the shared serial backend / single memory path sooner, so it scales less — an observation, not a
decomposed cause. These are simulated cycles of short regions, not board seconds; no board speed is inferred (the
m4smoke totals include idle time while the runner types commands).

## 7. Limitations
* No remote I-cache or TLB coherence (FENCE.I and SFENCE.VMA are hart-local); the ordering argument covers data.
* The bare-metal dual programs do not use Sv39; translation on both harts is covered by xv6 only.
* The historical CPU-SU / M / C baseline findings are not revisited (no core RTL change); nothing new failed.
* Board shape, 40 MHz closure, resources (P4b) and board validation are later, separately authorised gates.

## 8. Commands
```sh
P=experiments/pipeline/p4a
bash $P/scripts/gen-p4a.sh pipe-v1-single $P/runs/gen-N
bash $P/scripts/chain-sims.sh $P/runs/gen-N $P/runs/sims-N          # fast, traced+association, two negatives
bash $P/scripts/run-dual-suite.sh $P/runs/sims-N $P/runs/suite-N-<group> <traced|fast|neg|integ|all>
bash $P/scripts/chain-xv6.sh $P/runs/sims-N $P/runs/gen-N $P/runs/xv6-N   # m4smoke, perf-short, single-pipeline subset
```
Every entry point exits non-zero on a failed check, a missing output or a timeout; each ran as a coord job
(≤ 4 build workers).
