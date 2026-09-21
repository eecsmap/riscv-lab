# Benchmarks

A small, auditable performance baseline for this CPU, so that later optimisations can be judged against
something instead of against memory. It is deliberately not a benchmarking framework: Python's standard
library, a few scripts, and files you can read.

## What is here

| path | what |
| --- | --- |
| `metrics.md` | **the contract.** What every number means, how it is computed, what is measured and what is derived |
| `ERRATA.md` | corrections to performance claims made before B0 existed. History is not edited; it is superseded here |
| `workloads/*.json` | one descriptor per workload: source identity, ROIs, expected retired counts, marker |
| `workloads/src/` | sources for workloads added after the repo's import snapshot |
| `configs/` | platform and configuration descriptors |
| `baselines/B0/` | the baseline itself: `manifest.json` and `REPORT.md` |
| `templates/EXPERIMENT.md` | the shape of a single-variable experiment, for later changes |
| `INSTRUMENTATION-CONTRACT.md` | what counters must mean **if** they are added. None are implemented |
| `tools/` | parser, metric generation, comparison generation, and the negative fixtures for all three |

Measurement runs live in `../experiments/B0-measurement/runs/<run-id>/`, and the flattened table in
`../results/comparisons.csv`.

## The rules that matter

1. **Raw records are immutable.** `raw/` holds verbatim output. Every number is generated from it by
   `tools/gen_metrics.py` and `tools/gen_comparisons.py`. Nothing is transcribed by hand, and if a figure
   is wrong then a raw record or a generator is wrong.
2. **Refusal beats a plausible number.** A record missing its marker, carrying another probe's marker,
   retiring the wrong count, truncated, duplicated, or exiting non-zero is rejected *with its reason* and
   counted as a failed sample. It never becomes a value.
3. **`null` is not `0`.** A metric with no successful samples is null. A workload with no cycle counter
   support reports null, not zero.
4. **Failed samples are kept.** They stay in `raw/` and are counted in `samples_failed`. Samples are never
   re-run until the required number of successes appears.
5. **`reported` / `reviewed` / `reproduced` are different things.** Everything here is `reported` until
   someone else recalculates it or runs it again.
6. **Measured, RTL fact, and model-derived are different things** and are never mixed in a column. See
   `metrics.md` §1.
7. **Ratios are only formed like-for-like.** `tools/gen_comparisons.py:ratio()` refuses across platforms,
   workload shapes, configured frequencies, or against a null metric — the simulator models no PS or DDR
   path, so a board-against-simulator ratio describes neither machine.

## Running the checks

From this repository, with no absolute paths and no hardware:

```bash
make bench-selftest      # the parser and generators against their negative fixtures
make bench-metrics       # regenerate every run's metrics.json from its raw records
make bench-check         # regenerate comparisons.csv into a temp file and diff it against the committed one
make check               # the repository's existing offline checks, unchanged
```

## What B0 is not

It is not a claim about xv6's performance. The microbenchmarks are synthetic loops; see `ERRATA.md` E3.
It contains no optimisation, no counters, no cache, no TLB and no RTL change of any kind.
