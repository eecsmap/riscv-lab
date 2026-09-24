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

## SoC regression — in progress

`tests/run-stage1-soc.sh <outdir>` builds the **same** generated harness against each CPU RTL directory
in turn and runs the **same frozen ELFs** on both. `tests/build-sim.sh` exists because
`teaching-cpu-work/cpu/m3-build-sim.sh` hardcodes `RTL=$WS/cpu/rtl` and that tree is a read-only input;
this is the same build with the RTL directory as a parameter.

### Two findings from the first attempt, both recorded rather than tidied away

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
| 3 | running |

## Status

**IMPLEMENTED** and port-level **SIM-VERIFIED**. The SoC regression, xv6 and the application profiles
are not done. Nothing is BUILD-VERIFIED, BOARD-VERIFIED or PERFORMANCE-MEASURED.
