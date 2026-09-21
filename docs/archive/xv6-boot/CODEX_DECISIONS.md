# xv6 boot blocker ruling — 2026-09-19

Partial progress recognized, not xv6 boot acceptance. The first identified blocker is missing FENCE.I; this does not establish that it is the only remaining blocker.

Independent evidence: the current HASHES.txt contains 47 entries, all verified (the proposal says 62; reconcile the manifest/count). Archived run6/run.log.gz has illegal-instruction trap 79 at cycle 192043864, epc=0x3ffffff09c, tval=0x100f; trap 80 is the downstream store page fault. Active tcpu_core.v only recognizes MISC-MEM funct3=000. Replayed r02.elf against accepted core-run3/sim/t0/tcpu_tb: actual exit 2, cause 2, mtval 0x100f, 432 cycles. No full xv6 rerun or new build this review.

1. Approve a narrowly scoped Zifencei implementation, not removal of the kernel instruction. Retiring without extra memory activity is acceptable only with the existing serial completion/fresh-fetch invariant: prior stores must complete before subsequent instruction fetch, and no stale prefetched instruction may survive. Prove this with a self-modifying-code regression through the actual backend, not solely a decode test. Ignore reserved FENCE.I operand fields per the ISA, do not write rd, retire exactly once. Do not make other MISC-MEM encodings legal accidentally.
   Reference: https://docs.riscv.org/reference/isa/unpriv/zifencei.html (official Zifencei specification).
2. Approve 4 MiB as an explicit, isolated fast-simulation build option; retain 16 MiB as default/reference and leave board memory sizing untouched. Record patch, compile option and image identity. This is a capacity-changing configuration, not evidence of equivalence or a guarantee that every command fits. On allocation failure use the reference size, do not weaken tests. First shell/small-program acceptance may be labeled 4 MiB simulation; later board evidence remains separate.
3. Monitor-free simulation is useful for debugging but is not protocol-monitor coverage. Preserve monitored configuration and run focused fence/self-modification validation with monitors enabled before the long fast run.
4. Correct progress wording: reaching userret before its first successful sret does not prove user-mode execution, init exec, or shell. The blkdev geometry banner is not evidence that 4000 sectors were read. Minimal r01 success does not exclude all Sv39/trap defects. Correct these overclaims and the manifest count in the next report.

Continue directly under codex-xv6-fencei-resume; no renewed broad reset work and no synthesis/board access.
