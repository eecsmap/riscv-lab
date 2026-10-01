# PIPE-P4c REPORT — dual-pipeline image on the PYNQ-Z1: install, dual-hart gates, xv6, fixed-work comparison

Task `codex-pipe-p4c-board-validation` (user authorised board takeover, disk backup and replacement of the
single-pipeline image) and `codex-pipe-p4c-cold-cycle-confirmed`. Branch `pipe-dual`, local commits only, no push/tag,
no RTL, no Vivado.

**Status: dual-pipeline image installed and verified on the board; xv6 installed, ready to launch, NOT running.**

| step | result | evidence |
|---|---|---|
| pre-cycle (board read-only) | user disks backed up, hash-verified; boot 4d45136e pinned | `results/precycle/` |
| cold cycle 1 | **refused** at the uptime gate (1811 s > 600 s); nothing deployed | `results/cold-cycle-1-refused/` |
| re-pin + cold cycle 2 | new boot `1e44b36c…`, uptime **9 s**, /root/xv6run absent, no host, NO_LOCK | `results/precycle-2/`, session `boot-id.txt` |
| memory preflight | OK (DT 256 MiB, iomem 0x0–0x0fffffff, no reserved region captured) | `mem-preflight.json` |
| deploy | install: payload, host, 6 gates, 2 frequency programs (10); each xv6 run and the handoff deploy their own; every file hash-verified on the board | `deploy.log` |
| program | `cat pipedual.bit.bin > /dev/xdevcfg` rc **0**, prog_done **1**, payload re-hashed on the board **f330769d…** | `program.txt` |
| dual-hart gates | **6/6** exact marker AND RC=0 | `gates/` |
| core clock vs ARM clock | **40.00 MHz** (39.98–40.00, 3 pairs), mtime = cycles/100, hart1_id = 1 in all 6 runs | `freq/result.txt` |
| xv6 m4smoke | PASS (b0compute, m3par2, m3fs), hart 1 started the kernel | `xv6-m4smoke-*` |
| xv6 perf-board | PASS, 3 runs per workload, all child checksums, hart 1 started the kernel | `xv6-perf-board-*` |
| handoff | launcher check OK; launch / commands / stop / restart (file persisted) / stop PASS on a throwaway disk | `handoff-*` |

All under `results/session-pipedual-20261001T002837Z/` (65 files, `MANIFEST.sha256`; deploy progress lines removed).

## 1. Pinning and frozen execution
* Payload `f330769dac6172da32c3b097ae615d7dde878a9cd2a276835686b1e0de5de7dd`, bit
  `646d88b73b908ad74b76db818cf9692797b3ce1545297c8582b45dd81a65d69a` (P4b `61bde07`, build source `aa24497`,
  `RD2PipeDualBoardConfig`, 40 MHz). Kernels `kernel-dual-128mib` 33021237…, `kernel-perf-128mib` **133f5b72…**;
  disks `fs-dual-deploy.img` d8e50269…, `fs-perf.img` **d558e444…** (a fresh hash-verified copy for every run).
  The sealed set is `board/artefacts.sha256` (14 entries), rebuilt reproducibly by `board/freeze.sh`.
* Every board job ran scripts extracted by `git archive` into `runs/frozen-<commit>/`: pre-cycle `8ea162b`, re-pin
  `c86609a`, install / m4smoke / perf-board / handoff `c86609a`. Nothing was edited while a job ran. Jobs:
  `claude-pipe-p4c-{precycle,precycle2,precycle3,precycle4,install,install2,m4smoke,perf,handoff}`.
* Library: `board/lib/` is a verbatim copy of the accepted MC-M5 dual board library (`board/LIB-DIFF.txt`).

## 2. Cold cycles (both attested by the user, not measured)
* The first confirmation reached me relayed through Codex; it was not recorded. The user then confirmed directly
  (23:58Z). That install found a new boot `82c150fb…` but uptime 1811 s: REFUSE(11). The gate was not changed.
* Re-pin of the empty board took three attempts, all read-only. Two failures were my script defects: `cd
  /root/xv6run` on a fresh boot that has none (62), and an empty file list under `pipefail` (silent exit). Both fixed
  with an offline empty-board rehearsal that the old version fails (`board/selftest/test-precycle-empty.sh`).
* Second cycle confirmed directly at 00:28Z; the install read uptime 9 s.
* prog_done read **1 before programming** on both fresh boots (recorded). Programming is judged by rc + prog_done +
  payload re-hash, never by prog_done alone.

## 3. Dual-hart bare-metal gates (board, exact markers)
| gate | what it shows | board line (abridged) |
|---|---|---|
| dual01_boot | each hart takes its own ROM path and stack | `M2B-BOOT-OK sp1=0x80003000` |
| dual02_clint | timer and software interrupts delivered to hart 1 through its own CLINT slot | `M2B-CLINT-OK mtip0=5 5 …` |
| dual03_lock | lock / LR-SC / AMO counters, both harts contending | `lock=20000 lrsc=20000 amo=20000`, SC failures 4,879 / 4,003 |
| dual04_pbus | per-hart PLIC enable/priority readback | `M2B-PBUS-OK` |
| dual05_fencei | cross-hart code modification; after `fence.i` the new code runs | `nofence=1 fence=2` |
| dual07_long | sustained progress on both harts, identical results | `iter=100000 100000`, equal sums |
The SC failure counts show both harts contending for the reservation at the same time on the board.

## 4. Frequency (core cycles vs the ARM's /proc/uptime)
`freq_spin_dual.S` (new for two harts: hart 1 checks in and parks; validated first in P4a's traced and fast dual
simulators, `results/freq-sim/`). Three pairs, 4e7 / 8.4e8 cycles: f = 40.0000, 40.0000, 39.9800 MHz (±0.10 % from
the 10 ms resolution); cycles/mtime = 100.000 in every run; hart1_id = 1 in every run.

## 5. xv6 (board)
* m4smoke (kernel-dual-128mib, fresh fs-dual-deploy): b0compute `5ADF55920BF7696`; m3par2 children f6d98376…,
  01d86a21…; m3fs ok — identical to the archived dual multicycle (M5) and single-pipeline (P3b) board consoles.
  m3par2's `harts=0x0` field is a **constant** in that program (`r.harts = 0`), not evidence of anything.
* perf-board (kernel-perf-128mib 133f5b72…, fresh fs-perf d558e444…): mtimetest monotonic, the child's read inside
  the parent's window (one shared time base); 3 runs each, every child checksum recomputed by the judge:

| workload | work | runs (s) | median | range |
|---|---|---|---|---|
| perfcompute | 4 children, 8,000,000 iterations | 7.951 / 7.996 / 7.933 | **7.951 s** | 7.933–7.996 |
| perfarray | 4 children, 8,388,608 updates | 8.286 / 8.256 / 8.306 | **8.286 s** | 8.256–8.306 |

* Time base: CLINT mtime = core clock / 100, core clock measured above. The kernel tick is diagnostic only.
* The mtime read cost seen by mtimetest is ~188 mtime units on this image (~125 on the single pipeline, P3b).
  Recorded, not analysed.

### What the board shows about the two harts (and what it does not)
* **Shown on the board:** the six dual-hart gates (both harts executing, contending for the reservation, and making
  equal progress); hart1_id = 1 in every frequency run; xv6's own `hart 1 starting`, printed by hart 1, in every
  xv6 run (`hart_check.py`; the P3b single-hart consoles fail it). The four-child fixed-work times are about half of
  the single pipeline's for compute, which a second hart taking work would explain.
* **Not shown:** which hart ran which child, or per-hart retirement counts. Those exist only in the simulator
  (P4a); the board has no per-hart counter. `hart 1 starting` proves hart 1 booted, not how much of the benchmark it ran.

## 6. Four configurations at 40 MHz, fixed work (median of 3; same kernel 133f5b72, disk d558e444, sizes)
Only **pipeline × 2** was measured in this task. The other three are **archived** board results; nothing was
re-programmed to fill the table.

| configuration | source | perfcompute | iterations/s | perfarray | updates/s |
|---|---|---|---|---|---|
| multicycle × 1 (cache) | archived, MC-PERF (2026-09-28) | 26.588 s (26.579–26.588) | 300,888 | 40.548 s (40.540–40.551) | 206,881 |
| multicycle × 2 | archived, MC-PERF (2026-09-28) | 13.064 s (13.057–13.101) | 612,370 | 20.530 s (20.221–20.542) | 408,602 |
| pipeline × 1 | archived, P3b (2026-09-29) | 15.829 s (15.829–15.833) | 505,401 | 12.696 s (12.691–12.700) | 660,728 |
| **pipeline × 2** | **this task (2026-10-01)** | **7.951 s (7.933–7.996)** | **1,006,163** | **8.286 s (8.256–8.306)** | **1,012,383** |

| ratio of times | perfcompute | perfarray |
|---|---|---|
| pipeline × 2 vs pipeline × 1 | 1.991 | 1.532 |
| pipeline × 2 vs multicycle × 2 | 1.643 | 2.478 |
| pipeline × 2 vs multicycle × 1 | 3.344 | 4.894 |

* These are **fixed-work throughput** numbers for two workloads, not instructions per second. Per-instruction board
  measurements (CPI/IPS probes) exist only for the single-hart images (P3b `ips-compare.md`). No IPS is claimed for
  either dual image, and no general performance claim follows from two workloads.
* Observed, not analysed: the second pipelined hart nearly halves the compute time (1.99×) but gains less on the
  array workload (1.53×). The memory system is unchanged in every build (one outstanding request per hart, a
  shared serial atomic backend, no D-cache).
* Simulation (P4a, mtime units, short sizes) is reported there; it is not used in this table.

## 7. Finding: `pgrep -x fesvr-teaching-static` cannot see a running host on this board
Install step 6b ran `freq_spin_long` in the background and read three detectors while it ran: **pgrep -x = 0**,
comm scan = 1, pidof = 1 (`host-detection.txt`). The host's kernel name is truncated to 15 characters
(`fesvr-teaching-`), so `pgrep -x` with the 21-character name never matches, here or with procps. Consequence:
every `FESVR=` / `F=` "no host running" check built on it — in the production E1 library and all its copies — has
never been able to fire. The host lock has been the effective guard. This task does not change the accepted
library. The P4c steps (`p4c_no_host`) and the user launcher require the comm scan, pgrep and a free lock together.

## 8. Final board state (handoff, boot 1e44b36c)
Programmed: dual pipeline (payload f330769d…). xv6 installed and ready to launch, **not running**: F=0, comm scan 0,
NO_LOCK, no agent lease held, no agent reading the console. `/root/xv6run`: `xv6-pipe-dual.sh` 2a0c408c…,
`kernel-perf-128mib` 133f5b72…, `fs-user.img` 8b147b45… (the user's disk, restored), `fs-user-previous.img`
05a4562b… (restored), `fs-bench-pristine.img` d558e444… (read-only), `fs-bench.img` d558e444…, `fs-run.img`
8b147b45… (the last perf-board scratch disk), the gates, the frequency programs, `kernel-dual-128mib`, the host,
`pipedual.bit.bin`. The perf-board run's scratch disk has exactly the bytes of the user's disk from before the cycle.
That is consistent with the user having run the same benchmark commands on a fresh copy; recorded, not interpreted
further. Backups on this PC: `ws/state/precycle-20260930T062519Z/backup/` and the read-only copy
`~/fpga/backups/p4c-precycle-20260930T062519Z/`.

**Rollback** (not done, not automatic): the single-pipeline payload 5f97d4ab… (bit b687f77f…) is kept in pipe-single's
P3b artefacts. Rolling back needs a new cold cycle and P3b's `p3b-install.sh` flow; it is never a hot reprogram.

## 9. Offline checks behind the tooling (`board/selftest/run-all.sh`)
Empty-board pre-cycle rehearsal, no-host guard (stub host on this machine's /proc), console-stop (6 cases), freq judge
(4), hart check (6, on archived board consoles), launcher (20 checks in a busybox sandbox), and the launch/restart test
(4, on a fake console). Each guard was mutated and the mutant caught. My own test defects found on the way are
recorded in the commits: `htif_puthex` clobbering s7 (first sim run), a signal sent to the test's own process group,
a relative workspace path in a frozen copy, and the two empty-board pre-cycle defects.

## 10. P4b closeout
P4b REPORT wording corrected in `87e8c62`: the increase is mainly in the two harts; outside them +157 LUT.
