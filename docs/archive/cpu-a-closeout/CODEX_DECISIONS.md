# CPU-A closeout review — 2026-09-19

## Verdict

Items 2/3 receive finite acceptance. CPU-A functional acceptance from the preceding review stands. Item 1 (g2-write-inflight) is not passed: the evidence identifies a wrongly targeted restart, not an established CPU or device completion defect. Execute `codex-rboot-write-target-fix` next, then return to xv6 integration.

## Independently checked this review

- HASHES.txt: 999/999 pass.
- Archived core-run3 a01-t0 checked independently: 138 cases, 72 combinations, fails=0 with rc=0 and the real log. The same data with rc=3 fails; with an empty completion log fails. Runner source also propagates nonzero positive exits.
- Inspected the A-enabled Sv39 build command (`-GMISA_A=1`), regression records and completed SoC list. Those full suites were archive-reviewed, not independently rebuilt or rerun this turn.
- soc-run6 correctly reports g2 failure without exemption; it is not an all-green result.

## g2 evidence and interpretation

`restart-boot/src/boot07_blkdev_write.S` first READS sector 2. Only if its first word already equals PATBASE does it take the restart-survival path. Otherwise it builds and writes the pattern, then loops writing sector 3. Restarting before that first write legitimately repeats the initial path; it cannot satisfy the survival marker with only one scheduled restart.

BlockDevice address 0x10015010 is the direction register (0=read, 1=write); reading 0x10015011 allocates the request. In closeout/evidence:

- fail.log: direction=0 at cycle 8402, allocation 8429, HOLD_ASSERT 9000, epoch 1. First direction=1 occurs only at cycle 29152, epoch 2. Thus the supposed write-inflight restart precedes the first disk write.
- pass.log: sector-2 direction=1 at 12855, allocation 12874, HOLD_ASSERT 12878. This targets a different operation from the failing run.
- pass-at6404.log: direction=0 at 5930, allocation 5949, HOLD_ASSERT 6404; first write is again after restart. DRAIN_START at 6405 has bdevInflight=0, so that Boolean does not distinguish all failures from success.

The configured restart cycle is an earliest arm threshold, not necessarily the actual hold cycle: the successful 9000 setting holds at 12878. Generic busy selection plus an arm threshold is phase-sensitive and does not prove a WRITE was targeted. Later disk contents/completions do not establish that the required write happened before hold. This explains the observed marker timeout; it does not independently prove every device/reset behavior correct.

## Authorized next action

Narrowly repair and prove write-specific targeting in the isolated R-BOOT test/harness/runner; preserve old evidence and strict data/completion checks. No default Rocket/PS/SD changes, synthesis or board access. Correct G2_EVIDENCE conclusions to match the operation-level evidence. No need to request permission again merely because a scoped test file was previously accepted.
