# freq_spin_dual.S in the P4a two-pipeline simulators (before any board use)
* `freq_sim_a` / `freq_sim_b`: the same source with SPIN_CYCLES 100,000 / 300,000, built by `build-freq-dual.sh`, run
  by the M2b `run-dual.sh` on P4a's `sims-1/sim-boot-assoc` (traced, one association checker per hart) and
  `sims-1/sim-fast`. All four: exit 0, `TEACHING-FREQ-SPIN-OK`, `hart1_id=0x1`, cycles 100,008 / 300,008, mtime
  1,001 / 3,001 (cycles/mtime = 99.9), `ASSOC H0/H1 END fails=0` on the traced runs.
* `first-run-clobber/`: the first build printed `mtime_delta=0xfffffffffffffffc`. The loads were right (trace: 0x1c
  then 0x405); the program kept the delta in s7, which M2b's `htif_puthex` clobbers. Fixed (s4); freq_judge.py now
  refuses a ratio outside 100 +- 1 % and a hart1_id other than 1 (selftest/test-freq-judge.sh, both checks mutated).
* The board ELFs (`board-elfs.sha256`, 40,000,000 / 840,000,000 cycles) differ from the sim ELF only in the two
  instructions that load SPIN_CYCLES (`board-vs-sim-disasm.diff`: same lui+addiw pair, same addresses).
