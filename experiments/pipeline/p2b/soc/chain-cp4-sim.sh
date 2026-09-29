#!/bin/bash
# PIPE-P2b checkpoint 4/5: the RD2 pipeline simulator from RD2PipeXv6FastConfig (gen-2) and the manifest, plus the two
# build negatives: the multicycle configuration's Verilog must be refused, and a manifest without tcpu_tlb2.v must
# fail to find the module (no auto-discovery).   chain-cp4-sim.sh <gen dir> <fresh outdir>
set -u
W=/home/engineer/fpga/worktrees/pipe-single; B=$W/experiments/pipeline/p2b/soc/build-rd2-pipe-sim.sh
GEN=${1:?gen dir}; OUT=${2:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT
bash $B $GEN/after-RD2PipeXv6FastConfig/RD2Harness.RD2PipeXv6FastConfig.v $W/rtl/cpu $OUT/sim-pipe; r=$?; bad=0; [ $r = 0 ] || bad=1; echo "BUILD_PIPE_RC=$r"
bash $B $GEN/after-RD2AtomicXv6FastConfig/RD2Harness.RD2AtomicXv6FastConfig.v $W/rtl/cpu $OUT/neg-multicycle-verilog > $OUT/neg-multicycle-verilog.log 2>&1; rc=$?
echo "NEG multicycle Verilog: rc=$rc $(tail -1 $OUT/neg-multicycle-verilog.log)"
{ [ $rc = 2 ] && grep -q "instantiates the multicycle tcpu_core\|does not instantiate tcpu_core_pipe" $OUT/neg-multicycle-verilog.log; } || bad=1
mkdir -p $OUT/neg-rtl/pipeline; cp $W/rtl/cpu/*.v $W/rtl/cpu/*.vh $OUT/neg-rtl/; cp $W/rtl/cpu/pipeline/*.v $OUT/neg-rtl/pipeline/
grep -v 'pipeline/tcpu_tlb2.v' $W/rtl/cpu/pipeline/SOURCES.pipe > $OUT/neg-rtl/pipeline/SOURCES.pipe
bash $B $GEN/after-RD2PipeXv6FastConfig/RD2Harness.RD2PipeXv6FastConfig.v $OUT/neg-rtl $OUT/neg-no-tlb2 > $OUT/neg-no-tlb2.log 2>&1; rc=$?
echo "NEG manifest without tcpu_tlb2.v (the file itself present in the rtl dir): rc=$rc; $(grep -m1 -oE "Cannot find file containing module: '[a-z0-9_]+'" $OUT/neg-no-tlb2/verilator.log 2>/dev/null)"
{ [ $rc != 0 ] && grep -q "Cannot find file containing module: 'tcpu_tlb2'" $OUT/neg-no-tlb2/verilator.log 2>/dev/null; } || bad=1
echo "CHAIN_CP4_SIM_DONE bad=$bad"; exit $bad
