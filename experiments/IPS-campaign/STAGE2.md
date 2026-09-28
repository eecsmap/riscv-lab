# Stage 2 — TLB: results

Branch `ips-tlb`. Design fixed before implementation in `STAGE2-DESIGN.md`.

## SoC regression — `STAGE_SOC fails=0`

Four cores, one generated harness, twelve frozen binaries identical across all of them:

| core | `tcpu_core.v` |
| --- | --- |
| `baseline` | `09449b24e64440f7` — the accepted configuration |
| `fetch32` | `de6be6cb3b795d38` |
| `tlb` | the 8-entry TLB |
| `tlboff` | the same core with `TLB_ENTRIES = 0` |

Every binary exits 0 on every core, and every probe reports the **same verdict** on all four —
including `tlb01_sfence`, `perf02_sv39` and `ext04_sv39`. **48 metric rows, 0 refused.**

## The equivalence control holds exactly

| | |
| --- | --- |
| ROIs where `tlboff` is **cycle-identical** to `fetch32` | **12 / 12** |
| memory traffic on untranslated probes, `tlb` vs `tlboff` | **exactly 0.0% different** — identical, not similar |

That took two corrections, both mine, and both found by the control rather than by reasoning. The first
version of `tcpu_xlate` latched the request and looked it up a cycle later; the second registered the
walker's result on the way back. Each added a cycle to every translation, and together they made
`tlboff` read 40.05 CPI where `fetch32` read 37.04. The lookup is combinational now and a walk's result
passes straight through; only the hit path is registered, because a hit is answered one cycle after the
lookup and there is nothing else to answer it with.

**An equivalence control that is not equivalent is not a control.** The fix also made the TLB faster,
which was not the point.

## Results — SIMULATOR, never pooled with board figures

| workload | ROI | baseline | fetch32 | **tlb** | tlboff | tlb vs baseline | tlb vs fetch32 |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `perf02_sv39` | `bare_alu` | 19.02 | 11.00 | **11.00** | 11.00 | 1.729x | **1.000x** |
| `perf02_sv39` | `bare_load` | 21.36 | 13.35 | **13.35** | 13.35 | 1.600x | **1.000x** |
| `perf02_sv39` | `k4_alu` | 71.04 | 37.04 | **13.01** | 37.04 | **5.462x** | 2.848x |
| `perf02_sv39` | `k4_load` | 82.12 | 48.06 | **16.02** | 48.06 | **5.125x** | 3.000x |
| `perf02_sv39` | `mega_alu` | 39.05 | 21.06 | **13.01** | 21.06 | 3.002x | 1.619x |
| `perf02_sv39` | `mega_load` | 44.67 | 26.70 | **16.02** | 26.70 | 2.788x | 1.667x |
| `perf03_fetch` | `insn16` / `insn32` | 11.00 / 19.02 | 11.00 | **11.00** | 11.00 | — | **1.000x** |
| `perf04_where` | `load_clint` / `load_dram` | 21.36 | 13.34 | **13.34** | 13.34 | — | **1.000x** |
| `perf06_iws` | both ROIs | 19.02 | 11.00 | **11.00** | 11.00 | — | **1.000x** |

**The TLB changes only what is translated.** Every untranslated ROI is exactly 1.000x against fetch32 —
not close, identical. The 4 KiB page ROIs gain most, which is what a three-level walk predicts.

CPI here is simulator CPI. The same `perf03` 32-bit ROI reads **40.34 on hardware**.

## Walks are observed, not assumed

The design has no counter for page-table walks. The harness's per-event trace has one — a PTE read is a
`REQ` the walker issues — so `trace_aggregate.py` counts them exactly:

| workload | requests, `tlboff` → `tlb` | fewer |
| --- | --- | ---: |
| `perf02_sv39` | 533,904 → 225,391 | **57.8%** |
| `ext04_sv39` | 1,984 → 1,627 | 18.0% |
| `tlb01_sfence` | 3,238 → 2,781 | 14.1% |
| `perf03` / `perf04` / `perf06` | unchanged | **0.0%** |

`tlb01_sfence` saves least of the translated probes **because it exists to invalidate**: every case
flushes and forces a re-walk. That is the "re-walk after invalidation" evidence, visible as the saving
it prevents.

## The targeted probe, and proof it tests the TLB

`tlb01_sfence` passes on all four cores. On its own that proves little — the walker does every check on
a core with no TLB — so two things establish that it tests the **hit** path:

1. on the same binary, the TLB core issued **486 fewer memory requests and 42% fewer AXI reads**, so it
   was hitting during those cases;
2. two mutants of the TLB core, each caught by exactly the right case:

| mutant | verdict |
| --- | --- |
| a hit skips the permission re-check | **FAIL — case B (a hit ignored A/D)** |
| `sfence.vma` and `satp` changes do not flush | **FAIL — case A (sfence.vma did not invalidate a cached entry)** |

Case B is the one the walker cannot catch: the page is cached by a successful **load** with `A=1, D=0`,
and the **store** must then fault. The walk already happened and already passed.

## Attempts, all recorded

| attempt | outcome |
| --- | --- |
| 1 | `perf02_sv39` bound sized from the cores that finished; the baseline ran out. Also exposed a **vacuous verdict check** of mine: it said "every core reports OK" while the baseline had reported nothing at all |
| 2 | `tlb01_sfence` ran to completion and failed **case B on every core including the baseline** — the probe reset the trap cause between cases but not the trap count |
| 3 | stopped deliberately part way: its RTL had been superseded by the equivalence diagnosis. Preserved |
| 4 | **fails=0** |

Before attempt 1, `tlb01_sfence` timed out on all four cores with the trace ending at
`COMMIT pc=0x80000000` — a page fault in S-mode went to M-mode's unset `mtvec` and the machine
restarted. The probe now writes `medeleg`, **reads it back and checks it**, and the build refuses a
binary containing no `medeleg` write.

## Status

**IMPLEMENTED and SIM-VERIFIED.** Not BUILD-VERIFIED, BOARD-VERIFIED or PERFORMANCE-MEASURED.
