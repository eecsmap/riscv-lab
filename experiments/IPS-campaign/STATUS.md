# IPS campaign status

Updated 2026-09-24. Vocabulary is fixed: **IMPLEMENTED / SIM-VERIFIED / BUILD-VERIFIED /
BOARD-VERIFIED / PERFORMANCE-MEASURED**. A stage claims only what it has evidence for.

| stage | branch | commit | status |
| --- | --- | --- | --- |
| 0 identities & contract | `ips-baseline` | `66a3122` | **complete** |
| 1 fetch32 | `ips-fetch32` | `6462b67` | **IMPLEMENTED + SIM-VERIFIED** (port and SoC, with metrics). Handed off as `claude-ips-fetch32-ready`, **OPEN** |
| 2 TLB | `ips-tlb` | `dcfe056` | **IMPLEMENTED**, components SIM-VERIFIED. SoC regression not run |
| 3 I-cache | `ips-cache` | `4332cac` | components **IMPLEMENTED + SIM-VERIFIED in isolation**. Not integrated |

Nothing is BUILD-VERIFIED, BOARD-VERIFIED or PERFORMANCE-MEASURED. **No bitstream exists and this
campaign has touched no hardware.** The board holds the accepted 40 MHz bitstream, restored on
2026-09-24 with 8/8 gates.

## What is proved, per stage

**Stage 0.** The baseline reproduces the accepted 40 MHz configuration, executably: 15/15 frozen inputs
match with `clocking.vh` on the accepted side, against E1's `INPUTS.json`, which recorded those hashes
before this campaign existed and for an unrelated purpose. Workload set frozen, including the new
`perf06_iws` whose footprints (192 B and 4140 B) and retirement counts (70001 and 65729) are both
**derived from the disassembly**, not asserted.

**Stage 1.** Port regression `fails=0` across accepted / fetch32 / mutant, the mutant failing after
reaching the translated path. SoC: seven runnable gates and three probes exit 0 on both cores; 12
metric rows, 0 refused.

| ROI | baseline CPI | fetch32 CPI | gain |
| --- | ---: | ---: | ---: |
| `perf03 insn16` | 11.00 | 11.00 | **1.000x** |
| `perf03 insn32` | 19.02 | 11.00 | **1.729x** |
| `perf04 load_*` | 21.36 | 13.34 | 1.601x |
| `perf06 both ROIs` | 19.02 | 11.00 | 1.729x |

Simulator cycles. The same ROI reads 40.34 CPI on hardware; never pooled.

**Stage 2.** `tcpu_permcheck` extracted and proved **exhaustively equivalent over all 4096 inputs**.
`tcpu_tlb` 31/31 component checks, five mutants each caught by the right test. `tcpu_xlate` presents
the walker's own interface, so `S_XLATE` in the core is unchanged. `tlb01_sfence.S` built and
scope-checked; its three cases are shaped so only a hit-path defect can pass them.

**Stage 3.** `tcpu_cacheable` and `tcpu_icache`, 21/21 component checks, four mutants each caught.
"No valid partial line" is structural: `fill` takes the whole line or nothing.

## Running

`ips-xv6-fetch32` — xv6 with the frozen `b0apps` profile on fetch32, registered, 6 h bound. At the
time of writing it is ~490 M target cycles in and still booting, which is expected: the comparable
baseline simulator run took **6.4 hours**. The 6 h bound may prove too short; a timeout is a result and
will be reported as one.

One heavy simulation at a time. That run holds the slot, which is why stage 2's SoC regression and
stage 3's integration are waiting rather than proceeding.

## Next, in order

1. stage 2 SoC regression across `baseline`, `fetch32`, `tlb`, and `tlb` with `TLB_ENTRIES=0` — the
   disabled configuration must be **cycle-identical** to fetch32;
2. `tlb01_sfence` executed, plus walk counts from the trace showing fewer walks on repeated hits and a
   re-walk after invalidation;
3. stage 3 integration into the fetch FSM, then the same treatment.
