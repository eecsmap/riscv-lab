# Metric definitions

Every number in this tree is defined here or it does not belong here. Where a quantity is *measured*, the
measurement window is stated exactly; where it is *derived*, the derivation is stated and it is labelled
as derived. These are not the same kind of thing and are never mixed in one column.

## 1. Three kinds of statement, kept apart

| kind | meaning | example |
| --- | --- | --- |
| **measured** | read from hardware or simulation counters in a defined window | `cycles = 1210032` for the perf01 ALU loop on the board |
| **RTL fact** | established by reading the source, reproducible by anyone with the tree | `tcpu_core.v` issues `core_req_size = 2'd1`, one 16-bit parcel per fetch |
| **model-derived** | computed from measurements under a stated model | one memory round-trip `L ≈ 17.7` cycles, from `CPI32 - CPI16 - 1` |

A model-derived value inherits every assumption of its model. It is never presented as measured, and two
model-derived values obtained from different measurements are **not** interchangeable: `L` inferred from
perf03 and `L` inferred from perf04 are separate estimates that happen to be close, and substituting one
into an accounting built on the other, then calling the result exact, is not allowed.

## 2. The region of interest (ROI)

Every microbenchmark's ROI is the window between two counter reads:

```
csrr  <a>, cycle        <- not in the window
csrr  <b>, instret      <- the instret window OPENS after this instruction's own read
<loop body> x ITERS
csrr  <c>, cycle        <- inside the window
csrr  <d>, instret      <- the instret window CLOSES before this instruction's own read
```

* `cycles = c - a`
* `retired = d - b`

**Counter read overhead is inside the ROI and is not subtracted.** `minstret` is read before its own
retirement increments it (`tcpu_csr.v`: `rdata = minstret` in the access cycle, `retire` increments at the
end), so the retired count over the window is

```
retired = ITERS * (instructions per iteration) + 2
```

the `+2` being the `csrr b` and `csrr c` that fall inside. For the loops here, 3 instructions per
iteration and `ITERS = 10000`, so **30002**. Every probe asserts this and refuses to report if it differs:
a window that retired something else did not run as described, and its cycle count is a number about some
other program.

At 30002 retired the two counter reads are 0.007 % of the window. No overhead correction is applied.

`cycle`/`instret` (0xC00/0xC02) are used rather than `mcycle`/`minstret` wherever a probe runs in S-mode,
because the M-mode counters are inaccessible there; `mcounteren.CY|IR` is set in M-mode first. The two
alias the same registers.

## 3. CPI

```
CPI = cycles / retired          (both from the same ROI, same sample)
```

Numerator and denominator always come from **one sample of one workload**. CPI is reported per workload
per configuration. A CPI is never averaged across workloads, and **no average of these CPIs is xv6's CPI**
— see ERRATA.md, correction E4.

## 4. Throughput

Two different things, never conflated:

| name | definition | kind |
| --- | --- | --- |
| **derived IPS** | `configured_hz / CPI` | **model-derived** |
| **measured wall throughput** | `retired / wall_seconds` | measured, but only where wall time is recorded for the ROI alone |

Every IPS figure in B0 is **derived**. The probes do not time their own ROI against a wall clock, so B0
reports no measured wall throughput for microbenchmarks. Application workloads report **wall time only**,
because obtaining target-side cycles for them would require privilege or kernel changes that are out of
this task's scope.

`configured_hz` is 40 000 000, and it is **configured, not measured**: 125 MHz oscillator on pin H16
(`create_clock -period 8` in the board constraints) through an MMCM at ×8/25. Each manifest records
`frequency_source: "configured"` for this reason. No probe here measures absolute frequency.

## 5. Ratios

A ratio is only formed between two results that share workload shape, platform, configuration and
statistic. The denominator is named in the same row. A ratio between a measured result and a
model-derived one is labelled as such, and **a ratio between two loops is not the speedup of an
optimisation** — see ERRATA.md, corrections E3 and E5.

## 6. Wall time

For application workloads, wall time is taken on the **host**, from immediately before the command is
written to the console to immediately after its completion marker is framed. It therefore includes console
transport and the target's own execution and cannot be attributed to either. It is recorded as
`wall_seconds` with `includes_transport: true`.

## 7. Samples, timeouts and exclusions

* a finite timeout is set and recorded **before** any run; it is part of the manifest, not a note added
  afterwards;
* every sample's outcome is recorded — success, timeout, wrong marker, wrong retired count, non-zero exit
  — with the reason. Failed samples are retained in `raw/` and counted;
* a metric is reported as **median**, with **min and max**, over the successful samples, and the
  successful-sample count is always shown. Mean is not used;
* a missing or unsupported metric is `null`. **Never zero**;
* samples are **not** rerun until a required count of successes appears. If successes fall short of the
  policy the shortfall is reported as a shortfall.

Sample policy for B0: microbenchmarks **≥ 5** samples, application workloads **≥ 3**.

## 8. Same-session repeats vs cold boots

Every sample records `boot_id` and `session`. Repeats within one board power-on are **same-session
repeats** and demonstrate only short-term repeatability. A figure reproduced across independent cold boots
is marked separately. B0 does not claim cold-boot reproducibility for any figure unless the samples' boot
ids differ, and says so where they do not.

## 9. Statuses

| status | meaning |
| --- | --- |
| `reported` | measured and recorded here, by one agent, once |
| `reviewed` | independently inspected, recalculated from the raw records |
| `reproduced` | independently re-run and the result obtained again |

These are distinct and a result never advances status by assertion. Everything imported into B0 from the
2026-09-21 session enters as **`reported`**.
