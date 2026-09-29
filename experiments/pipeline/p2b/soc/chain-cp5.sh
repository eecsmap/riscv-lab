#!/bin/bash
# PIPE-P2b checkpoint 5 (after m4smoke on the pipeline, runs/xv6-m4smoke-pipe-1): perf-short on the pipeline, then the
# multicycle N=1 reference for m4smoke (m3/runs/sim-single: the accepted single-core simulator; its SoC Verilog is
# normalized-identical to gen-2's RD2AtomicXv6FastConfig) on the same kernel and disk, then the comparison.
set -u
bad=0; ck() { [ "$1" = 0 ] || bad=1; }
P=/home/engineer/fpga/worktrees/pipe-single/experiments/pipeline/p2b; SIMP=$P/runs/rd2sim-1/sim-pipe/obj_dir/sim
SIMM=/home/engineer/fpga/experiments/multicore/m3/runs/sim-single/obj_dir/sim
bash $P/soc/run-xv6-p2b.sh perf-short $SIMP $P/runs/xv6-perf-short-pipe-1; r=$?; ck $r; echo "PERF_PIPE_RC=$r"
bash $P/soc/run-xv6-p2b.sh m4smoke $SIMM $P/runs/xv6-m4smoke-multi-ref-1; r=$?; ck $r; echo "SMOKE_MULTI_RC=$r"
python3 $P/soc/xv6compare.py pipe-m4smoke=$P/runs/xv6-m4smoke-pipe-1 multi-m4smoke=$P/runs/xv6-m4smoke-multi-ref-1 \
  pipe-perf-short=$P/runs/xv6-perf-short-pipe-1 multi-perf-short=$P/runs/xv6-perf-short-multi-ref | tee $P/runs/xv6-compare-1.txt; ck ${PIPESTATUS[0]}
echo "CHAIN_CP5_DONE bad=$bad"; exit $bad
