#!/bin/bash
# PIPE-P4a: dual-pipeline xv6 (m4smoke, perf-short; the accepted runners, named hash-checked inputs, two-hart judges)
# on sims-1/sim-fast, then the bounded single-pipeline regression subset: the P3b association chain's positive set
# on a single-pipeline simulator built from THIS tree's fresh generation (gen-1 RD2PipeBootConfig).
#   chain-xv6.sh <sims dir> <gen dir> <fresh outroot>
set -u
W=/home/engineer/fpga/worktrees/pipe-dual/experiments/pipeline; SIMS=${1:?sims}; GEN=${2:?gen}; OUT=${3:?out}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT; bad=0; ck() { [ "$1" = 0 ] || bad=1; }
bash $W/p4a/scripts/run-xv6-dual.sh m4smoke $SIMS/sim-fast/obj_dir/sim $OUT/xv6-m4smoke-pipe-dual; r=$?; ck $r; echo "M4SMOKE_RC=$r"
bash $W/p4a/scripts/run-xv6-dual.sh perf-short $SIMS/sim-fast/obj_dir/sim $OUT/xv6-perf-short-pipe-dual; r=$?; ck $r; echo "PERF_RC=$r"
bash $W/p2b/soc/assoc/build-assoc-sim.sh $GEN /home/engineer/fpga/worktrees/pipe-dual/rtl/cpu $OUT/single-assoc-sim | tail -1
bash $W/p2b/soc/assoc/run-assoc.sh $OUT/single-assoc-sim/obj_dir/sim $OUT/single-assoc-run | tail -3; r=${PIPESTATUS[0]}; ck $r; echo "SINGLE_ASSOC_RC=$r"
echo "CHAIN_XV6_DONE bad=$bad"; exit $bad
