#!/bin/bash
# PIPE-P2b checkpoint 4/5 re-run after the hart wrapper's PTE classification (TeachingCpuV2, pipeline only): regenerate
# before/after (gen-3, judged), rebuild the RD2 pipeline simulator with its negatives (rd2sim-2), then both xv6 gates
# on it and the comparison with the multicycle references.
set -u
bad=0; ck() { [ "$1" = 0 ] || bad=1; }
P=/home/engineer/fpga/worktrees/pipe-single/experiments/pipeline/p2b
bash $P/soc/gen-cp4.sh 35c05eb $P/runs/gen-3 > $P/runs/gen-3.log 2>&1; r=$?; ck $r; echo "GEN3_RC=$r"; tail -1 $P/runs/gen-3.log
bash $P/soc/selftest-judge-gen.sh $P/runs/gen-3 > $P/runs/gen-3-selftest.txt 2>&1; r=$?; ck $r; echo "SELFTEST_JUDGE_RC=$r"
bash $P/soc/chain-cp4-sim.sh $P/runs/gen-3 $P/runs/rd2sim-2; r=$?; ck $r; echo "SIM2_RC=$r"
SIMP=$P/runs/rd2sim-2/sim-pipe/obj_dir/sim
[ -x $SIMP ] || { echo "NO SIMULATOR"; exit 1; }
bash $P/soc/run-xv6-p2b.sh m4smoke $SIMP $P/runs/xv6-m4smoke-pipe-2; r=$?; ck $r; echo "SMOKE_PIPE2_RC=$r"
bash $P/soc/run-xv6-p2b.sh perf-short $SIMP $P/runs/xv6-perf-short-pipe-2; r=$?; ck $r; echo "PERF_PIPE2_RC=$r"
python3 $P/soc/xv6compare.py pipe-m4smoke=$P/runs/xv6-m4smoke-pipe-2 multi-m4smoke=$P/runs/xv6-m4smoke-multi-ref-1 \
  pipe-perf-short=$P/runs/xv6-perf-short-pipe-2 multi-perf-short=$P/runs/xv6-perf-short-multi-ref | tee $P/runs/xv6-compare-2.txt; ck ${PIPESTATUS[0]}
echo "CHAIN_CP5B_DONE bad=$bad"; exit $bad
