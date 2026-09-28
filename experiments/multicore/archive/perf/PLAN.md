# MC-PERF — fixed-workload single-core vs dual-core measurement: PLAN (offline preparation; nothing here touches the board)

Task: `codex-mc-fixed-work-prep` (2026-09-27). Board operations in §5 are a PROPOSAL and need the user's hand-back and
authorisation again before anything runs on hardware.

## 1. What is compared
| | single core | dual core |
|---|---|---|
| bitstream / payload | IPS cache stage, bit e546c0dd… → **payload 79a114ae…** (the user's current configuration) | M4 dual, bit 4ecccd05… → **payload 43e5b414…** |
| per core | fetch32 + 8-entry TLB + 1 KiB I-cache, no D-cache, 40 MHz | identical per core; two harts, one shared serial atomic backend |
| kernel | the MEASUREMENT kernel `sw/out/kernel-deploy-128` **133f5b72…** = the M5 deployment kernel + one read-only syscall `mtime()` (Codex timebase fix; NOT byte-identical to the accepted 33021237…, frozen in `sw/out/sha256.txt`; NCPU 8: on one hart it never sees hart 1) | same file |
| disk | `fs-perf.img` **d558e444…** = the M4 deployment disk's programs + `perfcompute`, `perfarray`, `mtimetest`; a FRESH copy per boot | same file |
| host | `fesvr-teaching-static` c050eab3… | same |
| resources (M4 report, post-route) | LUT 14,554 / FF 7,011 | LUT 22,631 / FF 11,181 (+8,077 LUT = +55 %, +4,170 FF) |

## 2. The two workloads (`sw/xv6/user/perflib.h`, `perfcompute.c`, `perfarray.c`)
Both: the parent forks **4 children** (4 independent address spaces), each child does 1/4 of a FIXED total work, sends its
checksum to the parent through a pipe, exits; the parent waits for all four and is the only process that prints.
- **compute**: per child `size` iterations (default 2,000,000) of the dependency-chained LCG mix used by the accepted m3par/m3par2
  (`m3compute_nocpu`): no explicit data-array access (instruction fetch, stack and page-table traffic still exist), no syscalls in the timed work. Total 8,000,000 iterations.
- **array**: per child a private 128 KiB uint64 array, `size` passes (default 128) with stride 7 (b0array's access pattern),
  read-modify-write every element every pass. Total 4 × 128 × 16,384 = 8,388,608 element updates (plus one initialising pass per child) through the TLBs to the shared backend.
- Each child also runs one initialising pass over its array before the timed passes are counted as work (it is inside the timed region, listed separately, not counted as "updates").
- `argv[1]` overrides `size` for the short simulation only; the judge refuses any size other than the profile's expected one. Short-sim totals: compute 4 × 20,000 = 80,000 iterations; array 4 × 1 × 16,384 = **65,536 updates** (+ 65,536 initialising writes).

## 3. Timing (revised after Codex's timebase review)
`mt0 = mtime()` immediately before the first fork, `mt1 = mtime()` after the LAST wait returns; `dmtime = mt1 - mt0` is printed by the
program in raw mtime units. Excluded: kernel boot, `exec` of the benchmark itself (before mt0), and all console output (after mt1; the
parent prints only after mt1). Included: fork of the four address spaces, the children's work (array: initialising pass + timed passes)
and exit, the pipe transfers and the four waits.
- **Time base = the shared CLINT `mtime` register**, read by a new read-only syscall (`sys_mtime`: one naturally aligned 64-bit load
  through the kernel's existing identity mapping of the CLINT, `kvmmap(CLINT_BASE, 0x10000)`; S-mode MMIO read on the same path the
  kernel already uses). mtime is free-running at core clock / 100 (`int_rtc_tick = value == 7'h63`, one `rtcTick` for both builds) →
  **400 kHz at 40 MHz, 2.5 µs per unit**. Both boards run at 40 MHz, so units convert to seconds identically. Nothing in `timervec`,
  interrupt handling or scheduling is changed; no MMIO is mapped to user space; no new RTL; `rdtime` is not assumed.
- **Why not the kernel tick**: `timervec` rearms `mtimecmp` from the CURRENT mtime (`kernelvec.S`), so a late timer interrupt absorbs
  the delay and `ticks` counts services, not elapsed time; under load (and differently under two-hart contention) it under-reads. The
  earlier "±1 tick, ≤ 1 %" claim is **withdrawn**. `uptime()` is still printed (`ticks=`) as a diagnostic; the judge only requires
  `ticks ≤ dmtime/25000 + 1` (ticks can under-count, never over-count).
- Resolution and overhead: one unit = 2.5 µs. The program prints `readcost` = the difference of two back-to-back `mtime()` calls
  (the syscall trap + MMIO load + return); the judge refuses if it exceeds 100,000 units and reports it. Expected regions are seconds,
  so report quantisation and the measured readcost/region ratio separately. Twice the observed simulation readcost (131–136 units) is about 0.014% of the minimum region, not a guaranteed board bound. The 100,000-unit rejection ceiling alone does not guarantee negligible overhead. Minimum accepted region: **2,000,000 units = 5 s**.
- No instret differences across harts are used (there are no per-hart user counters on the board; not claimed).
- `mtimetest` (also in the board profile) checks on each boot: 8 consecutive reads monotonic (and their deltas = read cost), a child's
  read lies within the parent's before/after reads (one time base shared across processes/harts), and ticks ≤ elapsed mtime.

## 4. Metrics (per configuration, per workload, ≥ 3 repetitions; `tests/perf_check.py` (default `--mtime-hz 400000`, `--min-dmtime 2000000`))
median and range of dmtime and seconds; throughput = total work / seconds (iterations/s, element-updates/s);
S2 = T1(median) / T2(median); E2 = S2 / 2; resource increment from §1. **No threshold is set**: whatever S2 is, it is reported with
its range. The M5 hardware evidence for "two harts" is the six bare-metal gates plus xv6's `hart 1 starting` and the completion of
concurrent programs; M5 did NOT measure speed-up and this plan does not claim any until these runs exist.

## 5. Proposed board procedure (needs fresh authorisation; 2 cold power cycles by the user; ends in the user's configuration)
Same tooling as M5 (`m5-board/board`, isolated copies; production `ips-*.sh cache` for the single-core install):
1. cold cycle #1 → `m5-install.sh dual` (6 gates) → runner `perf-board` on the same boot with `kernel-dual-128mib` + fresh
   `fs-perf.img` (3 × perfcompute, 3 × perfarray). Est.: install ~15 min (serial deploy) + gates 1 min + run ≈ 3 min + 6 × T2.
2. cold cycle #2 → production `ips-install.sh cache` (8 gates, perf probes; this IS the restore to 79a114ae…) → deploy
   `kernel-dual-128mib` + fresh `fs-perf.img` → runner `perf-board` (6 × T1). Est.: ~25 min + 6 × T1. The board is left in the user's
   configuration with its 8 gates re-verified; no third cycle is needed. The production `ips-restore.sh` and the "20fae71e…" wording at
   the end of `ips-install.sh` refer to the OLD campaign's reference image; they are not used and not required (Codex, M5 verdict).
Size calibration from the dual short sim (`runs/sim-dual-short`, first version: 80,000 iterations in 4 kernel ticks, 65,536 updates + 65,536 initialising writes in 6 ticks; ±1 tick each and the tick under-counts, so the estimate is coarse and includes the fixed fork/exit/pipe cost): compute ≈ 125 cycles/iteration and array ≈ 115 cycles/element-op with two harts. Rough board expectation at the full sizes: T2 ≈ 25 s each, T1 ≈ 50 s each if the speed-up were 2, T1 = T2 ≈ 50 s if it were 1 — either way ≥ 5× the 5 s minimum. **These are sizing estimates only**: the simulator's memory model is not the PS DDR (latency and refresh unmodelled), fork/initialisation are fixed costs, and nothing here is a board time prediction. Estimated total wall: ≈ 60–75 min plus the two user power cycles.

## 6. Verification without hardware (this deliverable) — see REPORT.md
Short dual (N=2) and single (N=1) simulations of `perf-short` (`mtimetest`, `perfcompute 20000`, `perfarray 1`) with the same kernel/programs;
judge PASS on both; `perf-check-selftest.sh` mutations (ok=0, 3 children, missing/duplicated/MISSING child, wrong checksum ×2,
too-short / inconsistent / backwards dmtime, ticks exceeding the hardware delta, huge read cost, runs out of order, mtimetest non-monotonic / child outside / ticks / spin checksum / missing, wrong size, no DONE, runner rc, stop record) all refused. Python reference checksums reproduce
the accepted m3par2 values (f6d983767e3c5638 / 01d86a21f972f3fa).
