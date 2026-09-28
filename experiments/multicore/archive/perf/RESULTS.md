# MC-PERF RESULTS — fixed-workload 1-core vs 2-core on the PYNQ-Z1 (2026-09-28)

Both configurations: 40 MHz, 128 MiB, per-core fetch32 + 8-entry TLB + 1 KiB I-cache, the same measurement kernel
`kernel-perf-128mib` 133f5b72…, the same `fs-perf.img` d558e444… (fresh copy per boot), the same `fesvr-teaching-static`.
Time = shared CLINT mtime (core clock / 100 = 400 kHz), read by `mtime()` before the first fork and after the last wait.
Each number is one program run; 4 children per run; judge `perf_check.py` PASS on both records (default rules: ≥ 2,000,000 units).

| configuration | payload in the PL | cold boot | gates | run record |
|---|---|---|---|---|
| 1 core (the user's cache stage) | **79a114ae…** (bit e546c0dd…) | e6930db4… | 8/8 + perf probes 3/3 (production `ips-install.sh cache`) | `sessions/session-restore-cache-20260928T050004Z/xv6-perf-board-20260928T051330Z` |
| 2 cores (M4/M5 dual) | **43e5b414…** (bit 4ecccd05…) | a1b62d8e… | 6/6 dual gates (`m5-install.sh dual`) | `sessions/session-dual-20260928T041829Z/xv6-perf-board-20260928T043607Z` |

| workload | size/child | total work | n | T1 median (range) s | T2 median (range) s | throughput 1-core | throughput 2-core | S2 = T1/T2 | E2 = S2/2 |
|---|---|---|---|---|---|---|---|---|---|
| PERF-ARRAY | 128 | 8,388,608 element updates | 3/3 | 40.548 (40.540–40.551) | 20.530 (20.221–20.542) | 206,883 element updates/s | 408,600 element updates/s | **1.975** | 0.988 |
| PERF-COMPUTE | 2,000,000 | 8,000,000 iterations | 3/3 | 26.588 (26.579–26.588) | 13.064 (13.057–13.101) | 300,888 iterations/s | 612,377 iterations/s | **2.035** | 1.018 |

Raw dmtime (mtime units, 2.5 µs each), in run order:
- compute: 1-core 10,635,175 / 10,631,716 / 10,635,172; 2-core 5,222,752 / 5,240,406 / 5,225,538
- array: 1-core 16,215,854 / 16,219,028 / 16,220,441; 2-core 8,088,318 / 8,212,055 / 8,216,646

Run-to-run spread: 1-core ≤ 0.04 %; 2-core compute 0.3 %, array 1.6 % (the first array run on 2 cores was 1.5 % faster than the other two).

Diagnostics (per run): `readcost` (one `mtime()` round trip) 189–191 units on 1 core, 213–216 on 2 cores (≈ 19,000 / 21,400 cycles ≈ 0.48 / 0.54 ms);
kernel `ticks` 425–426 / 648–649 (1 core) and 209–210 / 324–329 (2 cores) against dmtime/25000 = 425.4 / 648.7 and 208.9–209.6 / 323.5–328.7:
consistent with the under-count-only rule. `mtimetest`: reads monotonic, child within the parent's window on both boards;
single-process spin of 100,000 iterations: 140,948 units on 1 core, 132,456 on 2 cores (141 vs 132 cycles/iteration; see REPORT §6).

Resources (M4 post-route): LUT 14,554 → 22,631 (+8,077, +55 %), FF 7,011 → 11,181 (+4,170, +59 %); BRAM 0 → 0, DSP 0 → 0.

**S2 (median T1 / median T2): compute 2.035, array 1.975; E2 = 1.018 / 0.988.** No threshold was set; these are the measured ratios
with their ranges above. The board is back in the user's configuration (79a114ae…, 8/8 gates) — it was the second boot.
