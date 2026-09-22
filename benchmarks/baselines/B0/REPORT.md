# B0 — performance baseline (candidate)

**Status: candidate.** Nothing here is accepted. Every figure is `reported`: measured once by one agent
and recorded, not independently recalculated or re-run. See `../../metrics.md` §9.

This exists so that a later optimisation has something to be judged against. It contains no optimisation,
no counters, no cache, no TLB and no RTL change.

## Baseline table — microbenchmarks

<!-- BEGIN GENERATED baseline-table -->

Board figures are the median of **5 samples**; the simulator is deterministic and verified so
over **3 samples**. Spread is `(max - min) / median`. Derived IPS is `40,000,000 / CPI` and is **model-derived**, never measured throughput.

| workload / ROI | board CPI | spread | simulator CPI | derived IPS (board) |
| --- | --- | --- | --- | --- |
| `perf01_cpi` / `alu` | **40.34** | 0.100% | 19.39 | 0.992 M |
| `perf01_cpi` / `load` | **46.68** | 0.077% | 21.84 | 0.857 M |
| `perf01_cpi` / `store` | **46.18** | 0.093% | 21.84 | 0.866 M |
| `perf02_sv39` / `bare_alu` | **40.33** | 0.066% | 19.39 | 0.992 M |
| `perf02_sv39` / `bare_load` | **46.84** | 0.049% | 21.84 | 0.854 M |
| `perf02_sv39` / `k4_alu` | **161.30** | 0.034% | 73.09 | 0.248 M |
| `perf02_sv39` / `k4_load` | **188.15** | 0.030% | 84.23 | 0.213 M |
| `perf02_sv39` / `mega_alu` | **82.62** | 0.034% | 39.84 | 0.484 M |
| `perf02_sv39` / `mega_load` | **96.22** | 0.074% | 45.35 | 0.416 M |
| `perf03_fetch` / `insn16` | **21.64** | 0.093% | 11.08 | 1.848 M |
| `perf03_fetch` / `insn32` | **40.33** | 0.037% | 19.39 | 0.992 M |
| `perf04_where` / `load_clint` | **42.83** | 0.138% | 21.74 | 0.934 M |
| `perf04_where` / `load_dram` | **46.68** | 0.079% | 21.84 | 0.857 M |
| `perf05_size` / `alu` | **40.35** | 0.049% | — *not in the sampled sim run* | 0.991 M |
| `perf05_size` / `load_1b` | **46.79** | 0.393% | — *not in the sampled sim run* | 0.855 M |
| `perf05_size` / `load_2b` | **46.81** | 0.386% | — *not in the sampled sim run* | 0.855 M |
| `perf05_size` / `load_4b` | **46.86** | 0.415% | — *not in the sampled sim run* | 0.854 M |
| `perf05_size` / `load_8b` | **46.80** | 0.492% | — *not in the sampled sim run* | 0.855 M |
| `perf05_size` / `store_1b` | **46.18** | 0.064% | — *not in the sampled sim run* | 0.866 M |
| `perf05_size` / `store_8b` | **46.20** | 0.095% | — *not in the sampled sim run* | 0.866 M |

**20 ROIs across 5 probes on the board; 13 of them also in the sampled simulator run.** Generated from `metrics.json` by `benchmarks/tools/gen_baseline_table.py`; `make bench-check` fails if it drifts.

<!-- END GENERATED baseline-table -->

**Do not divide a board column by a simulator column.** The simulator models no PS or DDR path at all —
`perf04` shows a DRAM load and a PL-internal CLINT load costing the same there (7.33 vs 7.04) and very
differently on the board. `gen_comparisons.py:ratio()` refuses such comparisons.

## What is measured, what is an RTL fact, and what is model-derived

**Measured** — cycle and retired counts from the core's own counters, above.

**RTL facts**, read from the source and reproducible by anyone with the tree:

* `tcpu_core.v` fetches **one 16-bit parcel at a time** (`core_req_size = 2'd1`); a non-compressed
  instruction takes a second request at `pc+2` via `S_IF2_REQ`;
* under Sv39 the second parcel's page is translated **independently** of the first;
* `tcpu_ptw.v`: serial walker, **no TLB and no PTE cache**, one 8-byte read per level;
* the core is a multi-cycle FSM with no pipeline, no instruction or data cache, no store buffer, and one
  outstanding access.

**Model-derived** — quantities computed from the measurements under a stated model, each inheriting its
model's assumptions:

| quantity | value | from |
| --- | --- | --- |
| memory round-trip `L` | ≈ **17.7 cycles** | `perf03`, using `CPI16 = F + L`, `CPI32 = F + 1 + 2L` |
| fixed FSM overhead `F` | ≈ **3.9 cycles** | the same model |
| memory round-trip `L` | ≈ **18.7 cycles** | `perf04`'s DRAM load, a *separate* estimate |

`F` comes out at **3.90 on the board and 3.77 in simulation**. That is the same RTL measured on two very
different memory systems, and the agreement is the reason to believe the split at all.

The two `L` estimates are close but are **not interchangeable**, and substituting one into an accounting
built on the other and calling the total exact is the error corrected in `ERRATA.md` **E1**.

## Coverage

| class | defined | measured | note |
| --- | --- | --- | --- |
| microbenchmarks | **20 ROIs across 5 probes** | **20 on board** (5 samples each); **13 in simulation** | board policy met; `perf05_size` was added after the sampled simulator run and has one simulator observation outside it, which is **not** a sampled result |
| applications | 3 | **0 — pending** | built, identities recorded, expected checksums computed; never executed |

### Why the application workloads are pending

`b0compute`, `b0array` and `b0file` are written, build into an xv6 image, and have expected checksums
computed independently on the host. They have **not been run on anything**, so they have no timings, and
their metrics are `null` rather than `0`.

The blocker is specific. Hardware repetitions in this task are authorised **only** through the accepted
production lifecycle, and that lifecycle drives a fixed four-command workload: `EXPECTED` in
`tools/xv6-boot/scripts/xv6_console.py` is a module-level constant shared by the board driver and the
simulator driver, not a parameter. Extending it is host/driver redesign, which this task excludes. The
simulator is not an alternative either — the accepted xv6 simulation run took **12 054 s (3.35 hours)**
for a single session, so three samples of three workloads is a multi-day campaign.

This is reported as a coverage gap, not worked around.

### The image these would run on

The **kernel is byte-identical** to the accepted one (`e990fb31…`) — the three programs live in `fs.img`,
and this build reproduced the accepted kernel exactly. The **disk differs** (`6bdd8148…` against the
accepted `4691ffea…`) and is therefore a different workload image. Results from it must never be compared
with results from the accepted disk as though they were the same workload.

## Limits

* Both board runs share boot id `ebeab8a6-…`. They are **same-session repeats** and show short-term
  repeatability (spread ≤ 0.14 %) only. **Nothing here is reproduced across independent cold boots.**
* Every IPS figure is **derived** as `configured_hz / CPI`. No measured wall throughput exists for any
  microbenchmark.
* 40 MHz is **configured**, not measured: 125 MHz on pin H16 through an MMCM at ×8/25. No probe here
  measures absolute frequency.
* The microbenchmarks are **synthetic loops**. None of these numbers is xv6's average CPI, which remains
  unmeasured (`ERRATA.md` E3).
* The historical run `2026-09-21-board-s3-historical` is retained for provenance and **does not meet the
  sample policy** — one sample per workload. It is not part of the baseline figures above.

## Auxiliary result

`perf01` also reports the RTC divider: **100.0** measured on the board, matching
`clint_io_rtcTick = value == 7'h63`. So `mtime` runs at 40 MHz / 100 = **400 kHz** against a device tree
declaring a 1 MHz timebase — out by **2.5×**. Inherited from the baseline platform, not introduced by this
CPU.

## Measurement identities

`benchmarks/tools/verify_identities.py`, run by `make bench-check`, checks every identity it can reach
from inside the repository and **names the rest with the reason they are out of reach** — an identity
that cannot be checked from here has to be checked elsewhere, and saying so is not the same as verifying
it.

| | |
| --- | --- |
| verified against the repository's own release bundle | the **bitstream**, the **raw payload**, the **host binary** |
| verified against committed sources | all **eight workload sources** |
| **structurally verified** | every workload with samples has a recorded ELF identity |
| unchecked, with reasons stated | probe ELFs and the simulator binary — build artefacts, not committed |

That structural check found a real gap: `perf05_size` was added to the board run after its manifest was
written, so the run carried five sampled workloads while the manifest named four ELFs. Its identity is
now recorded, and the check fails if it happens again — verified by removing it, which turns the check
red.

## Reproducing the analysis

From this repository, no hardware and no absolute paths:

```bash
make bench-selftest    # 28 negative and positive fixtures for the parser and generators
make bench-metrics     # regenerate every metrics.json from the immutable raw records
make bench-check       # regenerate comparisons.csv and diff it against the committed copy
make check             # the repository's pre-existing offline checks, unchanged
```

---

## Addendum: access size does not affect cost (`perf05_size`)

Added after the first draft, to discriminate between two explanations for the low achieved bandwidth:
**granularity** (a 2-byte parcel uses a quarter of one 64-bit beat) or **concurrency** (one outstanding
access, so bandwidth is size ÷ latency whatever the bus width). The same loop, the same 8-byte-aligned
address, seven times, differing in one instruction. Board, median of 5 samples.

| access | bytes | CPI | extra cycles per access |
| --- | --- | --- | --- |
| baseline, no data access | — | 40.35 | — |
| load | 1 | 46.79 | **19.32** |
| load | 2 | 46.81 | **19.39** |
| load | 4 | 46.86 | **19.54** |
| load | 8 | 46.80 | **19.36** |
| store | 1 | 46.18 | **17.49** |
| store | 8 | 46.20 | **17.56** |

**An 8× larger transfer costs the same.** 1-byte and 8-byte loads differ by **0.2 %**; stores by 0.4 %.
Within a single beat the cost is **pure latency** and the transfer itself is not on the critical path.

Two further results fall out:

* **stores are ~10 % cheaper than loads** (17.5 against 19.4 cycles), consistent with a write being
  acknowledged before a read could have returned data;
* **sub-word writes carry no read-modify-write penalty** — `sb` costs the same as `sd`, so byte strobes
  are being used rather than a read-modify-write somewhere below. This was a specific worry the probe was
  written to check, and it is answered: no.

### What this settles, and what it does not

**Settled:** widening an access buys nothing. Any proposal of the form "fetch more bytes per request"
gains only from the requests it *eliminates*, never from the extra bytes. This is why the aligned 32-bit
fetch is worth doing — it removes one round-trip of two per instruction, and under Sv39 one walk of two —
and not because it moves 4 bytes instead of 2.

**Not settled:** whether a multi-beat **burst** amortises the latency across a cache line. The core issues
one single-beat request at a time and cannot express a burst, so this probe cannot test it. The estimate
that a 32-byte line would cost ≈32 B / (470 + 3×25) ns remains a **model-derived hypothesis**, not a
measurement, and would need an RTL change to test.
