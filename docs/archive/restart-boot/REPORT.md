# R-BOOT — the block-device stale-completion fault, fixed by a controlled program restart

**Scope held:** isolated implementation and simulation only. No synthesis, no board, no default bitstream or
PS/SD image change. `PL_RECONFIG_SAFE` stays 0. The known fault is *fixed for the restart flow below*, not
"resolved in general"; what is still open is in §6.

## 1. The fault, kept as it was

`reset-drain/rd2/rd2-d/FINDING-bdev-stale-completion.md` and its log `rd2-d/blkdev/restart-on-bdev.log`
(exit 8) are untouched. A CPU restart while a block-device read was in flight left that request's
completion queued; the restarted program consumed it as its own (tags restart at 0, so they even match)
and read a buffer its own DMA had not finished filling — a completion 41 cycles after submission where a
real one takes ~1786.

## 2. What was built (`DESIGN.md` has the full statement)

* `RD2BlockDevice.scala` — the controller wiring and the router copied from testchipip (frontend, trackers,
  arbiter reused as they are), adding a **hold** (no new submission is accepted; nothing presented is
  withdrawn — a pending allocation read keeps waiting) and a **flush** of the completion and allocation
  queues, with every dropped completion counted. The upstream file is untouched.
* The restart FSM in `RD2ZynqTopModule`: `IDLE → DRAIN → FLUSH → READY`, entered when the soft reset is
  sampled. DRAIN waits for every tracker to be idle *and* the master port to owe nothing *and* the CPU
  bridge to have drained with the reset applied; FLUSH empties the queues; READY is a level,
  `BOOT_RESTART_READY` (status bit 4), held while the reset is held. A device that does not drain within
  `rbootTimeout` (200 000 cycles) sets sticky `BOOT_RESTART_TIMEOUT` (bit 5); READY is never asserted, nothing
  is cleared, and recovery is a cold reset. `CPU_RESTART_SAFE` (bit 0) keeps its narrow meaning.
* Host order (`rd2_boot_main.cpp`, `+rboot=1`): hold → poll for bit 4 (stop on bit 5) → release → reload
  the ELF, clear `tohost`/`fromhost` → write `msip`. No timer anywhere. TSI loading while the CPU is held is
  unaffected.
* Two new programs: `boot07_blkdev_write` (a write DMA in flight at the restart; the second run reads the
  written sector back whole) and `boot08_blkdev_queued` (a completion queued and deliberately never consumed
  when the restart lands; the second run checks the queue is empty first). `boot05_blkdev` is unchanged.

## 3. The frozen gates (`build3/gates/`, `RBOOT_DONE fails=0 infra=0`)

Each run gets its own fresh copy of the generated disk image. The checker (`scripts/rboot-check.py`)
enforces, per round, the order *host assert < DRAIN_START < BDEV_DRAINED < READY < host release <
RELOADED*, requires the assert to have landed on a busy device where the scenario says so, and verifies
the **whole 512-byte buffer from the AXI write beats** against the expected disk sector — not the program's
spot checks and not a printed tag.

| gate | scenario | result |
|---|---|---|
| 1 | `g1-boot05-fixed` — same program, disk and trigger as the fault | `M3-BLKDEV-OK`, host exit 0; aimed (bdev busy at the assert); **1 stale completion discarded at the flush**; all 512 buffer bytes match sector 0 |
| 2 | `g2-read-inflight` (read DMA in flight) | as above |
| 2 | `g2-write-inflight` (write DMA in flight) | `RBOOT-WRITE-SURVIVED`; the program reads sector 2 back whole, and the **disk file** itself has all 64 doublewords of the pattern |
| 2 | `g2-queued-unconsumed` (completion queued, never taken) | `RBOOT-QUEUED-CLEAN`; the second run sees 0 queued; 1 discarded; buffer = sector 1 |
| 3 | `g3-three-rounds` — three restarts on one simulator, no cold reset | aimed on all three (`[1,1,1]`); discards 1, 2, 3 cumulative; final completion, exit 0 |
| 4 | `g4-stuck-device` — the device never answers from cycle 5000 | restart aimed at the busy device; `RBOOT TIMEOUT` after 200 001 cycles; host reports it; **no release, no reload, no READY**; run ends on the guard (exit 2, declared) |
| 4 | `g4-late-recovery` — the device answers again *after* the deadline | `TIMEOUT` first, `LATE_DRAIN` afterwards, **still no READY, no release, no reload**; exit 2 declared |
| 4 | `g4-counterexample` — READY and the release removed from the gate-1 log | rejected: `READY never happened` |
| 5 | four M3 ELFs on the same simulator (`build3/boot-gate/`) | 4/4 with the accepted `check-m3`/`check-axi` gates |
| 5 | default board RTL (`build3/default-unchanged/`) | `28ec3c91…`, byte-identical |

Regression, not a gate: the RD2 suite on the same simulator (`build2/rd2-scenarios/`) — 15 positive and 1
declared negative, `fails=0 infra=0`; checker probes 16/16, runner probes 18/18.

## 4. Two things that went wrong on the way

* The first stuck-device run never restarted at all: the host's "device busy" condition looked only at the
  master port, and a tracker waiting on a host that never answers puts nothing on the bus. The condition
  now includes "a tracker is not idle" (`bdevBusy`), which is what a stuck device looks like.
* The checker then reported "READY was asserted for a device that never drained" — it had seen the
  **power-on** round's READY at cycle 6. Restart judgements are now scoped to events after the host's first
  assert. The design had behaved correctly throughout: `TIMEOUT` at 205 973, no release.

## 4b. The timeout was not terminal (Codex's one blocker, fixed)

Reading the source and the generated RTL, Codex found that after `TIMEOUT` the FSM stayed in `DRAIN` with
the completion transition still armed, and that the host's timeout branch printed once and then let a
later READY through — so a device that recovered *after* the deadline would have produced a release and a
reload. The permanent-stall test could not see it. Both halves are fixed: the FSM has a terminal `FAILED`
state (only a cold reset leaves it; hold stays on; nothing is flushed; READY never), and the host latches
`R_FAILED` and ignores any later READY. Precedence is stated: completion at or before the deadline cycle
wins, after it failure is latched. `g4-late-recovery` (the device answers again 54 000 cycles after the
deadline) shows `TIMEOUT` first, then `LATE_DRAIN` on record, and still no READY, no release, no reload.

## 5. Reproducing

```
scripts/rd2-prog-build.sh (PROG=boot07_blkdev_write PROGDIR=experiments/teaching-cpu/restart-boot/src) <dir>
scripts/rboot-run.sh <sim> <outdir>       # gates 1-4
reset-drain/rd2/scripts/rd2-boot-gate.sh <sim> <elf dir> <outdir>   # gate 5
```
Identities: `HASHES.txt` / `HASHES-VERIFY.txt`; simulator inputs in `build2/sim/inputs.sha256`.
`build1/` (the run that exposed §4) is kept.

## 6. Residual limits

* No arbitrary-time hot reconfiguration and no global quiesce; `PL_RECONFIG_SAFE` is 0.
* The frontend's `addr/offset/len/write` registers are not cleared at the flush: the next program rewrites
  them before submitting, and the second-run checks in boot07/boot08 rely on that, not on a reset.
* The stuck-device recovery is a cold reset; nothing automatic is attempted.
* Deferred, not done (per the plan): old-D-into-new-live-transaction injection, real duplicate backend
  writes, separating the three write-reset windows, global PL quiesce.
