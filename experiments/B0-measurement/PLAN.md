# B0 measurement: plan and what actually happened

Written against `benchmarks/templates/EXPERIMENT.md`, with the outcome recorded afterwards in the marked
sections. B0 is not an experiment on a change — it is the establishment of the thing later experiments
will be measured against — so "the single variable" is empty by design.

## Hypothesis

None. B0 tests nothing. It records what this CPU does now, with enough identity bound to each number that
a later run can be compared with it or shown not to be comparable.

## Baseline

B0 *is* the baseline. Its constituents:

| run | platform | samples | purpose |
| --- | --- | --- | --- |
| `2026-09-21-board-s3-historical` | board | 1 each | provenance: the original session, imported verbatim. **Below policy; not part of the baseline figures** |
| `2026-09-21-board-s3-b0` | board | 5 each | the baseline figures |
| `2026-09-21-sim-boot3` | simulator | 3 each | a deterministic reference on the same binaries |

## The single variable

Not applicable.

## Invariants

Held constant across the board runs, and verified live before access rather than assumed from logs:

| invariant | value |
| --- | --- |
| bitstream | `2cd8a992…`, unchanged and already configured; **no PL reload** |
| probe binaries | the four ELF hashes, re-verified on the board immediately before the samples |
| boot session | `ebeab8a6-…`, uptime ~10 h continuous — **the same session as the historical run** |
| host state | no fesvr process, no remote lock, adapter `0x00080E00`, `drain_timeout=0` |
| frequency | 40 MHz configured |
| transport | serial console, exclusive channel |

**Not held constant, and therefore a limit:** independent cold boots. Every board figure is a
same-session repeat.

## Correctness gates

Each probe asserts its own retired count and prints a completion marker; the parser re-checks both and
refuses the record otherwise. A sample that fails a gate is retained and counted, never re-run to reach a
target number of successes.

Result: **65 board sample-parses, 0 failures; 39 simulator sample-parses, 0 failures.**

## Measures

CPI per ROI as median with min and max over successful samples; derived IPS as `configured_hz / CPI`,
labelled model-derived. Timeouts set before the runs: 120 s per probe (180 s for `perf02_sv39`), with a
60 s harness margin. See `benchmarks/metrics.md`.

## What happened

* board: 4 probes × 5 samples. All 20 completed; spread ≤ 0.14 % of the median;
* simulator: 4 probes × 3 samples, **byte-identical measurement values across all three** — the platform
  is deterministic, so further repeats would only inflate a count;
* three application workloads were written and built, and **not executed** — see the blocker in
  `benchmarks/baselines/B0/REPORT.md`;
* two defects were found and fixed while building the pipeline, both in the pipeline rather than the CPU:
  the parser checked for a success marker before checking whether the probe had reported FAIL, so a
  self-rejected measurement was reported with the wrong reason; and the sample sidecars were written with
  `bc` output like `.9068`, which is not valid JSON. The second was repaired as a syntax fix with no
  value altered.

## Limits

Listed in `benchmarks/baselines/B0/manifest.json` under `limits`, and restated in the report. The ones
that matter most: same-session only, derived IPS only, synthetic loops only, and no application coverage.
