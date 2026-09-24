# Stage 1 — fetch32

Branch `ips-fetch32`, from the verified `ips-baseline`. The implementation is **reused** from
`opt01-aligned-fetch`, whose review (`claude-opt01-port-fixed-ready`) is still **OPEN**: it is not
assumed accepted, and nothing here treats it as such.

## The delta

Exactly one file changes, `rtl/cpu/tcpu_core.v`, by **41 insertions and 4 deletions**. Every other RTL
file — `tcpu_csr.v`, `tcpu_ptw.v`, `tcpu_cdecode.v`, `tcpu_defs.vh`, `tcpu_muldiv.v`,
`tcpu_regfile.v` — is byte-identical to the accepted configuration, and the baseline `tcpu_core.v`
hashes `09449b24e64440f7`, which is the value E1's frozen inputs record for it.

What it does: when the PC is 4-byte aligned, one request asks for four bytes and the whole 32-bit
instruction arrives in a single response, so `S_IF2_REQ`/`S_IF2_WAIT` are never entered. Under Sv39 the
second page-table walk disappears with it, because a naturally aligned 4-byte access cannot cross a
4 KiB page. The unaligned case is untouched and still fetches and translates the second parcel on its
own.

`fetch_wide_req` is latched **at issue** rather than read back from `core_req_size`, because the
walker's own PTE reads drive that field during a translation — reading it back would be asking a signal
somebody else has since written.

## Port-level regression — PASSED

`tests/run-stage1-port.sh <outdir>`, reviewer-rerunnable from this tree.

```
accepted 09449b24e64440f7
fetch32  de6be6cb3b795d38
mutant   fa7be9ff1f57c4e3
```

| case | result |
| --- | --- |
| the accepted core passes, and **never** issues a 4-byte request | ok |
| fetch32 passes, issues wide requests **under translation**, 0 protocol violations | ok |
| **the mutant FAILS**, having actually reached the translated path | ok |
| injection: the monitor reports violations; the weaker `valid && !ready` monitor sees nothing | ok |
| a withdrawn request is detected, and fails the run | ok |
| | **`PORT_TB_REGRESSION fails=0`** |

The mutant carries the *actual* first-version defect: the post-walk issue asks for two bytes while the
wide-consumption flag is still set. Against a memory that returns a full word regardless it is
invisible; against poisoned lanes it must fail, and it does.

## SoC regression — PASSED (attempt 3)

`tests/run-stage1-soc.sh <outdir>` builds the **same** generated harness against each CPU RTL directory
in turn and runs the **same frozen ELFs** on both.

`tests/build-sim.sh` exists because
`teaching-cpu-work/cpu/m3-build-sim.sh` hardcodes `RTL=$WS/cpu/rtl` and that tree is a read-only input;
this is the same build with the RTL directory as a parameter.

| result | |
| --- | --- |
| seven runnable startup gates, **both cores** | all exit 0 |
| `ext03_a` | exit 2 on **both** cores at the same cycle bound — identical, so not a fetch32 regression |
| `perf03_fetch`, `perf04_where`, `perf06_iws`, both cores | all exit 0 |
| metrics | **12 rows, 0 refused** — every window retired exactly what its descriptor predicts |

### Results (SIMULATOR — never pooled with board figures)

| workload | ROI | baseline CPI | fetch32 CPI | gain | baseline IPS@40MHz | fetch32 IPS@40MHz |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `perf03_fetch` | `insn16` | 11.00 | 11.00 | **1.000x** | 3,636,121 | 3,636,242 |
| `perf03_fetch` | `insn32` | 19.02 | 11.00 | **1.729x** | 2,103,116 | 3,636,287 |
| `perf04_where` | `load_clint` | 21.36 | 13.34 | **1.601x** | 1,872,480 | 2,997,457 |
| `perf04_where` | `load_dram` | 21.36 | 13.34 | **1.601x** | 1,872,471 | 2,997,427 |
| `perf06_iws` | `iws_exceeds` | 19.02 | 11.00 | **1.729x** | 2,103,119 | 3,636,364 |
| `perf06_iws` | `iws_resident` | 19.02 | 11.00 | **1.729x** | 2,103,125 | 3,636,354 |

External AXI reads, per binary (both ROIs of a probe share one run):
`perf03_fetch` 107,348 → 74,407; `perf04_where` 150,962 → 83,272; `perf06_iws` 306,618 → 156,607.

**The compressed path is 1.000x.** 330,044 cycles against 330,033 — eleven cycles in a third of a
million, 0.003%. The change is confined to 32-bit fetch exactly as the design says, and that is a
stronger correctness statement than the speedup is a performance one.

**`perf06`'s two ROIs are identical on both cores**, 19.02 and 11.00 alike. That is what
`ROI-POLICY.md` says must happen on a core with no cache — "if cold and steady differ on a stage with
no cache and no TLB, the probe is measuring something other than what it claims". They do not differ,
so the probe is validated before the stage that needs it exists.

`perf04`'s 1.601x is lower because its loop does data loads as well as fetches; the fetch saving is
diluted, which is the expected shape rather than a disappointment.

**These are simulator cycles.** The same `perf03` 32-bit ROI reads CPI 19.02 here and **40.34 on
hardware**: the simulated memory is not PS DDR. Nothing here is a board figure.

### Findings recorded rather than tidied away

**The harness traces every event and cannot be told not to.** `TeachingCpuSoc.scala` emits a Chisel
`printf` per REQ/RESP/COMMIT/TRAP and per AXI beat, gated only by `PRINTF_COND`, which this build
defines as always true. One run produced **300 MB in thirteen minutes**. `tests/trace_aggregate.py`
now streams it: every event counted exactly, every **non-trace** line — the probe's own output and its
verdict — kept verbatim, and a bounded head and tail of the raw trace kept for diagnosis.

That trace is not a nuisance; it is the observability the later stages need. `EVA:AR` counts external
AXI reads directly, which is how "fewer external instruction reads" will be measured in stage 3, there
being no hardware counter for it.

**`ext03_a` does not complete in this SIM configuration — on the BASELINE core.** It ran past
**11,161,226 cycles** with a trap every ~28 committed instructions. The established M3 sim regression
only ever ran `boot01`–`boot04`; `ext01`–`ext04` were built for **hardware**, where all eight pass, and
were most recently re-verified 8/8 during the 2026-09-24 restore. So this is a property of atomics in
this SoC configuration, not a fetch32 regression. It is measured on both cores and reported, not
required and not hidden.

### Attempts

| attempt | outcome |
| --- | --- |
| 1 | stopped deliberately: a 300 MB log and growing, from an oversized `+max-cycles` combined with the unconditional trace. Diagnosed before changing anything. |
| 2 | died on a harness bug of mine in every run: `local core=$1 prog=$2 d=".../$core-$prog"` word-expands the whole line before `local` runs, so `$core` is unset and `set -u` aborts. No simulation happened. |
| 3 | **completed, 0 fails** after the gate list and bounds were corrected from attempt 1's measurements |

## A third finding: the probe console is interleaved character by character

The probe writes its console through HTIF one character at a time, and each character lands in stdout
wherever it falls — so a line reads `TEVA 1564 R id=0 ...`, where the leading `T` is the probe and the
rest is the trace. The first aggregator matched `^EV`, which is true of neither, and a marker spread
over eight lines matched nothing: every marker comparison failed while every probe had in fact passed.

The trace is now found **anywhere** in the line and what precedes it is kept as the probe's own output.
That is the same approach `xv6-drive.py` already takes, which is reassuring — it is the established
reading of this stream, not an invention. No simulation was repeated: the data was recoverable from
what had already been written.

## Status

**IMPLEMENTED**, and **SIM-VERIFIED** at port level and at SoC level with metrics.

Not done: xv6 with the frozen `b0apps` profile (running), and the baseline xv6 comparison. Nothing is
BUILD-VERIFIED, BOARD-VERIFIED or PERFORMANCE-MEASURED — no bitstream has been built and no hardware
has been touched by this campaign.
