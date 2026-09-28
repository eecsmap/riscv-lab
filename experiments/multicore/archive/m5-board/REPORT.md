# MC-M5 — dual-core board test: REPORT (complete; board restored to the user's cache configuration)

Authorisation: the user, 2026-09-27 ("1. 我不需要使用了，你可以接管… 2. 授权 3. 同意"): board and serial handed over, cold-start
dual test authorised, restore to the user's current cache configuration (payload 79a114ae…) agreed. Codex M4 verdict
conditions honoured: no board access before that message; recovery image named by hash (79a114ae…, not the 20fae71e reference).

## 1. What ran, in order (all as coord jobs; every step in `sessions/session-dual-20260927T191016Z/session.log`)
| step | result |
|---|---|
| pre-state (read-only) | `state/pre-state-20260927T185446Z.txt`: boot 56855e57…, PL prog_done=1, cache set + user's `fs-interactive.img` in /root/xv6run, no host, NO_LOCK |
| `m5-precycle.sh dual` | 9 frozen artefacts ok, payload 43e5b414… ok, board has `timeout`, pinned boot 56855e57… |
| user power cycle | attested 2026-09-27T19:09:52Z (`state/dual-power.txt`) |
| `m5-install.sh dual` (job `mc-m5-install`, 19:10:16Z) | cold cycle verified: new boot **a534c757…**, uptime 25 s, /root/xv6run empty, no host, NO_LOCK; memory evidence captured for that boot, production `mem-preflight` verdict OK (`mem-preflight.json`); 10 artefacts deployed and sha-verified on the board (`deploy.log`); `cat dual.bit.bin > /dev/xdevcfg` rc=0, prog_done=1, payload re-hashed on the board = 43e5b414…; **STARTUP GATES 6/6** |
| dual xv6, attempt 1 (`xv6-m4smoke`) | runner refused BEFORE launching a host: the cold initramfs has no `/var/lock` (same one-time `mkdir` the accepted xv6-board-run made); PL untouched |
| dual xv6, attempt 2 (`xv6-m4smoke-20260927T192841Z`) | kernel booted, both harts up, b0compute ok, m3par2 output exactly right; runner marked m3par2 unsatisfied because the real console ends lines CRLF and the isolated `m4smoke` pattern had a bare `\n` (the simulator console was LF). Host stopped cleanly (exit 0, confirmed on the board). Fix in the ISOLATED runner copy only (`\r?\n`), proven on the recorded segment, ok=0 mutation still rejected |
| dual xv6, attempt 3 (`sessions/session-dual-20260927T191016Z/xv6-m4smoke-20260927T192956Z`) | fresh disk copy redeployed (attempt 2 had written it); **PASS**: 6/6 stages, deliberate stop, host exit 0, remote exit confirmed, `check-xv6 --require-commands` fails=0, `m5_xv6_check.py` PASS |
| `ips-precycle.sh cache` (PRODUCTION script, IPS_OUT redirected) | 13 artefacts ok, payload 79a114ae… ok, pinned boot a534c757… |
| user power cycle #2 | attested 2026-09-27T19:40:52Z (`state/cache-power.txt`) |
| `ips-install.sh cache` (PRODUCTION script, `IPS_OUT`/`IPS_SESSION` redirected; job `mc-m5-restore-cache`, 19:41:08Z) | cold cycle verified: new boot **4e3f038a…**, uptime 18 s, /root/xv6run empty, no host, NO_LOCK; evidence + `mem-preflight` OK; 13 artefacts deployed and verified; `cat cache.bit.bin > /dev/xdevcfg` rc=0, prog_done=1, payload re-hashed on the board = **79a114ae…**; **STARTUP GATES 8/8** (incl. ext03_a); perf02/03/04/06 **3/3 usable each**; final state PD=1 FESVR=0 NO_LOCK (`sessions/session-restore-cache-20260927T194108Z`) |

## 2. The six dual-hart gates on hardware (`sessions/session-dual-20260927T191016Z/gates/*.out`, all RC=0)
| gate | marker line |
|---|---|
| dual01_boot | `M2B-BOOT-OK sp1=0x80003000` (hart 1 woke via the ROM IPI and reached its own stack) |
| dual02_clint | `M2B-CLINT-OK mtip0=0x5 0x5 0x807` (per-hart mtimecmp/mtip and msip) |
| dual03_lock | `M2B-LOCK-OK lock=0x4e20 lrsc=0x4e20 amo=0x4e20 scf_shared=0x111f 0x1387` (20 000 increments each way, both harts, SC failures observed on both: real contention) |
| dual04_pbus | `M2B-PBUS-OK senable_rb=0x2 0x0 sprio_rb=0x0 0x0` |
| dual05_fencei | `M2B-FENCEI-OK nofence=0x1 fence=0x2` (cross-hart code patch visible after fence.i) |
| dual07_long | `M2B-LONG-OK iter=0x186a0 0x186a0 sum=0xdaf8a24a417f9318 0xdaf8a24a417f9318` (100 000 iterations per hart, equal sums) |

## 3. Dual xv6 on hardware (attempt 3 console, verbatim)
```
teaching: ready after 50 ms; status=0x00010711 cpu_restart_safe=1 pl_reconfig_safe=0 draining=0 drain_timeout=0 boot_ready=1 boot_timeout=0 epoch=7 ndrained=1

xv6 kernel is booting

blkdev: 4000 sectors (1 MB), max request 16 sectors
hart 1 starting
init: starting sh
$ b0compute
B0-COMPUTE-CHECKSUM=5ADF55920BF7696
B0-COMPUTE-DONE
$ m3par2
M4-PAR-CHILD0 checksum=f6d983767e3c5638 harts=0x0
M4-PAR-CHILD1 checksum=01d86a21f972f3fa harts=0x0
M4-PAR-DONE children=2 ok=1
$ m3fs
M3-FS-CHILD0 ok=1
M3-FS-CHILD1 ok=1
M3-FS-DONE ok=1
$ 
```
Stages: banner 5.4 s, first prompt 11.7 s, b0compute 13.9 s, m3par2 15.9 s, m3fs 22.1 s (`stages.txt`, with the bitstream/host/kernel/disk
sha, evidence session a534c757… and its digest, host exit 0). The same `m4smoke` workload took 2175 s of host wall in the M4
simulation. `harts=0x0` in m3par2 is by design: the deployment kernel has no `getcpu`; on the board there are no per-hart
retire counters (HARTS/HARTS_USER/RBOOT lines are simulator-main output), so the hardware evidence for "two harts" is the six
gates above plus the kernel's `hart 1 starting` and the two concurrent workloads completing.

## 4. Honest notes
- Two xv6 attempts before the pass; both failures were host-side (missing `/var/lock` on the cold initramfs; CRLF vs the
  isolated pattern). Neither touched the PL or left a host/lock behind (post-state PD=1 FESVR=0 NO_LOCK each time). All attempts kept.
- Nothing in `worktrees/ips-cache`, `riscv-lab` or the frozen images was modified: the M5 library is a copy (`board/LIB-DIFF.txt`),
  the runner is the M4 isolated copy (pattern change above), the restore uses the production scripts with `IPS_OUT`/`IPS_SESSION`
  pointed here. `git status` in `ips-cache` shows `board-metrics.json` modified since 2026-09-25 22:58Z, before this session.
- One lease refusal (exit 60) when I pre-claimed `board`/`serial` by hand before the precycle; released and re-run. Logged.
- The user's RAM working disk `fs-interactive.img` (7aa27965…) was lost by the power cycle as expected; its hash is in the pre-state record.
- No performance measurement was taken (not authorised/asked); the fixed-workload dual-vs-single comparison remains a future stage.

## 5. Final board state
The PL holds the user's cache configuration again (payload 79a114ae…, the same artefact `ips-install.sh cache` installed on
2026-09-25), re-verified by its own 8 gates and 12 perf samples, on a cold boot (4e3f038a…). No host running, no lock, leases
released. `/root/xv6run` holds the cache campaign set (RAM; gone at the next power cycle). The dual bitstream is NOT in the PL.

## 6. Re-run entry points
```bash
M5=/home/engineer/fpga/experiments/multicore/m5-board
$M5/board/m5-precycle.sh dual              # user cycles power -> $M5/board/m5-record-power-cycle.sh dual
$M5/board/m5-install.sh dual               # -> $M5/board/m5-xv6.sh <session dir>
IPS_OUT=$M5/state ./ips-precycle.sh cache  # (in worktrees/ips-cache/.../board) user cycles power -> ips-record-power-cycle.sh cache
IPS_OUT=$M5/state IPS_SESSION=$M5/sessions/session-restore-cache-<ts> ./ips-install.sh cache
python3 $M5/board/m5_xv6_check.py <xv6 attempt dir>
```
Self-tests: gate runner mutations (`/tmp/claude-1000/m5-selftest`, rerun with the fake console in the README) and the judge's three
mutations against `m4/runs/smoke-deploy` and the CRLF pattern check against attempt 2's console (see coord log).
