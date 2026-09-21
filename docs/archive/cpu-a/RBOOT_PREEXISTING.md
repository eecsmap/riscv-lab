# A pre-existing R-BOOT failure, found while re-running the gates for CPU-A

CPU-A is the first stage to re-run the accepted R-BOOT gates (`restart-boot/scripts/rboot-run.sh`) since
the CPU-SU core landed. One of the eight, **g2-write-inflight**, does not pass any more, and the cause is
not CPU-A: it is already broken with the CPU-SU-era core.

## What the gate does

`boot07_blkdev_write` submits a block-device write, the host asserts a soft reset while the device is busy
(`+rboot=1 +rd2_restart_at=9000 +rd2_restart_when=3 +rd2_restart_rounds=1`), R-BOOT drains the device, the
CPU is restarted and the program is reloaded; the program must then report `RBOOT-WRITE-SURVIVED`.

## Bisect, all with the same program, disk image and plusargs

| Simulator | CPU core | Result |
|---|---|---|
| `restart-boot/build3/sim/obj_dir/sim` (the accepted R-BOOT build) | the R-BOOT-era core | **passes**, `CYCLES total=34487 host_done_at=34481` |
| `cpu-su/soc-run2/sim/obj_dir/sim` | the CPU-SU core | fails: 300000 cycles, `host_done_at=0` |
| `cpu-sv39/soc-run2/sim/obj_dir/sim` | the CPU-SV39 core | fails the same way |
| `cpu-a/soc/sim-default/obj_dir/sim` (this stage, V1 path, `misa.A = 0`) | the current core | fails the same way |
| `cpu-a/soc/sim-atomic/obj_dir/sim` (this stage, the atomic path) | the current core | fails the same way |

The failure predates CPU-A by two stages. Both of this stage's configurations fail it identically, which is
also evidence that the atomic path is not what breaks it.

## What the failure looks like

The restart itself completes (`restarts_requested=1 restarts_completed=1`). After the reload the program
re-submits the write and then sits in `submit_wait`, polling the device's completion byte at 0x10015014
(`lbu t0, 20(s0)`, a bounded loop of 400000 iterations). The completion never arrives, so the CPU burns the
whole budget — with a 200-million-cycle probe it is still polling at 14 million cycles, still fetching and
still being granted the bus (in the last slice the CPU won 4144 transactions against 1286 for the other
masters), so it is not a bus deadlock and not starvation: the device's completion simply does not come.

Without the restart injection the program does not complete on *either* core, which is expected — the
program is written around the restart.

## Not fixed here

Diagnosing the block device's completion path after an R-BOOT restart is outside this delegation, which is
about the A extension. It is reported rather than worked around: `scripts/run-soc-a.sh` runs the R-BOOT
gates, requires the other seven to pass, and names this one as a known pre-existing failure with this file
as its evidence. If the ruling is to fix it, the bisect above says the change to look at is between the
R-BOOT-era core and the CPU-SU core.
