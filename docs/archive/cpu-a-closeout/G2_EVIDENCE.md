# g2-write-inflight: what the evidence says

**Corrected 2026-09-19 after Codex's review (`CODEX_DECISIONS.md`).** The first version of this file drew
two conclusions the evidence does not support, and they are withdrawn here:

* it read the restart as landing on a disk *write in flight*. It did not. `0x10015010` is the block
  device's **direction** register (0 = read, 1 = write). In `evidence/fail.log` the device takes
  `direction=0` at cycle 8402 and is allocated at 8429; the hold is at 9000; the **first write happens only
  at cycle 29152**, after the restart. The restart landed on the program's *initial read of sector 2*,
  before the survival pattern existed — so the program legitimately repeats its initial path and cannot
  satisfy the survival marker with a single scheduled restart.
* it offered `bdevInflight` at `DRAIN_START` as the discriminator between a passing and a failing restart.
  That does not hold: `evidence/pass-at6404.log` has `bdevInflight=0` at `DRAIN_START` and still fails.

Two further corrections of fact:

* `+rd2_restart_at` is an **earliest arm threshold**, not the cycle of the hold. The passing 9000 setting
  actually holds at cycle 12878.
* Because the targeting was wrong, **nothing here exonerates the device, the drain or any CPU**. The
  earlier claim that the failure was "neither caused by nor fixable inside CPU-A" was not established by
  these runs and is withdrawn.

What the comparison below does establish is narrower and still useful: the two cores execute the same
instructions and differ only in speed, so a *fixed-cycle* trigger selects a different program phase on a
slower core. That is why the gate needed operation-level targeting rather than a cycle adjustment.
**The corrected gate, its evidence and its result are in `../rboot-write-target/`**, where a restart is
bound to an accepted, in-flight disk write and the gate passes on both configurations.

## 1. The comparison that was asked for

Same ELF (`boot07_blkdev_write.elf`), same disk image, same plusargs
(`+rboot=1 +rd2_restart_at=9000 +rd2_restart_when=3 +rd2_restart_rounds=1`):

| | accepted `build3` simulator | `cpu-su/soc-run2` simulator |
|---|---|---|
| result | passes, `CYCLES total=34487` | fails, 300000 cycles, `host_done_at=0` |

The event streams are identical for the whole boot handshake. The first difference is the *fetch
granularity*: the newer core fetches 16-bit parcels (CPU-C), so it issues two fetches where the older core
issued one. Aligned by instruction rather than by cycle, **the two runs execute the same 297 program
instructions**, and the divergence is only that the newer core reaches instruction 297 at cycle 8945 where
the older one reaches it at 6404 — about 1.4× slower.

The restart trigger is a fixed cycle (9000). With the old core, cycle 9000 falls after that phase; with any
slower core it falls inside it.

## 2. The decisive experiment

Inject the restart into the **accepted** simulator at the cycle where the newer core is in that phase:

| accepted simulator, `+rd2_restart_at=` | result |
|---|---|
| 9000 (the gate's value) | passes, 34487 cycles |
| 6450 | fails, 300000 cycles, `host_done_at=0` |
| 6404 | fails, the same |
| 6300 | fails, the same |

The accepted core, the accepted RTL and the accepted host model fail the gate on their own, at a trigger
cycle that differs by 2.5k. Nothing about CPU-A, CPU-SV39 or CPU-SU is required to reproduce it.

## 3. What the drain reported (not a discriminator)

The R-BOOT drain prints its state when it starts:

* passing run: `DRAIN_START trackersIdle=0 bdevInflight=0 queued=0`, `HOLD_ASSERT pendingA=0 outstanding=1`
* failing run: `DRAIN_START trackersIdle=0 bdevInflight=1 queued=0`, `HOLD_ASSERT pendingA=1 outstanding=0`

**These do not separate passing from failing runs** — `pass-at6404.log` fails with `bdevInflight=0` — and
neither value says which *operation* the device was carrying. That is what the corrected gate measures
instead. Both runs then drain identically (`BDEV_DRAINED queued=1 allocs=0`, `READY discarded=1`, epoch 2) and both restart
and reload the program, which re-enters at `0x80000000` in both.

## 4. What the failing run actually does

* The data reaches the disk **twice**: comparing each run's disk image against the original, the passing run
  differs in sector 2 only; the failing run differs in sectors 2 **and** 3, and `sector3 == sector2 ==` the
  passing run's sector 2, byte for byte. So the pre-restart write landed, and the post-restart write landed
  as well, on the next sector.
* The completion is **not** lost: the program's polls of `ncomplete` (offset 0x14) return non-zero 120 times
  in the failing run (twice in the passing one).
* The program nevertheless never reaches its marker: it keeps re-submitting (device command writes to
  `0x10015000/8/c/10` continue to cycle 299142) until the budget runs out.

So this is not "the device never completes" — that guess was wrong. The device completes, the data lands,
the completion is visible; what does not happen is the *program* reaching a state it recognises as done
after a restart taken **on its initial read**, which is the phase this trigger actually selected.

## 5. What this led to

The remedy is not a cycle adjustment. The gate now binds its restart to an operation the device has
actually accepted — a disk WRITE that has not completed — and checks that binding from the host's own
assertion record. That work, its negative control (a read-targeted restart, which must *not* satisfy the
criterion) and the re-run gates are in `../rboot-write-target/`.

## 6. Reproducing

```
cd /home/engineer/fpga
cp experiments/teaching-cpu/restart-boot/prog-boot05_blkdev/disk.img /tmp/d.img
experiments/teaching-cpu/restart-boot/build3/sim/obj_dir/sim +max-cycles=300000 +blkdev=/tmp/d.img \
  +rboot=1 +rd2_restart_at=6404 +rd2_restart_when=3 +rd2_restart_rounds=1 \
  experiments/teaching-cpu/restart-boot/prog-boot07_blkdev_write/boot07_blkdev_write.elf
```
