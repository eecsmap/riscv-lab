# Production-entry acceptance; release convergence plan part C

Codex, 2026-09-21. Accept claude-xv6-production-entry-ready together with claude-xv6-convergence-package-ready for this board's exclusive serial path. This is an offline execution-package decision, not a hardware command milestone.

## Independent evidence

- Actual production-entry-selftest.sh, launched as registered job codex-production-acceptance: completed summary pass=30 fail=0. Log: .coord/jobs/logs/codex-production-acceptance-20260921-055826.log; outputs /tmp/codex-converge-production. Actual board-runner.py ran seven stages, checker accepted, effective channel/device recorded, remote completion confirmed and lock released. Both session-2 argument-plumbing mutations failed as intended; forced multiplexed mutation demonstrably reached the fake host and contaminated its input, rather than merely failing argument parsing.
- transport-selftest.py /tmp/codex-converge-transport: exit 0, 40/40. Includes traceback line595 and in-range line42 rejection, framed-response/range/error cases, and exact empty-lock cleanup success versus nonempty failure/uncertainty.
- exclusive-integration-selftest.sh /tmp/codex-converge-exclusive-live: exit 0, 21/21. Production pump bound, normal four-command completion, true ignored-interrupt uncertainty, killed transport with zero diagnostic injection, cooperating-lock exclusion and reclaim all passed. Initial detached sandbox launch produced no output; only this foreground run is counted.
- deploy-bundle manifest independently verified: 10/10. Probe identities and independent simulation acceptance remain as recorded in CODEX_SERIAL_ACCEPTANCE.md; not rerun this round.
- Source review confirms both entry points call build_transport, explicit channel/device forwarding, no channel default, device cross-check, framing gate before any post-host control command, and range-checked nonce-framed control replies. New-claim empty-directory cleanup is narrow and reports its actual result. Session-2 raw evidence/correction is retained.

Scope: live remote behavior remains to be tested. Multiplexed-board exit143 checker compatibility stays deferred; no claim of general transport completeness. The 30-test script's multiplexed section checks stages/record, not checker acceptance. No full OS simulation, RTL change, synthesis or actual board access occurred here. The production-entry test used local PTYs and its guarded fixed local lock, not the physical serial device.

## Decision and next action

Part B is complete. Claude may now execute part C of codex-xv6-converge-to-board under the existing user authorization, AFTER coordinating and verifying a physical cold start. Do not ask for new permission for the same bounded board test; do coordinate the user's power action. No more offline task expansion before this attempt.

Claim board/serial, verify cold platform/new boot, capture and pass fresh same-boot memory evidence, deploy the frozen package and pristine-derived writable disk, program the approved bitstream only from cold/quiescent state, run four M3 plus four extension startup probes and the EXACT production exclusive command in CONVERGENCE-PACKAGE.md. Correct its prose count: there are eight probe programs, not 'twelve startup gates'. Keep timeouts; stop on failure. Preserve logs, effective device/channel, hashes, real framed exit and ARM health.

No manual clearing of session-2's lock, warm/hot programming, automatic recovery loops, network/SD/DT/PS configuration changes, or new CPU/synthesis work. Cold recovery is a precondition, not something inferred from the absence of local leases. Final milestone remains shell plus echo/ls/cat/pipe and trustworthy termination/ARM health in one hardware session.
