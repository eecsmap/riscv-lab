#!/bin/bash
# PIPE-P4a: the four simulators, sequentially (verilator -j 4): fast dual; traced dual with the per-hart association
# checkers; two negatives built from COPIES of the generated Verilog -- the two harts' HART_ID swapped, and the core's
# knob 4 (STORE_UNDER_TRAP) on hart 1 only (with the checkers).   chain-sims.sh <gen dir> <fresh outdir>
set -u
W=/home/engineer/fpga/worktrees/pipe-dual; S=$W/experiments/pipeline/p4a/scripts; GEN=${1:?gen}; OUT=${2:?out}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT; bad=0
VF=$GEN/after-RD2PipeDualXv6FastConfig/RD2Harness.RD2PipeDualXv6FastConfig.v; VB=$GEN/after-RD2PipeDualBootConfig/RD2Harness.RD2PipeDualBootConfig.v
NHARTS=2 bash $S/build-rd2-pipe-sim.sh $VF $W/rtl/cpu $OUT/sim-fast | tail -1 || bad=1
bash $S/build-assoc-dual.sh $VB $W/rtl/cpu $OUT/sim-boot-assoc | tail -1 || bad=1
sed -E 's/\.HART_ID\(0\)/.HART_ID(9)/; s/\.HART_ID\(1\)/.HART_ID(0)/; s/\.HART_ID\(9\)/.HART_ID(1)/' $VB > $OUT/neg-hartid-swap.v; diff $VB $OUT/neg-hartid-swap.v > $OUT/neg-hartid-swap.diff
[ $(grep -c '^>' $OUT/neg-hartid-swap.diff) = 2 ] || { echo "REFUSE: the HART_ID swap did not change exactly two lines"; bad=1; }
NHARTS=2 bash $S/build-rd2-pipe-sim.sh $OUT/neg-hartid-swap.v $W/rtl/cpu $OUT/sim-neg-hartid-swap | tail -1 || bad=1
bash $S/build-assoc-dual.sh $VB $W/rtl/cpu $OUT/sim-neg-pf4-h1 's/^(\s*tcpu_core_pipe #\()(.*\.HART_ID\(1\))/\1.PIPE_FAULT(4), \2/' | tail -1 || bad=1
for s in sim-fast sim-boot-assoc sim-neg-hartid-swap sim-neg-pf4-h1; do [ -x $OUT/$s/obj_dir/sim ] || { echo "MISSING $s"; bad=1; }; done
echo "CHAIN_SIMS_DONE bad=$bad"; exit $bad
