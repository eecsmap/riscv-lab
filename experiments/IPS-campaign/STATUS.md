# IPS campaign status

Updated 2026-09-24. Vocabulary is fixed: **IMPLEMENTED / SIM-VERIFIED / BUILD-VERIFIED /
BOARD-VERIFIED / PERFORMANCE-MEASURED**. A stage claims only what it has evidence for.

| stage | branch | status | note |
| --- | --- | --- | --- |
| 0 identities & contract | `ips-baseline` | **in progress** | manifest and identity check done; `perf06_iws` not yet written |
| 1 fetch32 | `ips-fetch32` | not started here | OPT01 exists on `opt01-aligned-fetch` and is **pending independent review**, not accepted |
| 2 TLB | `ips-tlb` | not started | |
| 3 I-cache | `ips-cache` | not started | |

## Stage 0

| item | state |
| --- | --- |
| baseline reproduces the accepted 40 MHz configuration | **verified** — 15/15 frozen inputs match, `clocking.vh` on the accepted side |
| `manifest.json` | **written** — 15 config inputs, 13 probe ELFs, 8 sources, board artefacts, toolchain |
| `CAMPAIGN.md` measurement contract | **written** |
| `perf06_iws` (instruction working set > 1 KiB) | **not written** |
| ROI cold/steady-state policy per workload | **not written** |

## What is NOT claimed

Nothing has been simulated, built or run on hardware under this campaign. No performance number exists
for any stage. The 40 MHz bitstream currently on the board is the accepted one, restored on 2026-09-24
with 8/8 gates; this campaign has not programmed anything and is not authorised to.

## Carried in from before the campaign

* **OPT01 / fetch32** is implemented and simulated on `opt01-aligned-fetch`, including a port-level test
  with a failing mutant, and xv6 booting with all four commands at 1.23× cycles on real code. Its
  review, `claude-opt01-port-fixed-ready`, is **OPEN** — it is reused, not assumed accepted.
* **B0** gives 20 board microbenchmark ROIs and three board applications at 40 MHz. Reusable only where
  identity, window and repetition policies match; gaps are recorded rather than relabelled.
