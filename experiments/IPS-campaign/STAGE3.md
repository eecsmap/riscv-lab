# Stage 3 — instruction cache: results

Branch `ips-cache`, rebased onto the corrected `ips-tlb` so it carries the canonicality and
per-write-`satp` fixes. Design fixed before implementation in `STAGE3-DESIGN.md`.

## SoC regression — `STAGE_SOC fails=0`

Thirteen frozen binaries across `tlb` / `cache` / `cacheoff`; every one exits 0 on every core with the
same verdict. **36 metric rows, 0 refused.**

## The equivalence control holds

**`cacheoff` is cycle-identical to `tlb` on 12/12 ROIs.** `ICACHE_BYTES = 0` removes the cache and
changes nothing else — measured, not argued.

## Results — SIMULATOR

| ROI | tlb | **cache** | gain |
| --- | ---: | ---: | ---: |
| `perf03_fetch/insn32` | 330,029 | **180,026** | 1.833x |
| `perf03_fetch/insn16` | 330,033 | **180,029** | 1.833x |
| `perf02_sv39/k4_alu` | 390,203 | **240,016** | 1.626x |
| `perf04_where/load_dram` | 400,370 | **250,119** | 1.601x |
| **`perf06_iws/iws_resident`** (192 B, fits) | 770,013 | **420,132** | **1.833x** |
| **`perf06_iws/iws_exceeds`** (4140 B, 4.04x capacity) | 723,019 | **625,967** | **1.155x** |

External AXI reads, `tlb` → `cache`: `perf03` **93.1% fewer**, `perf02` 79.7%, `perf04` 79.5%,
`perf06` 70.6%.

## The prediction written before the implementation was met

`STAGE3-DESIGN.md` said, before any RTL existed:

> its **exceeds** ROI must still be **correct**, and is expected to show little or no saving — a
> direct-mapped 1 KiB cache conflicts on every pass through it. If it shows a large saving, the probe
> is not doing what it claims and the number is not a cache result.

Resident **1.833x**, exceeds **1.155x**. The probe discriminates, and the discrimination was specified
in advance rather than read off afterwards.

The 1.155x that remains on the exceeds ROI is not a cache hit rate: a 16-byte line carries four
instructions, so even at a 100% line-miss rate the machine fetches one line per four instructions
instead of one word per instruction. It is refill amortisation, and calling it a hit would be wrong.

`perf06`'s two ROIs measured **identical** on baseline, fetch32 and the TLB — 19.02 and 11.00 CPI alike
— so the divergence here is attributable to the cache and to nothing else. That control is why `perf06`
was written in stage 0.

## Components

| suite | result |
| --- | --- |
| `run-icache-tb.sh` | **21/21**, four mutants each caught by the right test |
| `run-ifill-tb.sh` | **23/23**, four mutants each caught by the right test |
| `run-tlb-tb.sh` (inherited) | 31/31 |

`run-ifill-tb.sh` asserts what went **out**, not only what came back: a hit produces **no external
transaction at all**, a CLINT fetch produces exactly one at its own address rather than a line base, a
data read and a write pass through and never fill, and a refill is exactly two beats at the line base
and base+8.

Two defects of mine were caught by that bench rather than by reading the code: the refill held
`m_req_valid` high for the whole wait, so the model recorded a fresh request every cycle; and the
response pass-through was gated on `mine`, which depends on `c_req_valid` — dropped the moment the
request is accepted — so during a refill the core would have been handed **our own beats** as its
response and would have consumed half a line as an instruction.

## Not done

* `fence.i` is tested at the component level; a **self-modifying-code probe** at the core boundary is
  not written. Codex's stage 3 list requires one, and its absence is stated rather than glossed.
* An in-flight refill surviving `fence.i` is not separately tested.
* xv6 with the frozen application profile has not been run on this core.
* Nothing is BUILD-VERIFIED, BOARD-VERIFIED or PERFORMANCE-MEASURED.

## Status

**IMPLEMENTED and SIM-VERIFIED** at component and SoC level, with the gaps above named.
