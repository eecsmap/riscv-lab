# R-BOOT: aiming the write-restart gate at an actual disk WRITE

Claude, 2026-09-19. Delegation `codex-rboot-write-target-fix` (acked), from
`cpu-a-closeout/CODEX_DECISIONS.md`. Codex's finding was correct and my earlier reading was wrong:
`0x10015010` is the block device's **direction** register, and the gate's fixed-cycle trigger was catching
the program's *initial read of sector 2*, before the survival pattern existed. `cpu-a-closeout/G2_EVIDENCE.md`
has been corrected accordingly (the `bdevInflight` discriminator and the device/CPU-exoneration claims are
withdrawn, and arm threshold is now distinguished from hold time). The old logs are untouched; everything
new is here.

## 1. Targeting by operation, not by "busy"

A read and a write both make the device busy, so a busy flag cannot say which operation a restart lands on.
The device now reports what it is actually carrying:

* `RD2BlockDevice.scala` — per tracker, a flag set at the request handshake with that request's own
  direction and sector, cleared when the tracker reports completion. Exposed as `opAccepted` / `opWrite` /
  `opSector` / `opLen` (a pulse per accepted operation) and `writeInflight` / `readInflight` /
  `writeSector` (the standing state).
* `RD2Soc.scala` — carries them into the harness status and prints one line per accepted operation:
  `RBOOT <cycle> BDEV_OP dir=<0|1> sector=<n> len=<n>`.
* `rd2_boot_main.cpp` — two new restart conditions: **5 = a disk WRITE has been accepted and has not
  completed**, 6 = the same for a READ (used by the negative). The assertion line now records what the hold
  actually caught: `RESET_ASSERT round=1 bdev_busy=1 write_inflight=1 read_inflight=0 write_sector=2
  arm_at=1`. `restart_at` remains only the earliest cycle the arm may fire.
* `rboot-check.py` — `--write-target=<sector>` accepts the claim "this restart landed on a write" **only**
  from that assertion record, and `--read-target` states the negative. The pre-existing `--aimed` check now
  reads the new fields (old logs with `bdev_inflight` still parse).

## 2. What the corrected gate does

`rboot-run.sh`, g2-write-inflight: `+rd2_restart_at=1 +rd2_restart_when=5 +rd2_restart_rounds=1`, checked
with `--rounds=1 --aimed --marker=RBOOT-WRITE-SURVIVED --host-exit=0 --write-target=2`. In the run the
device accepts a read of sector 2 at cycle 8538 (`BDEV_OP dir=0 sector=2`), then the sector-2 **write** at
18951 (`dir=1`), and the hold asserts at 18952 with `write_inflight=1 write_sector=2` — the write is
provably still in flight. The original oracle is unchanged and still passes: the marker appears, the host
exits 0, only sector 2 differs from the original disk, and it holds all 64 doublewords of the pattern.

A new declared negative, **g2-read-target-neg**, aims at the initial read (`restart_when=6`) and must fail:
under `--write-target=2` it is refused by name — *"the restart at cycle 8539 did not catch a write in
flight (write_inflight=0, read_inflight=1)"* — and it never reaches the survival marker. That is the case
the old fixed-cycle trigger was silently hitting.

## 3. Results

| Run | Result |
|---|---|
| the eight R-BOOT gates, **default (V1) configuration** | `RBOOT_DONE fails=0 infra=0` (`gates-default/`) |
| the eight R-BOOT gates, **A-enabled configuration** | `RBOOT_DONE fails=0 infra=0` (`gates-atomic/`) |
| the full SoC suite, both configurations, no exemption | `SOC_A_DONE infra=0 fails=0` (`soc-run/`) — the four M3 programs, boot09/boot10 misa copies, the original hello, su01/su05/su06, boot11, boot12_amo, both `misa` probes, the R-BOOT gates, and the four atomic-in-flight drain restarts |

So the gate passes on both configurations once the restart is aimed at an operation rather than at a cycle.
No device or CPU defect appeared after correct targeting, and nothing in the CPU, the bridge or the backend
was changed for this.

`identity.sha256` records the exact sources, generated RTL, simulator binaries, program and disk image these
results came from, and the accepted `build3` simulator used for the comparison.

## 4. Commands

```
# the gates, per configuration
MAXCYC=300000 WALL=900 bash experiments/teaching-cpu/restart-boot/scripts/rboot-run.sh \
  experiments/teaching-cpu/rboot-write-target/sim-<default|atomic>/obj_dir/sim \
  experiments/teaching-cpu/rboot-write-target/gates-<default|atomic>

# the whole SoC suite (uses the same two simulators)
bash experiments/teaching-cpu/cpu-a/scripts/run-soc-a.sh experiments/teaching-cpu/rboot-write-target/soc-run
```

## 5. Not claimed

No synthesis, no board; the default Rocket, PS, SD and xv6 software are untouched; the A implementation is
unchanged. This was a test-targeting correction, not a reset study: no phase matrix was explored beyond the
operation-level binding the gate now uses.
