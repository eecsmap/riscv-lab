#!/bin/bash
# PIPE-P4a: dual-pipeline xv6 (m4smoke, perf-short; the accepted runners, named hash-checked inputs, two-hart judges)
# on sims-1/sim-fast, then the bounded single-pipeline regression subset: the P3b association chain's positive set
# on a single-pipeline simulator built from THIS tree's fresh generation (gen-1 RD2PipeBootConfig).
#   chain-xv6.sh <sims dir> <gen dir> <fresh outroot>
# Runner fix: every step's own status (including the single-pipeline BUILD) is captured and any failure fails the
# chain. RUN_XV6 / BUILD_ASSOC1 / RUN_ASSOC override the steps (the self-test injects stubs).
set -u
W=/home/engineer/fpga/worktrees/pipe-dual/experiments/pipeline; SIMS=${1:?sims}; GEN=${2:?gen}; OUT=${3:?out}
RUN_XV6=${RUN_XV6:-$W/p4a/scripts/run-xv6-dual.sh}; BUILD_ASSOC1=${BUILD_ASSOC1:-$W/p2b/soc/assoc/build-assoc-sim.sh}; RUN_ASSOC=${RUN_ASSOC:-$W/p2b/soc/assoc/run-assoc.sh}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT; bad=0
step() { local n=$1; shift; "$@" > $OUT/$n.log 2>&1; local r=$?; echo "  $n: exit $r -- $(tail -n 1 $OUT/$n.log | cut -c1-140)"; [ $r = 0 ] || bad=1; }
step m4smoke bash $RUN_XV6 m4smoke $SIMS/sim-fast/obj_dir/sim $OUT/xv6-m4smoke-pipe-dual
step perf-short bash $RUN_XV6 perf-short $SIMS/sim-fast/obj_dir/sim $OUT/xv6-perf-short-pipe-dual
step single-assoc-build bash $BUILD_ASSOC1 $GEN /home/engineer/fpga/worktrees/pipe-dual/rtl/cpu $OUT/single-assoc-sim
if [ -x $OUT/single-assoc-sim/obj_dir/sim ]; then step single-assoc-run bash $RUN_ASSOC $OUT/single-assoc-sim/obj_dir/sim $OUT/single-assoc-run
else echo "  single-assoc-run: not run, no simulator"; bad=1; fi
echo "CHAIN_XV6_DONE bad=$bad"; exit $bad
