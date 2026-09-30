# Single-pipeline xv6 on the PYNQ-Z1 — how to use it

State at handoff (2026-09-30 ~00:10Z, boot `4d45136e…`): the board holds the **single-pipeline** bitstream (payload
`5f97d4ab…`), xv6 is **installed and ready to launch, not running**; no host process, no lock, no agent holds the
serial console. Nothing survives a power-off (the board's root filesystem is RAM).

## Connect (from this PC)
```sh
screen /dev/ttyUSB1 115200            # exit screen: Ctrl-A then k then y
# or: python3 -m serial.tools.miniterm /dev/ttyUSB1 115200     (exit: Ctrl-])
```
Press Enter; you should see the board's prompt `/root/xv6run # `.

## Start xv6
```sh
cd /root/xv6run && ./xv6-pipe.sh                                   # your disk: fs-user.img
cd /root/xv6run && ./xv6-pipe.sh /root/xv6run/fs-user-previous.img  # the disk you had on the dual-core system
./xv6-pipe.sh --check                                              # check only, starts nothing
```
Boot takes about 7 s to the `$ ` prompt. The launcher refuses to start if a host is already running or the lock is
held.

## Try it (at the xv6 `$ ` prompt)
| command | what it does | single pipeline (measured) | single multicycle (measured) |
|---|---|---|---|
| `mtimetest` | mtime clock and syscall cost | read cost ~125 mtime units | ~190 |
| `perfcompute` | 4 children, 8,000,000 iterations in total | **15.8 s** | 26.6 s |
| `perfarray` | 4 children, 8,388,608 array updates | **12.7 s** | 40.5 s |
| `b0compute`, `m3par2`, `m3fs` | the smoke programs | each finishes in ~2–4 s | |

Also the usual `ls`, `cat`, `echo`, `grep`, `wc`, `usertests` (slow: it runs many tests). The times above are the
median of three runs each, measured by the kernel's `mtime()` (the core clock was checked at 40.00 MHz against the
ARM's clock).

## Stop and restart
* Stop: wait for the xv6 `$ ` prompt (nothing running), then press **Ctrl-C once**. The launcher prints
  `xv6 host exited …; lock released` and you are back at `/root/xv6run # `.
* Restart: run `./xv6-pipe.sh` again. `fs-user.img` keeps your files between restarts (until power-off).
* If a command hangs, Ctrl-C still stops the host; xv6's file system log makes the disk consistent on the next boot.

## Files on the board (`/root/xv6run`)
| file | sha256 | |
|---|---|---|
| `xv6-pipe.sh` | `983c67ff…` | the launcher |
| `kernel-perf-128mib` | `133f5b72…` | the measurement kernel (has the `mtime()` syscall) |
| `fs-user.img` | `d558e444…` at handoff | your disk (fresh copy of the benchmark image; agent runs never write it) |
| `fs-user-previous.img` | `05a4562b…` | your disk from the dual-core session (backed up over the console before the power cycle; also on this PC at `experiments/pipeline/p3/board/state/backup/fs-run.img`) |
| `pipe.bit.bin` | `5f97d4ab…` | the programmed payload (not re-programmed by the launcher) |
| `fs-run.img` | | the benchmark runs' scratch disk (overwritten by each agent run) |

Agents will not start anything on the board while xv6 is running (they check for the host and the lock), and they
do not touch the serial console until you hand it back.
