#!/bin/bash
# PIPE-P4a: the four simulators, sequentially (verilator -j 4): fast dual; traced dual with the per-hart association
# checkers; two negatives built from COPIES of the generated Verilog -- the two harts' HART_ID swapped, and the core's
# knob 4 (STORE_UNDER_TRAP) on hart 1 only (with the checkers).   chain-sims.sh <gen dir> <fresh outdir>
# Runner fix (codex-pipe-p4a-runner-exit-fix): every builder's OWN exit status is captured (its output goes to a log;
# no pipe hides it) and any non-zero status fails the chain, as does a missing executable. BUILD_SIM / BUILD_ASSOC
# override the builders (the self-test injects stubs).
set -u
W=/home/engineer/fpga/worktrees/pipe-dual; S=$W/experiments/pipeline/p4a/scripts; GEN=${1:?gen}; OUT=${2:?out}
BUILD_SIM=${BUILD_SIM:-$S/build-rd2-pipe-sim.sh}; BUILD_ASSOC=${BUILD_ASSOC:-$S/build-assoc-dual.sh}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT; bad=0
step() {  # step <name> <command...>: run, keep the log, report the builder's own status
  local n=$1; shift; "$@" > $OUT/$n.log 2>&1; local r=$?
  echo "  $n: builder exit $r -- $(tail -n 1 $OUT/$n.log | cut -c1-120)"; [ $r = 0 ] || bad=1; }
VF=$GEN/after-RD2PipeDualXv6FastConfig/RD2Harness.RD2PipeDualXv6FastConfig.v; VB=$GEN/after-RD2PipeDualBootConfig/RD2Harness.RD2PipeDualBootConfig.v
step sim-fast env NHARTS=2 bash $BUILD_SIM $VF $W/rtl/cpu $OUT/sim-fast
step sim-boot-assoc bash $BUILD_ASSOC $VB $W/rtl/cpu $OUT/sim-boot-assoc
sed -E 's/\.HART_ID\(0\)/.HART_ID(9)/; s/\.HART_ID\(1\)/.HART_ID(0)/; s/\.HART_ID\(9\)/.HART_ID(1)/' $VB > $OUT/neg-hartid-swap.v; diff $VB $OUT/neg-hartid-swap.v > $OUT/neg-hartid-swap.diff
[ $(grep -c '^>' $OUT/neg-hartid-swap.diff) = 2 ] || { echo "REFUSE: the HART_ID swap did not change exactly two lines"; bad=1; }
step sim-neg-hartid-swap env NHARTS=2 bash $BUILD_SIM $OUT/neg-hartid-swap.v $W/rtl/cpu $OUT/sim-neg-hartid-swap
step sim-neg-pf4-h1 bash $BUILD_ASSOC $VB $W/rtl/cpu $OUT/sim-neg-pf4-h1 's/^(\s*tcpu_core_pipe #\()(.*\.HART_ID\(1\))/\1.PIPE_FAULT(4), \2/'
for s in sim-fast sim-boot-assoc sim-neg-hartid-swap sim-neg-pf4-h1; do [ -x $OUT/$s/obj_dir/sim ] || { echo "  MISSING $s"; bad=1; }; done
echo "CHAIN_SIMS_DONE bad=$bad"; exit $bad
