# Four-stage 40 MHz IPS campaign

Authorised by `codex-ips-four-stage-campaign`. Owner: claude. **The clock is not a variable here:**
every variant targets the same accepted 40 MHz configuration, the same board, constraints, PS setup,
host, memory map and software images. E1 and 25 MHz are out of scope; their evidence is preserved and
untouched.

## The four branches

| branch | architectural difference from its predecessor |
| --- | --- |
| `ips-baseline` | the frozen accepted multicycle core: parcel fetch, no TLB, no cache |
| `ips-fetch32` | aligned 4-byte fetch, with a safe fallback for unaligned and cross-page instructions |
| `ips-tlb` | fetch32 plus a small parameterised fully associative TLB |
| `ips-cache` | TLB plus a small blocking, physically tagged instruction cache |

Frozen geometry, decided before any comparative run and not swept: **TLB** one shared
instruction/data structure, **8 entries**; **I-cache** 1 KiB, direct mapped, 16-byte lines, sequential
refill over the existing interface. I-cache **only** — no D-cache, no write-back, no prefetcher, no
additional outstanding requests, no change to atomic or data-memory ordering. The single-outstanding
strict request/response contract is preserved throughout. No pipeline redesign, no new ISA.

## What "baseline" means, and why it is not "whatever main holds"

`experiments/E1-clock-scaling/INPUTS.json` froze fifteen inputs by hash in order to change exactly one
constant. Those pre-change hashes **are** the accepted 40 MHz configuration, recorded before this
campaign existed and for an unrelated purpose — and E1's own failure is irrelevant, because only the
*before* side is used.

`tools/verify_baseline_identity.py` checks the working tree against them and against
`intended_delta.sha256_before` for `clocking.vh`, so the claim is executable rather than asserted:

```
BASELINE_IDENTITY match=15 differs=0 missing=0 of 15; clocking.vh = accepted (40 MHz)
  the working tree IS the accepted 40 MHz configuration
```

## Measurement contract

**Counters.** Core `mcycle`/`minstret` (`cycle`/`instret` in S-mode) read either side of the ROI. They
count **retirement**, not fetches and not offered requests. Zero, invalid or wrapped readings are
rejected, never repaired.

**Primary microbenchmark metrics.** Δinstret, Δcycle, `CPI = cycles/instret`,
`IPS = instret × 40,000,000 / cycles`, and target ROI time `= cycles / 40,000,000` seconds. Every stage
reports absolute IPS, gain against baseline **and** gain against its immediate predecessor.

**Things that are not the metric.** Simulation wall speed is not CPU IPS and is never reported as such.
Application wall time is a separate end-to-end number that includes console transport and the TSI
round-trips fesvr serves for block I/O. Where trustworthy application ROI counters are unavailable,
IPS and CPI are **null with a reason** — never inferred from how long the host waited.

**Separation.** Simulation and hardware results are never pooled. ≥3 successful samples per
workload/config/platform; every attempt is reported, with median and min/max.

**Cold versus steady state.** Cold-cache/TLB and steady-state ROIs are defined and reported separately.
Every sample records the reset, `fence.i` and `sfence.vma` actions taken, and any warm-up excluded from
the ROI. Raw logs, workload hashes, platform clock and session id are retained per sample.

**Reuse.** Existing B0 data is reused only where the identity, window and repetition policies match.
Where they do not, the gap is recorded — data is not relabelled to fit.

## Frozen workload set

| workload | what it separates | state |
| --- | --- | --- |
| `perf03_fetch` | 32-bit versus compressed fetch | existing, frozen |
| `perf04_where` | CLINT versus DDR | existing, frozen |
| `perf02_sv39` | page walks / Sv39 | existing, frozen |
| `perf01_cpi` | ALU / load / store baseline ROIs | existing, frozen |
| `perf05_size` | access size | existing, frozen |
| **`perf06_iws`** | a deterministic instruction working set **larger than 1 KiB**, so the I-cache stage has something it must miss in | **to be written**; must run unchanged on baseline |
| `b0compute` / `b0array` / `b0file` | applications, end-to-end | existing, frozen |

Every probe's ELF hash is in `manifest.json` and must match across variants. Fresh disk per application
sample. One target hart.

## Rules of engagement

Isolated worktrees only; the shared `riscv-lab` checkout is never switched. Accepted sources are
read-only inputs. Original milestone binaries, B0 records, E1 records and `EXECUTION.md` are not
overwritten. Scoped commits with attribution; no push, no release, no force-moving existing refs, no
merging into shared main.

Jobs over two minutes are registered. One heavy build or simulation at a time; at most four compile
workers; `vivado` is claimed for synthesis and implementation. Each simulation attempt carries a cycle
limit and a wall timeout (≤6 h); each Vivado attempt ≤8 h. **A timeout is a result, never a pass.** No
automatic unchanged retries — logs are preserved and the failure diagnosed before anything is changed.

**No hardware programming is authorised by this assignment.** Each bitstream needs independent review
and a user-coordinated physical cold cycle. Power removal is never attested on the user's behalf; no
hot reload, no clearing of unknown locks, no board OS/network/SD edits. When blocked only on board
access, downstream offline work continues and the stage hands off `READY-FOR-BOARD` — simulation is not
repeated to fill time.

## Definition of done

Four traceable branches; reproducible configuration, build and test commands; passing functional
evidence; timing and resource tables; raw per-sample records; and a generated IPS/CPI/application-time
comparison against baseline with incremental speedups. Each stage's status states explicitly which of
**IMPLEMENTED / SIM-VERIFIED / BUILD-VERIFIED / BOARD-VERIFIED / PERFORMANCE-MEASURED** it has reached.
The hardware IPS comparison is not complete until all four variants have valid board samples.

There is **no required speedup**. An optimisation that is correct and slower is a valid result. Probes
are not selected for being favourable and failures are not hidden.
