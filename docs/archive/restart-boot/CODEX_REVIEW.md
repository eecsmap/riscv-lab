# R-BOOT bounded review — Codex, 2026-09-17

## Decision

The normal controlled-restart repair is independently reproduced and accepted for the frozen cases.
**One narrow blocker remains: timeout is not an irreversible fail-stop state as documented.** This is
within frozen gate4, not a return to the deferred generic fault matrix. No Vivado/hardware work was done.

## Independent evidence

Registered `codex-rboot-review`; delivered build2 simulator, no fresh SoC compilation. All284 manifest
entries match. `codex-review/gates/` contains new runs on freshly copied simulation disks:

- Original boot05 failure case now marker/host exit0, full512-byte buffer matches sector0, one stale
  completion discarded. Original pre-fix exit8 evidence remains in the old RD2 directory.
- Read-DMA in flight, write-DMA in flight and queued/unconsumed completion cases all pass. Written disk
  sector2 independently checked by the gate: all64 doublewords equal the expected pattern.
- Same-process three restarts pass, discarded count1/2/3; final host exit0 at37943. Restart assert/release/
  reload times: 5971/7743/7819,13923/15738/15773,21940/23731/23790. This is three interruptions with one final
  completion, not three process exits.
- Permanently stalled device reaches design timeout, never releases/reloads in that run, simulator exits2
  at the declared guard. Review uses MAXCYC300000 (above the200000-cycle design timeout), not6million.
- Removing READY/release evidence is correctly rejected. RBOOT_DONE fails0 infra0.

Gate5 M3 regression is also run using the same delivered simulator, with outputs in codex-review/boot;
completion recorded in the coord job log. Existing default RTL identity is checked through the manifest;
not independently regenerated. The postponed fix13 narrow audit is not silently marked complete here.

## Timeout blocker — source/generated-RTL finding

In RD2Soc.scala rbDrain, `when(bdevIdle && cpuDone)` advances to rbFlush without checking rbTimeout.
The else branch only sets rbTimeout; that sticky flag neither makes the state absorbing nor suppresses
bootRestartReady. Generated RTL has the same `bdevIdle & cpuDone` condition and READY state decode.
Consequently, if the device returns **after** timeout, hardware can flush and assert READY with TIMEOUT1.

The host loop has a matching omission: it checks timeout only while `!rboot_timeout_seen`, prints once and
sets that boolean. The following READY-release branch does not check the sticky seen flag or timeout bit.
A late READY can therefore release CPU reset and schedule an ELF reload despite the earlier timeout.

This is a code-confirmed reachable transition, **not claimed as a dynamically reproduced late-recovery
SoC run in this review**. The submitted permanent-stall test never allows recovery, so cannot exercise it.
It contradicts DESIGN.md's "READY never asserted", stop-on-bit5 and cold-reset-only recovery, and the
frozen gate's timeout-not-release requirement. Fix both hardware and host, then add one late-recovery
test. No new universal checker or reset-state research is needed.

## Narrow completion criteria

After timeout latches: READY remains0, no flush used to hide outstanding work, host reset remains asserted
and host refuses reload even if completion/READY later appears. Allow protocol work to drain if useful,
but remain in terminal error until the documented recovery. Test a late device recovery plus the existing
permanent-stall case; preserve normal-path results/regressions. State simultaneous completion/deadline
priority explicitly. Cold-reset recovery must not be described as permission to reload PL while PS has
outstanding traffic; use a safe platform reset/power-cycle procedure instead.

Normal-path bdev fix should not be redone. M/C and xv6 remain next functional milestones once this small
fail-stop correction is checked. Global PL_RECONFIG_SAFE remains0 and all deferred matrix rows stay deferred.
