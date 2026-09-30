#!/bin/bash
# PIPE-P4a: elaborate before (<base>, the tag pipe-v1-single) and after (this worktree) from private commons and judge:
#   * the ten existing configurations (multicycle 1/2 in the Xv6Fast, Boot and Board shapes, the V1 RD2Boot, and the
#     three single-pipeline ones) must be normalized-identical before/after (scala source locators removed);
#   * the two dual-pipeline configurations must instantiate tcpu_core_pipe exactly twice, HART_ID 0 and 1, with
#     MISA_A / PIPE_EXT_M / C / SU = 1 and nothing else passed, and never tcpu_core;
#   * the refusals must refuse with their messages (pipeline x4, multicycle x4, x0, unknown CORE_IMPL, pipeline V1).
#   gen-p4a.sh <base> <fresh outdir>
set -u
W=/home/engineer/fpga/worktrees/pipe-dual; G=/home/engineer/fpga/experiments/multicore/m4/gen
BASE=${1:?base}; OUT=${2:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT/scala-before
git -C $W archive $BASE soc/scala/teaching | tar -x -C $OUT/scala-before || exit 2
git -C $W diff --quiet $BASE -- soc/scala/teaching && { echo "REFUSE: scala unchanged since $BASE"; exit 2; }
cp -a $W/soc/scala/teaching $OUT/scala-after; git -C $W diff $BASE -- soc/scala/teaching > $OUT/scala.diff; git -C $W rev-parse HEAD > $OUT/head.txt
ln -s /home/engineer/fpga/teaching-cpu-work/fpga-zynq/common $OUT/common      # the boot ROM is read via ../common
bash $G/prepare-common.sh $OUT/scala-before/soc/scala/teaching $OUT/common-before | tail -1
bash $G/prepare-common.sh $OUT/scala-after $OUT/common-after | tail -1
OLD="RD2Harness:RD2AtomicXv6FastConfig RD2Harness:RD2DualXv6FastConfig RD2Harness:RD2AtomicBootConfig RD2Harness:RD2DualBootConfig RD2Harness:RD2BootConfig RD2BoardTop:RD2AtomicBoardConfig RD2BoardTop:RD2DualBoardConfig RD2Harness:RD2PipeXv6FastConfig RD2Harness:RD2PipeBootConfig RD2BoardTop:RD2PipeBoardConfig"
norm() { sed -E 's#[[:space:]]*// @\[[^]]*\]##; s#\(connected at [A-Za-z0-9_]+\.scala:[0-9]+:[0-9]+\)#(connected at <scala>)#g' "$1"; }
bad=0
echo "== existing configurations: before vs after" | tee $OUT/old.txt
for tc in $OLD; do t=${tc%%:*}; c=${tc#*:}
  bash $G/gen.sh $t $c $OUT/common-before $OUT/before-$c > $OUT/before-$c.log 2>&1
  bash $G/gen.sh $t $c $OUT/common-after $OUT/after-$c > $OUT/after-$c.log 2>&1
  vb=$OUT/before-$c/$t.$c.v; va=$OUT/after-$c/$t.$c.v
  if [ ! -s $vb ] || [ ! -s $va ]; then echo "  $c: GEN FAILED" | tee -a $OUT/old.txt; bad=1; continue; fi
  cmp -s $vb $va && raw="raw identical" || raw="raw differs in $(diff $vb $va | grep -c '^[<>]') lines"
  diff <(norm $vb) <(norm $va) > $OUT/norm-$c.diff && nm="normalized IDENTICAL" || { nm="normalized DIFFERS ($(grep -c '^[<>]' $OUT/norm-$c.diff) lines)"; bad=1; }
  echo "  $c: $raw; $nm; tcpu_core $(grep -cE '^\s*tcpu_core\b' $va), tcpu_core_pipe $(grep -cE '^\s*tcpu_core_pipe\b' $va); after $(sha256sum $va | cut -c1-16)" | tee -a $OUT/old.txt
done
echo "== the dual-pipeline configurations" | tee $OUT/new.txt
for tc in RD2Harness:RD2PipeDualXv6FastConfig RD2Harness:RD2PipeDualBootConfig; do t=${tc%%:*}; c=${tc#*:}
  bash $G/gen.sh $t $c $OUT/common-after $OUT/after-$c > $OUT/after-$c.log 2>&1; v=$OUT/after-$c/$t.$c.v
  [ -s $v ] || { echo "  $c: GEN FAILED" | tee -a $OUT/new.txt; bad=1; continue; }
  grep -E '^\s*tcpu_core_pipe #' $v | sed -E 's#\s*// @.*##; s#^\s*##' > $OUT/$c.instances.txt
  n=$(wc -l < $OUT/$c.instances.txt); nc=$(grep -cE '^\s*tcpu_core\b' $v)
  h0=$(grep -c '\.HART_ID(0)' $OUT/$c.instances.txt); h1=$(grep -c '\.HART_ID(1)' $OUT/$c.instances.txt)
  ext=$(grep -c '\.MISA_A(1).*\.PIPE_EXT' $OUT/$c.instances.txt); allp=$(grep -cE '\.(MISA_A|PIPE_EXT_SU|PIPE_EXT_M|PIPE_EXT_C)\(1\).*\.(MISA_A|PIPE_EXT_SU|PIPE_EXT_M|PIPE_EXT_C)\(1\).*\.(MISA_A|PIPE_EXT_SU|PIPE_EXT_M|PIPE_EXT_C)\(1\).*\.(MISA_A|PIPE_EXT_SU|PIPE_EXT_M|PIPE_EXT_C)\(1\)' $OUT/$c.instances.txt)
  extra=$(grep -oE '\.[A-Z_]+\(' $OUT/$c.instances.txt | sort -u | grep -vE '\.(MISA_A|PIPE_EXT_SU|PIPE_EXT_M|PIPE_EXT_C|HART_ID|RESET_PC)\(' | tr '\n' ' ')
  ok=1; { [ $n = 2 ] && [ $nc = 0 ] && [ $h0 = 1 ] && [ $h1 = 1 ] && [ $allp = 2 ] && [ -z "$extra" ]; } || { ok=0; bad=1; }
  echo "  $c: $(sha256sum $v | cut -c1-16); tcpu_core_pipe instances $n (HART_ID 0: $h0, 1: $h1; M/C/SU/A on both: $allp), tcpu_core $nc; other parameters: ${extra:-none}; ok=$ok" | tee -a $OUT/new.txt
  sed 's/^/      /' $OUT/$c.instances.txt | tee -a $OUT/new.txt
done
echo "== refusals" | tee $OUT/refuse.txt
for cm in "MC1UnsupportedPipelineConfig:unsupported NUM_CORES=4" "MC2UnsupportedQuadConfig:unsupported NUM_CORES=4" "MC1UnsupportedZeroConfig:unsupported NUM_CORES=0" \
          "P2bUnsupportedImplConfig:unsupported CORE_IMPL=superscalar" "P2bUnsupportedPipeV1Config:unsupported CORE_IMPL=pipeline with atomic=false"; do
  c=${cm%%:*}; msg=${cm#*:}
  bash $G/gen.sh RD2Harness $c $OUT/common-after $OUT/refuse-$c > $OUT/refuse-$c.log 2>&1; ra=$?
  if [ $ra = 0 ]; then echo "  $c: ELABORATED -- must refuse" | tee -a $OUT/refuse.txt; bad=1
  elif grep -qF "$msg" $OUT/refuse-$c/gen.log; then echo "  $c: refused: $msg" | tee -a $OUT/refuse.txt
  else echo "  $c: failed WITHOUT '$msg'" | tee -a $OUT/refuse.txt; bad=1; fi
done
echo "GEN_P4A_DONE bad=$bad"; exit $bad
