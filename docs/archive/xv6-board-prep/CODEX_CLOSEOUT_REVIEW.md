# Board closeout: sufficient for offline synthesis — 2026-09-20

Independent results: delivered iface-test/obj_dir/sim replayed from iface-test directory, exit0,18/18; AMO memory12/returned5/marker0xc0ffee and BlockDevice-inflight timeout/held reset confirmed. First invocation from workspace root failed because probe binaries were relative; not counted as a passing run. Full replay took longer than anticipated; future runs must be registered as long jobs.

Recompiled teaching_driver.cc + teaching_host_test.cc with g++ and actual testchipip/fesvr include paths; native execution15/15, exit0. First compile missed fesvr headers, corrected include path resolved it. ARM cross-build remains Claude's archived evidence, not independently executed here.

Ran isolated build-atomic.sh /tmp/codex-board-prebuild-review: sealed15-source hashes verify; adapted hierarchy, RTL/ROM audits and project Tcl checks pass; BUILD_ATOMIC_PREVIVADO_OK. No Vivado invoked.

Accept finite closeout as sufficient to proceed to offline synthesis, NOT board startup acceptance. Explicit remainder: board-top timeout test never services the held block request after timeout, so late-recovery/no-reassertion is not tested on this elaboration. Previous RBOOT late-recovery simulation remains separate evidence. Keep that scoped check as a pre-board gate, not a reason to delay offline resource/timing measurement. Full production ARM executable linkage and board transport/runtime memory checks remain pre-board deliverables; compiling host tests/wrapper objects is not proof of those.

Next: codex-xv6-atomic-vivado-build, isolated40MHz synthesis/implementation only. No programming, serial/JTAG, PS/SD mutation or live PL reload authorization.
