# MC-M5 — dual-core board test (authorised by the user 2026-09-27)

Isolated workspace. Nothing here modifies the accepted IPS campaign scripts (`worktrees/ips-cache/.../board`), the
E1 library (`riscv-lab/.../lib-e1.sh`), the production transport/send-file/mem-preflight tools, or any frozen image.

| item | content |
|---|---|
| `board/lib/lib-e1.sh` | copy of the accepted E1 library; `LIB-DIFF.txt` = the only changes: `GATES` = the six M2b dual programs, `GATE_COUNT=6`, no perf probes |
| `board/lib/markers.tsv` | exact completion markers `M2B-BOOT-OK`, `M2B-CLINT-OK`, `M2B-LOCK-OK`, `M2B-PBUS-OK`, `M2B-FENCEI-OK`, `M2B-LONG-OK` (dual06_drain needs the harness injector: not a board gate) |
| `elfs-dual/` | frozen set + `elfs.sha256`: the 6 gates (M2b `build/elf.sha256` hashes), `fesvr-teaching-static` c050eab3…, `kernel-dual-128mib` 33021237…, `fs-dual-deploy.img` d8e50269… |
| `payloads/` | `dual.bit.bin` payload **43e5b414…** (bit 4ecccd05…), `cache.bit.bin` payload **79a114ae…** (bit e546c0dd…, the user's current config); `payloads.tsv` |
| `board/m5-precycle.sh dual` | local hashes -> leases -> board `timeout` probe -> pin boot id (`state/dual-pin.txt`) |
| `board/m5-record-power-cycle.sh dual` | the USER's attestation that power was physically removed |
| `board/m5-install.sh dual` | cold-cycle gates (new boot id, uptime<=600, empty /root/xv6run, no host, NO_LOCK) -> memory evidence + production `mem-preflight` -> hash-verified deploy (payload, host, 6 gates, kernel, fresh `fs-run.img`) -> `cat > /dev/xdevcfg`, PROG_RC=0, prog_done=1, payload re-hashed on the board -> 6 gates (marker AND RC=0, first failure stops) -> final state |
| `board/m5-xv6.sh <session>` | same boot: production runner (isolated M4 copy) over `/dev/ttyUSB1` exclusive, workload `m4smoke`, evidence bundle re-checked by the runner's gate; judge `m5_xv6_check.py` |
| restore | the PRODUCTION `ips-precycle.sh cache` / `ips-record-power-cycle.sh cache` / `ips-install.sh cache` (unchanged) with `IPS_OUT`/`IPS_SESSION` pointed into `state/`, `sessions/`: payload 79a114ae… + its 8 single-core gates, after a second cold cycle |

Self-tests (`/tmp/claude-1000/m5-selftest`, rerunnable from the commands in the REPORT): gate runner 6/6 positive; refuses a
missing marker, RC!=0, 5 gates, wrong count (exit 30). `m5_xv6_check.py` PASSes the accepted M4 sim smoke record and
FAILs three mutations (parent DONE removed, stop record altered, runner exit altered).

On the board the host has no per-hart counters (HARTS/HARTS_USER and RBOOT BDEV lines are printed by the simulator main):
the dual-core evidence on hardware is the six gates; the xv6 run shows the deployment kernel booting both harts and
completing the concurrent workload.

Pre-state (read-only, `state/pre-state-*.txt`): boot 56855e57…, up 2 d 9 h, PL prog_done=1, `/root/xv6run` held the IPS
cache set (cache.bit.bin 79a114ae…, 8 gates, fesvr), `kernel-4mib` 6ad5c233…, `fs-b0-pristine.img` 6bdd8148…, and the
user's RAM working disk `fs-interactive.img` 7aa27965… (lost by the power cycle; the user said the session is no longer needed).
