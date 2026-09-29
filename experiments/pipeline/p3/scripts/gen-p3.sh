#!/bin/bash
# PIPE-P3a: re-elaborate from the pinned scala (the worktree at the commit being built) and compare.
#   gen-p3.sh <base commit = the accepted P2b anchor> <fresh outdir>
# 1. p2b/soc/gen-cp4.sh <base> <out>/gen: before (base) / after (worktree) for the seven existing configurations,
#    judged normalized-identical; the two pipeline simulation configurations; the five refusals (incl. pipeline x2).
# 2. RD2BoardTop.RD2PipeBoardConfig from the same "after" common.
# 3. comparisons, module by module (vmodule-diff.py): RD2PipeBoardConfig vs RD2AtomicBoardConfig (the accepted
#    single multicycle board shape: only the hart may differ), vs gen-3 RD2PipeXv6FastConfig (the accepted P2b
#    integration: the intended board-shape differences), and gen-3 vs the fresh RD2PipeXv6FastConfig (the fresh
#    re-elaboration reproduces the accepted one).
set -u
W=/home/engineer/fpga/worktrees/pipe-single; P3=$W/experiments/pipeline/p3; G=/home/engineer/fpga/experiments/multicore/m4/gen
BASE=${1:?base}; OUT=${2:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT
git -C $W status --porcelain -- soc rtl > $OUT/worktree-status.txt; git -C $W rev-parse HEAD > $OUT/head.txt
bash $W/experiments/pipeline/p2b/soc/gen-cp4.sh $BASE $OUT/gen > $OUT/gen-cp4.log 2>&1; r1=$?; echo "GEN_CP4_RC=$r1"; tail -1 $OUT/gen-cp4.log
bash $G/gen.sh RD2BoardTop RD2PipeBoardConfig $OUT/gen/common-after $OUT/gen/after-RD2PipeBoardConfig > $OUT/gen-board.log 2>&1; r2=$?
echo "GEN_BOARD_RC=$r2 $(tail -1 $OUT/gen-board.log)"
V=$OUT/gen/after-RD2PipeBoardConfig/RD2BoardTop.RD2PipeBoardConfig.v
bad=0; [ $r1 = 0 ] && [ $r2 = 0 ] && [ -s $V ] || bad=1
if [ -s $V ]; then
  python3 $P3/scripts/vmodule-diff.py $OUT/gen/after-RD2AtomicBoardConfig/RD2BoardTop.RD2AtomicBoardConfig.v $V --label-a multicycle-board --label-b pipeline-board --show 3 > $OUT/cmp-vs-atomic-board.txt
  python3 $P3/scripts/vmodule-diff.py $W/experiments/pipeline/p2b/runs/gen-3/after-RD2PipeXv6FastConfig/RD2Harness.RD2PipeXv6FastConfig.v $V --label-a gen3-pipe-xv6fast --label-b pipeline-board > $OUT/cmp-vs-gen3.txt
  python3 $P3/scripts/vmodule-diff.py $W/experiments/pipeline/p2b/runs/gen-3/after-RD2PipeXv6FastConfig/RD2Harness.RD2PipeXv6FastConfig.v $OUT/gen/after-RD2PipeXv6FastConfig/RD2Harness.RD2PipeXv6FastConfig.v --label-a gen3 --label-b fresh > $OUT/cmp-gen3-vs-fresh.txt
  # the harness -> board differences, for both cores: they must be the same modules (only TeachingCpuV2 may differ)
  python3 $P3/scripts/vmodule-diff.py $OUT/gen/after-RD2AtomicXv6FastConfig/RD2Harness.RD2AtomicXv6FastConfig.v $OUT/gen/after-RD2AtomicBoardConfig/RD2BoardTop.RD2AtomicBoardConfig.v --label-a multi-xv6fast --label-b multi-board > $OUT/cmp-multi-xv6fast-vs-board.txt
  python3 $P3/scripts/vmodule-diff.py $OUT/gen/after-RD2PipeXv6FastConfig/RD2Harness.RD2PipeXv6FastConfig.v $V --label-a pipe-xv6fast --label-b pipe-board > $OUT/cmp-pipe-xv6fast-vs-board.txt
  diff <(sed -E 's/(multi|pipe)-(xv6fast|board)/X-\2/g' $OUT/cmp-multi-xv6fast-vs-board.txt) <(sed -E 's/(multi|pipe)-(xv6fast|board)/X-\2/g' $OUT/cmp-pipe-xv6fast-vs-board.txt) > $OUT/cmp-board-delta-multi-vs-pipe.diff
  grep -v "TeachingCpuV2" $OUT/cmp-board-delta-multi-vs-pipe.diff | grep -q '^[<>]' && { echo "  the harness->board delta differs beyond TeachingCpuV2"; bad=1; }
  for f in cmp-vs-atomic-board cmp-vs-gen3 cmp-gen3-vs-fresh cmp-multi-xv6fast-vs-board cmp-pipe-xv6fast-vs-board; do echo "  $f: $(tail -n 1 $OUT/$f.txt)"; done
  grep -q "differing=1 only_a=0 only_b=0" $OUT/cmp-vs-atomic-board.txt && grep -q "^  TeachingCpuV2:" $OUT/cmp-vs-atomic-board.txt || { echo "  the board RTL differs from the multicycle board beyond TeachingCpuV2"; bad=1; }
  grep -q "differing=0 only_a=0 only_b=0" $OUT/cmp-gen3-vs-fresh.txt || { echo "  the fresh RD2PipeXv6FastConfig differs from gen-3"; bad=1; }
  grep -m1 -E "^\s*tcpu_core_pipe #" $V | sed -E 's#\s*// @.*##' | tee $OUT/pipe-instance.txt
  echo "  tcpu_core_pipe instances $(grep -cE '^\s*tcpu_core_pipe\b' $V), tcpu_core instances $(grep -cE '^\s*tcpu_core\b' $V)" | tee -a $OUT/pipe-instance.txt
  { [ $(grep -cE '^\s*tcpu_core_pipe\b' $V) = 1 ] && [ $(grep -cE '^\s*tcpu_core\b' $V) = 0 ]; } || bad=1
fi
echo "GEN_P3_DONE bad=$bad"; exit $bad
