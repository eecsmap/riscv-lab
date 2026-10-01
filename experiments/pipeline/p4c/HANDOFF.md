# Dual-pipeline xv6 on the PYNQ-Z1 — how to use it

State at handoff (2026-10-01 ~01:20Z, boot `1e44b36c…`): the board holds the **dual-pipeline** bitstream (two
pipelined harts, payload `f330769d…`). xv6 is **installed and ready to launch, not running**: no host process, no
lock, and no agent holds the serial console. Nothing survives a power-off (the board's root filesystem is RAM; your
disks are also backed up on this PC, see below).

## Connect (from this PC)
```sh
screen /dev/ttyUSB1 115200            # exit screen: Ctrl-A then k then y
# or: python3 -m serial.tools.miniterm /dev/ttyUSB1 115200     (exit: Ctrl-])
```
Press Enter; you should see the board's prompt.

## Start xv6
```sh
cd /root/xv6run && ./xv6-pipe-dual.sh                                   # your disk: fs-user.img
cd /root/xv6run && ./xv6-pipe-dual.sh /root/xv6run/fs-user-previous.img  # your older disk (dual multicycle era)
cd /root/xv6run && ./xv6-pipe-dual.sh --bench                           # a FRESH benchmark disk, re-made every time
./xv6-pipe-dual.sh --check                                              # check only, starts nothing
```
You should see `hart 1 starting` during boot (both harts are up), then the `$ ` prompt after a few seconds. The
launcher refuses to start if a host is already running or the lock is held.

## Try it (at the xv6 `$ ` prompt), with measured reference times
Fixed work, median of three board runs each, all at 40 MHz:

| command | work | **dual pipeline** (this board, measured now) | single pipeline | dual multicycle | single multicycle |
|---|---|---|---|---|---|
| `perfcompute` | 4 children, 8,000,000 iterations | **7.95 s** | 15.83 s | 13.06 s | 26.59 s |
| `perfarray` | 4 children, 8,388,608 updates | **8.29 s** | 12.70 s | 20.53 s | 40.55 s |
| `mtimetest` | the clock and the cost of reading it | read ~188 mtime units | ~125 | | |
| `b0compute`, `m3par2`, `m3fs` | smoke programs | a few seconds each | | | |

The other three columns are archived board measurements (not re-measured today). Run the benchmarks on `--bench`
for numbers comparable to the table; they also work on your own disk. Times are printed by the programs from the
kernel's `mtime()` (core clock / 100; the clock was checked at 40.00 MHz against the ARM's clock).

## Stop and restart
* Stop: wait for the xv6 `$ ` prompt (nothing running), then press **Ctrl-C once**. The launcher prints
  `xv6 host exited …; lock released` and you are back at the board prompt.
* Restart: run `./xv6-pipe-dual.sh` again. `fs-user.img` keeps your files between restarts (until power-off).
* If a command hangs, Ctrl-C still stops the host; xv6's file system log makes the disk consistent on the next boot.

## Files on the board (`/root/xv6run`)
| file | sha256 | |
|---|---|---|
| `xv6-pipe-dual.sh` | `2a0c408c…` | the launcher |
| `kernel-perf-128mib` | `133f5b72…` | the measurement kernel (has `mtime()`; boots both harts) |
| `fs-user.img` | `8b147b45…` at handoff | **your disk**, restored from the backup taken before the power cycle |
| `fs-user-previous.img` | `05a4562b…` | your disk from the dual multicycle session |
| `fs-bench-pristine.img` | `d558e444…` | read-only pristine benchmark image (`--bench` copies it) |
| `fs-bench.img` | `d558e444…` at handoff | the benchmark disk (`--bench` re-makes it) |
| `fs-run.img` | | the agents' scratch disk (overwritten by agent runs) |
| `pipedual.bit.bin` | `f330769d…` | the programmed payload (the launcher never re-programs) |

## Backups on this PC
`experiments/pipeline/p4c/ws/state/precycle-20260930T062519Z/backup/` and a read-only copy in
`~/fpga/backups/p4c-precycle-20260930T062519Z/`: `fs-user.img` 8b147b45…, `fs-user-previous.img` 05a4562b…,
`fs-run.img` 8b147b45…, with `backup.sha256`.

## Going back to the single pipeline
Not automatic. It needs another power cycle and the P3b install flow. Ask for it; the single-pipeline payload
`5f97d4ab…` is kept on this PC.

Agents will not start anything on the board while xv6 is running (they check the lock and the host), and they
do not touch the serial console until you hand it back.
