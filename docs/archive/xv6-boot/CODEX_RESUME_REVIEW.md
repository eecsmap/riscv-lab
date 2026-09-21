# FENCE.I resume review — 2026-09-19

Partial recognition, not shell acceptance. Independently replayed r02.elf on regress-cpu-a/sim/t0/tcpu_tb: exit 0, 276 cycles, 21 retired, zero traps (previous implementation exited 2). Active decoder recognizes FENCE.I separately and suppresses rd write. Full regressions and monitored SMC results remain delivered evidence, not independently rerun this turn.

Hash verification: 415/416 match; evidence/fs-boot3.img mismatches. Preserve it and explain run-finalization/manifest timing; do not merely replace the digest without provenance.

The reported second blocker is not established by the current run-dev2/run.log. It contains later successful writes at cycles 534679550–544752964 (sectors 4,68,94,66,4), then a third U ecall at cycle 547303400, epc=0x392. Its tail also contains `init: starting ` (not a full shell marker). This contradicts the claim that mknod never returns and no device operation follows it. Distinguish an early snapshot from the final run. A quiet scheduler sample or a stable retire rate cannot prove deadlock or exonerate the CPU/device.

Additional finite test correction: r03_fencei_matrix.S executes M-only mstatus/mepc/mret operations from s_mode. Its handler advances past unexpected traps and returns in M mode, while the final success path accepts cause 8 OR 9. The reported U-mode FENCE.I coverage is therefore not robust. Use an explicit S ecall transition to an M handler, set MPP=U there, and require cause=8 at completion; reject every unexpected trap. Do not reopen the functional implementation on this test defect alone.

Next task codex-xv6-progress-diagnosis: finalize evidence and continue bounded boot observation. Read-only SoC memory inspection is authorized if still needed, with a consistent snapshot and exact ELF symbol/layout identity. No software lock/log patch or hardware fix is justified yet. Shell and user commands remain unverified; no new board work.
