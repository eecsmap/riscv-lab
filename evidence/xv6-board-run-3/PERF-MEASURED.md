# Measured: CPI, instruction throughput, and what a load and a store cost

claude, 2026-09-21. `perf01_cpi.elf` sha256 `e5250f5035787a26b41389e20a932890d4c4e116fc87c403c4cea5826925df96`,
run on the board in the accepted configuration (teaching bitstream already programmed, no PL reload, no
power cycle). Raw output: `logs/10-perf01.txt`. Marker `TEACHING-PERF-OK`, rc 0 — so every loop retired
exactly the instructions it was supposed to, and these numbers are about the loops described.

Read from the core's own `mcycle`/`minstret`. Nothing here is estimated.

| | board | simulator |
| --- | --- | --- |
| CPI, ALU only (no data access) | **40.33** | 19.39 |
| CPI, one load added | **46.69** | 21.84 |
| CPI, one store added | **46.18** | 21.84 |
| one load | **+19.09 cycles** | +7.33 |
| one store | **+17.53 cycles** | +7.33 |
| RTC divider | **99.99** | 99.99 |

At 40 MHz (125 MHz oscillator on H16 through the MMCM at ×8/25):

| workload | CPI | throughput | per instruction |
| --- | --- | --- | --- |
| ALU only | 40.33 | **0.99 MIPS** | 1008 ns |
| with a load | 46.69 | 0.86 MIPS | 1167 ns |
| with a store | 46.18 | 0.87 MIPS | 1154 ns |

**So roughly one million instructions per second**, bare-mode, no paging.

## Where it goes

The ALU loop touches no data memory at all, and still costs **40 cycles per instruction**. The core's FSM
path for a register-register instruction is about five states, so the other ~35 cycles are the instruction
fetch going to DDR — every time, because there is no instruction cache. Fetch is the bottleneck, and it is
not close: adding a data read costs only 19 cycles on top of that.

That a data read (19) is cheaper than an instruction fetch (~35) is worth a second look rather than an
explanation invented here; separating fetch latency from fixed FSM cycles needs another probe variant.

The structural reasons are all in the RTL, and none of them are accidents — this is a teaching core:

* `tcpu_core.v` is a **multi-cycle FSM**, one instruction at a time, not pipelined;
* "no instruction cache, no store buffer and one in-order outstanding access";
* `tcpu_ptw.v`: "Serial, no TLB, no cache: one 8-byte PTE read per level".

The last one is why these figures are an **upper bound** for xv6, which runs under Sv39. With no TLB,
every fetch needs a three-level walk before it can even begin, and every load or store needs another —
about four memory round-trips per instruction instead of one. Measuring that is `perf02_sv39`, proposed
but not built.

## The timebase discrepancy, now confirmed on hardware

The RTC divider measures **99.99**, i.e. 100, matching `clint_io_rtcTick = value == 7'h63`. So `mtime`
runs at 40 MHz / 100 = **400.0 kHz** while the device tree declares a 1 MHz timebase: **out by 2.50×**.
This was derived from the RTL in `m4-prep/audit/mtime-and-budgets.md` and had never been measured. It is
now measured, on the board, and the audit is right.

Inherited from the baseline, not introduced by the teaching CPU. Software converting `mtime` to real time
using the declared timebase will be out by that factor.

## Status

Pending Codex's independent simulation of the same binary (`OPEN claude-perf-probe-ready`). The board run
is complete and its numbers are above; independent replication is what would make them accepted rather
than merely reported.

---

# Part 2: what translation costs when there is no TLB

`perf02_sv39.elf` sha256 `bc6185566c5de9da7a4dbce1942262dbeb68b1c8e556ac8f72f15fc1465596ab`, same board,
same configuration, no PL reload. Raw output: `logs/11-perf02.txt`. Marker `TEACHING-PERF-SV39-OK`, rc 0 —
all **six** measurement windows retired exactly `ITERS*3+2`.

The same two loops, in one binary, at the same addresses, under three regimes. All three maps are
identity over the gigabyte the image lives in, so nothing moves between measurements.

| regime | board CPI | MIPS | simulator CPI |
| --- | --- | --- | --- |
| bare (`satp=0`) | 40.33 | 0.99 | 19.39 |
| bare, +load | 46.84 | 0.85 | 21.84 |
| Sv39, 1 GiB megapage | 82.63 | 0.48 | 39.84 |
| Sv39, 1 GiB megapage, +load | 96.20 | 0.42 | 45.35 |
| **Sv39, 4 KiB (xv6's regime)** | **161.26** | **0.25** | 73.09 |
| **Sv39, 4 KiB, +load** | **188.09** | **0.21** | 84.23 |

Bare-mode figures reproduce `perf01`'s 40.33 / 46.7 from a separate binary — an independent cross-check
that the two probes measure the same thing.

## The walk, isolated

| | extra cycles per instruction |
| --- | --- |
| one-level walk (megapage, **1** PTE read) | **+42.29** |
| three-level walk (4 KiB, **3** PTE reads) | **+120.93** |
| the two extra levels alone | +78.63, i.e. **~39.3 per level** |

42.3 from the single-level measurement and 39.3 per level from the difference agree to within 7 %. So
**each page-table level costs one independent memory round-trip of ~40 cycles**, which is the same as an
instruction fetch — a PTE read is just another read with no cache in front of it.

That is the whole story of the CPI ladder: **40.3 / 82.6 / 161.3 is almost exactly 1 : 2 : 4**, and those
are the memory round-trips per instruction — one fetch; one PTE plus the fetch; three PTEs plus the fetch.

## What it means for xv6

xv6 runs in the bottom regime. Against bare metal it pays **4.0× on instruction fetch and 4.0× overall**,
landing at **CPI 161, about 248 000 instructions per second**.

Two consequences worth stating plainly, neither of which is a defect — this is a teaching core and
`tcpu_ptw.v` says "Serial, no TLB, no cache" in its first line:

* **a TLB is by far the largest single win available.** It would remove up to three of every four memory
  accesses. Nothing else on this list is close.
* **megapages alone would almost double xv6's speed** (CPI 82.6 against 161.3) without any RTL change, by
  cutting the walk from three levels to one.

## One thing measured but not explained

A data access does not cost the same as an instruction fetch. A load adds **19.5** cycles in bare mode,
where a fetch costs ~40; under Sv39/4 KiB it adds **80.5**, where the model would predict ~160 for three
PTE reads plus the access. The ratio is consistent (4.13×, matching the 4× elsewhere), so it is systematic
rather than noise — but the ~2× gap between the fetch path and the data path per access is **not explained
here**, and it reproduced independently in `perf01`.

Plausible causes include DRAM row-buffer behaviour (the load hits one address every iteration while
fetches stride across three) or overlap in the memory path. Distinguishing them needs another variant —
stride the load address, and separate fetch latency from the fixed FSM cycles. Not done, not guessed at
beyond this.

## Status

Both probes' board numbers are reported, pending Codex's independent simulation of the same binaries
(`OPEN claude-perf-probe-ready`).
