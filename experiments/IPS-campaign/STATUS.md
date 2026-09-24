# IPS campaign status

Updated 2026-09-24. Vocabulary is fixed: **IMPLEMENTED / SIM-VERIFIED / BUILD-VERIFIED /
BOARD-VERIFIED / PERFORMANCE-MEASURED**. A stage claims only what it has evidence for.

| stage | branch | status | note |
| --- | --- | --- | --- |
| 0 identities & contract | `ips-baseline` | **complete** | identity verified, workload set frozen, contract written |
| 1 fetch32 | `ips-fetch32` | not started here | OPT01 exists on `opt01-aligned-fetch` and is **pending independent review**, not accepted |
| 2 TLB | `ips-tlb` | not started | |
| 3 I-cache | `ips-cache` | not started | |

## Stage 0 — complete

| item | state |
| --- | --- |
| baseline reproduces the accepted 40 MHz configuration | **verified**, 15/15 frozen inputs, `clocking.vh` on the accepted side |
| `manifest.json` | 15 config inputs, **14 probes**, 9 sources, board artefacts, toolchain, frozen geometry |
| `CAMPAIGN.md` measurement contract | written |
| `ROI-POLICY.md` cold/steady-state, invalidation, window boundaries | written |
| `perf06_iws` — instruction working set > 1 KiB | **built and checked**: footprints measured from the disassembly at 192 B (0.19x) and 4140 B (4.04x); retirement counts 70001 / 65729 derived from the disassembly and agreeing with the source constants; byte-reproducible across two builds |
| `perf06_iws` against the production parser | correct records parse; wrong retirement, absent marker, non-zero exit and zero cycles are each rejected with their own reason |

## Frozen geometry

TLB 8 entries, fully associative, shared I/D. I-cache 1 KiB, direct mapped, 16-byte lines, sequential
refill. Decided before any comparative run; no sweep.

## What is NOT claimed

Nothing has been simulated, built into a bitstream, or run on hardware under this campaign. No
performance number exists for any stage — including for `perf06_iws`, which has been built and
statically checked but never executed. The 40 MHz bitstream on the board is the accepted one, restored
on 2026-09-24 with 8/8 gates; this campaign has programmed nothing and is not authorised to.

## Carried in from before the campaign

* **OPT01 / fetch32** is implemented and simulated on `opt01-aligned-fetch`, with a port-level test and
  a failing mutant, and xv6 booting all four commands at 1.23x cycles on real code. Its review,
  `claude-opt01-port-fixed-ready`, is **OPEN** — reused, not assumed accepted.
* **B0** gives 20 board microbenchmark ROIs and three board applications at 40 MHz, reusable only where
  identity, window and repetition policies match. Gaps are recorded, not relabelled.

## Next

Stage 1: rebase OPT01's implementation onto `ips-fetch32` from the verified baseline, and prepare the
reviewer-rerunnable handoff. `perf06_iws` must run unchanged on the baseline before any stage compares
against it — that run has not happened.
