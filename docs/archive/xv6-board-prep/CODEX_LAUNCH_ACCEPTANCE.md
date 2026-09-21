# Offline launch preparation accepted

Codex, 2026-09-20. Decision on `claude-xv6-board-two-gaps-ready`: accepted within the offline execution-preparation scope. This is neither board acceptance nor permission to program hardware.

## Independent checks this round

- `board-safety-selftest.sh /tmp/codex-two-gaps-review`: exit 0, 59 passed, 0 failed. Includes argument-joining remote-shell fake, exact file-role checks, uncertain remote exit, token-checked cleanup, conflicting expectation rejection with zero remote calls, and rejection of all three removed production test options with zero remote calls.
- `transport-selftest.py /tmp/codex-two-gaps-transport`: exit 0, 18 passed, 0 failed.
- `sha256sum -c MANIFEST.sha256` in deploy-bundle: exit 0, 10/10 matched.
- Source review: parse_expect rejects contradictory duplicates before assignment/construction; identical repeats are allowed. Production board-runner constructs the fixed-lock/fixed-boot-id transport and invokes shared board_run.run; test overrides are confined to the separate test entry point. The launch example's missing continuation is corrected; its angle-bracket placeholders still require substitution before execution.

Earlier accepted simulation and 40 MHz bitstream results remain unchanged. No ARM executable, board, network deployment, serial, JTAG or programming was exercised in this review. No new full OS simulation was run. Other regression results in Claude's report are not represented as independent reruns here.

## Next phase: bounded live-board authorization, pending user decision

Do not open another offline architectural task. After explicit user authorization, the board operator must claim board (and serial if used), identify the board and current owners, and perform the following bounded sequence:

1. Arrange a cold, quiescent platform. After the FINAL cold boot, capture the actual ARM boot-id, device-tree memory/reservations, iomem and meminfo and pass the memory preflight. Any subsequent reboot invalidates that capture and requires repetition BEFORE target load/DMA. Do not reuse the older procedure's check-then-power-cycle ordering.
2. Stop if memory ownership is unsafe, access is unavailable, or an unexpected host/lock is present. No SD, device-tree or PS boot-configuration repair is included in the proposed authorization.
3. Verify the approved deployment identities, preserve the source disk and use a per-run writable copy. Program only the accepted bitstream from the cold/quiescent state, after required build attestations/preflight are satisfied. Use only the production runner, never the test entry point.
4. Verify ARM no-I/O self-test and the established host/reset handshake, execute the staged board probes in the reviewed procedure, then attempt xv6 shell and echo/ls/cat/pipe. Record exact artifacts, console, stage results and ARM post-run health. Stop on a failed stage rather than skip it.
5. No live PL reload, no automatic recovery/reset loop, no full usertests or performance campaign in this phase. An uncertain host/target state requires cold recovery and a fresh evidence capture; stopping the host alone does not assert reset.

BOARD-PROCEDURE.md is an older preparation document: its 'transport not implemented' statement is superseded by the accepted production/shared runner, and its cold-start sequence is superseded by the same-boot capture rule above. These corrections do not claim live behavior has been verified.

ARM runtime compatibility, real SSH/board behavior, actual DDR ownership, and xv6 hardware success remain unverified until the authorized live phase. Timing margins remain +0.779 ns setup and +0.024 ns hold; PL_RECONFIG_SAFE remains 0.
