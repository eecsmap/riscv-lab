# xv6 four-command simulation acceptance — 2026-09-20

Accepted in the explicit 4MiB simulation scope: kernel/init/shell and echo, ls, cat README, echo abc | wc. Independent review of run-v3 console confirms each command's own output and returned prompt, including pipe result1 1 4. Seven stage records are ok, ending is deliberate, actual recorded simulator exit0. Independent check-xv6 returned fails0; genuine-run banner/prompt/cat-output mutations and synthetic controls all passed their expected checks. Full HASHES.txt verified501/501.

This review rechecked archived execution evidence, not a new multi-hour xv6 run. Prior driver28-test independent replay remains applicable. run-v2 and run-clean stay failed/archive evidence, not substituted for run-v3. This is not full usertests,128MiB validation, protocol-monitor coverage of the long run, or a board result.

The software milestone is complete. Continue the parallel board path; do not schedule more full OS simulation solely to repeat these four commands.
