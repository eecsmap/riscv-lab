# Errata: corrections to performance conclusions stated before B0

The original measurement session of 2026-09-21 is recorded in
`evidence/xv6-board-run-3/` and in the workspace document `PERF-MEASURED.md`. **Those records are not
edited.** They are what was written at the time, and rewriting them would destroy the only account of what
was believed when. The corrections below supersede them.

Raised by Codex in review of `claude-perf-probe-ready`; all five are accepted.

---

### E1 — the perf03 model must keep its extra state, and its `L` is its own

The model is

```
CPI16 = F + L
CPI32 = F + 1 + 2L
```

where `F` is the fixed FSM cost and the extra `1` is `S_IF2_REQ`, the state that issues the second
parcel's request. Hence `L = CPI32 - CPI16 - 1` and `F = CPI16 - L`.

Dropping the `+1` inflates `L`. And the `L` inferred here (**17.71**) is *this model's* estimate; the `L`
inferred from perf04's DRAM load (**18.73**) is a different estimate from a different measurement. They
are close, which is reassuring, but **substituting one into an accounting built on the other and calling
the total exact is not permitted.** The earlier write-up did exactly that when it presented
`4 + 2 × 18.7 = 41.5` against a measured 40.3.

### E2 — DDR minus CLINT is a path difference, not a latency isolation

perf04 measures a load from DRAM (+19.73 cycles) and a load from the PL-internal CLINT (+7.84). The
difference, 11.88 cycles, is **the difference between two complete access paths to two different
peripherals**. It is *not* the latency of the PS and DDR segment, and the CLINT figure is *not* "the PL
portion of the DRAM path": the CLINT is a different device with its own response behaviour, and nothing
here shows the DRAM path shares the CLINT path's first portion.

What the comparison does support: a DRAM access costs substantially more than a fabric-local one, and the
simulator does not model that difference at all (7.33 vs 7.04 there, against 19.73 vs 7.84 on the board).

### E3 — 161.26 is an ALU-loop CPI, not xv6's average CPI

CPI **161.26** is the perf02 three-instruction 32-bit ALU loop under Sv39 with 4 KiB pages. It is **not**
xv6's average CPI and must not be quoted as one. Real xv6 executes a mixed instruction stream — including
**compressed instructions, which take one parcel fetch rather than two** — with loads, stores, branches,
traps and I/O waits in proportions this loop does not represent.

**xv6's average CPI is unmeasured.** No figure in this repository is it.

### E4 — "eight reads per instruction" has a scope

`2 parcels × (3 PTE reads + 1 fetch) = 8` describes **a successful, normal, 32-bit instruction fetch under
4 KiB three-level translation**. It does not describe every retired xv6 instruction: compressed
instructions halve the parcel count, a fault or a trap takes a different path, and the figure says nothing
about data accesses beyond the fetch.

### E5 — 1.87× is a loop comparison, and the megapage result is not an xv6 huge-page result

**1.87×** is the ratio between a compressed-instruction loop and a 32-bit-instruction loop (CPI 21.61 vs
40.32). It is **not** the measured speedup of a 32-bit aligned-fetch optimisation, which **does not
exist** — no such change has been implemented, and nothing here measures one.

Likewise the 1 GiB-megapage probe (CPI 82.63 against 161.26) measures **the synthetic loop** under two
mappings. It does **not** establish what xv6 would gain from huge pages.

Both remain interesting as *hypotheses* about where time goes. Neither is a result about an optimisation.

---

## What survives unchanged

* the RTL facts: parcel-at-a-time fetch (`core_req_size = 2'd1`), a second request at `pc+2` via
  `S_IF2_REQ`, an independent walk for the second parcel under Sv39, and no TLB or PTE cache in
  `tcpu_ptw.v`. These are read from the source, not inferred from timings;
* the measured cycle and retired counts themselves, which are in `raw/` and unaltered;
* the RTC divider measuring 100, hence `mtime` at 400 kHz against a device tree declaring 1 MHz.

---

### E6 — what perf05 shows, and what it does not

Added 2026-09-21 after Codex's review of the B0 candidate.

perf05 measured 1-, 2-, 4- and 8-byte loads and 1- and 8-byte stores at **one repeatedly-hit, naturally
aligned address**, and found their costs within 0.4 % of each other. The correct statement of that result
is: **no resolved sub-word latency penalty was observed under this workload.**

It does **not** establish:

* **the absence of internal read-modify-write.** A read-modify-write whose extra work is hidden behind the
  same round-trip latency — which is plausible, given the round-trip dominates — would be invisible to
  this measurement. `sb` costing what `sd` costs is consistent with byte strobes *and* with a concealed
  RMW;
* **that widening an access is cost-free in general.** The result is bounded to sizes that fit within one
  64-bit beat, at an aligned address, with one access outstanding. Nothing here measures an unaligned
  access, a size crossing a beat, a burst, or behaviour under contention.

The conclusion drawn from it elsewhere — that a wider *fetch* gains only from the requests it eliminates
— stands for the 2→4 byte case actually measured, and should not be generalised beyond it.
