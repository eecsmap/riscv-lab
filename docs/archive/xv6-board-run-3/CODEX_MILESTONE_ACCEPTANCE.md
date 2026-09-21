# Accepted: teaching CPU runs xv6 on PYNQ-Z1

Codex, 2026-09-21. Decision on claude-xv6-board-milestone-ready: the fixed convergence milestone is complete for this recorded hardware session.

Independent review (read-only, no second hardware run):

- Re-ran check-xv6.py run-1 --require-commands: exit 0, segments=5 prompts=5 stages=7 console_bytes=3387 fails=0. Read console.txt and stages.txt: shell, echo, directory listing, README and pipe result `1 1 4` all present in order, each command successful.
- Re-ran memory preflight on evidence-1 with boot ebeab8a6-0ac9-474a-84c3-bd6e0b357d3b: exit 0, refusals=0. Captured memory map places Linux below the target DDR window.
- Reviewed deployment hash record, four M3 and four extension probe logs: all eight expected markers and RC=0. These are smoke-test results, not full ISA compliance.
- Run records effective exclusive channel, ttyUSB1, approved artifact identities, host exit 0, deliberate stop after commands and confirmed remote exit. Interpreted with the previously independently accepted production framed-control path; not an independent live reread of the remote exit file.
- Post-health record has the same boot id, LOCK_RELEASED, FESVR=0, KERNEL_ERRORS=0 and readable meminfo. Status 0x00050900 does not establish target quiescence or PL reload safety; PL_RECONFIG_SAFE remains 0. No assertion that stopping the ARM host resets the teaching CPU.

The agreed result is achieved: one cold-board session booting xv6 and executing echo/ls/cat/pipe, with accepted termination evidence and ARM health checks. Shell at 86.2s; final command complete at 277.9s. These timings describe this session, not a performance benchmark.

Not claimed: full usertests, long-run reliability, performance qualification, general transport completeness, complete ISA compliance, or absence of remaining CPU defects. Existing cold-only/no-hot-reload operating restrictions remain. Future work requires a new scoped task; do not extend this milestone's acceptance requirements retroactively.
