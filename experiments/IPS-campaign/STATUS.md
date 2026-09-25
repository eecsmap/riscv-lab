# IPS campaign status

Updated 2026-09-25. Vocabulary: **IMPLEMENTED / SIM-VERIFIED / BUILD-VERIFIED / BOARD-VERIFIED /
PERFORMANCE-MEASURED**. A stage claims only what it has evidence for.

| stage | branch | commit | status |
| --- | --- | --- | --- |
| 0 identities & contract | `ips-baseline` | `66a3122` | complete |
| 1 fetch32 | `ips-fetch32` | `60421b5` | **SIM-VERIFIED + BUILD-VERIFIED** |
| 2 TLB | `ips-tlb` | `25b8e3f` | **SIM-VERIFIED + BUILD-VERIFIED**; the canonical fix is OPEN for review |
| 3 I-cache | `ips-cache` | `2b97e6d` | **SIM-VERIFIED + BUILD-VERIFIED** |

**Nothing is BOARD-VERIFIED or PERFORMANCE-MEASURED.** No bitstream has been programmed; this campaign
is not authorised to, and each one needs independent review plus a user-coordinated physical cold
cycle. The board holds the accepted 40 MHz bitstream, restored 2026-09-24 with 8/8 gates.

## Final matrix — `STAGE_SOC fails=0`

Four cores, one harness, 14 frozen binaries, all exiting 0 with identical verdicts. **48 metric rows,
0 refused.** See `FINAL-COMPARISON.md`.

| ROI | baseline | fetch32 | tlb | **cache** | vs baseline |
| --- | ---: | ---: | ---: | ---: | ---: |
| `perf02/k4_alu` | 71.04 | 37.04 | 13.01 | **8.00** | **8.880x** |
| `perf02/k4_load` | 82.12 | 48.06 | 16.02 | **11.00** | **7.465x** |
| `perf03/insn32` | 19.02 | 11.00 | 11.00 | **6.00** | 3.170x |
| `perf03/insn16` | 11.00 | 11.00 | 11.00 | **6.00** | 1.833x |
| `perf06/iws_resident` | 19.02 | 11.00 | 11.00 | **6.00** | 3.169x |
| `perf06/iws_exceeds` | 19.02 | 11.00 | 11.00 | **9.52** | 1.997x |

External AXI reads fall **95.3%** on `perf02` and **95.2%** on `perf03` from baseline to cache.

Simulator CPI throughout. The same `perf03` 32-bit ROI reads **40.34 on hardware**; these are never
pooled with board figures.

## Builds — all four close timing

| stage | WNS | WHS | setup/hold fail | LUT | FF | critical warnings |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline | +0.779 | +0.024 | 0 / 0 | 13,777 | 5,884 | 0 |
| fetch32 | +0.733 | +0.020 | 0 / 0 | 13,841 | 5,880 | 0 |
| tlb | +0.273 | +0.037 | 0 / 0 | 14,092 | 6,685 | 0 |
| cache | +0.354 | +0.035 | 0 / 0 | 14,529 | 7,007 | 0 |

`fetch32` costs **+64 LUTs** for the 1.73x it gives on 32-bit fetch. The TLB is the largest timing
cost. The cache's WNS being better than the TLB's is placement variance, not a gain from added logic.

## Equivalence controls, all exact

| control | result |
| --- | --- |
| `TLB_ENTRIES=0` vs `fetch32` | cycle-identical, **12/12 ROIs** |
| `ICACHE_BYTES=0` vs `tlb` | cycle-identical, **12/12 ROIs** |

Each took corrections that only the control could have found.

## What is open, and what is missing

* `claude-ips-fetch32-ready`, `claude-ips-tlb-canonical-fixed-ready`, `claude-ips-cache-ready` — all
  **OPEN**. Nothing here assumes any of them accepted.
* xv6 with the frozen `b0apps` profile has been run on **fetch32 only** (all three checksums matching
  the board). Not on `tlb` or `cache`.
* An in-flight refill surviving `fence.i` is argued from construction, not measured.
* AMO is not covered by the canonicality probe: `ext03_a` does not complete in this SoC configuration
  even on the baseline core.
* No board samples, so **the hardware IPS comparison is not complete** and is not claimed to be.
