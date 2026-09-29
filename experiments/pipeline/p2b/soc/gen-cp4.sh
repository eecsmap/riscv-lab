#!/bin/bash
# PIPE-P2b checkpoint 4: elaborate the SoC configurations from the scala BEFORE the change (git HEAD at checkpoint 3,
# extracted) and AFTER it (the worktree), each from its own private common (multicore/m4/gen/prepare-common.sh +
# gen.sh, unchanged, read-only), then
#   * every existing configuration: the generated Verilog before vs after, raw and normalized (source locators
#     `// @[File.scala l:c]` removed -- editing a scala file moves them); normalized must be identical
#   * the pipeline configurations: elaborate, instantiate tcpu_core_pipe with the pipeline parameters and never
#     tcpu_core
#   * the refused matrix entries: each must FAIL with "unsupported" and its value
#   gen-cp4.sh <base commit> <fresh outdir>
set -u
W=/home/engineer/fpga/worktrees/pipe-single; G=/home/engineer/fpga/experiments/multicore/m4/gen
BASE=${1:?base commit}; OUT=${2:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p $OUT/scala-before || exit 2
git -C $W archive $BASE soc/scala/teaching | tar -x -C $OUT/scala-before || { echo "REFUSE: cannot extract $BASE"; exit 2; }
git -C $W diff --quiet $BASE -- soc/scala/teaching && { echo "REFUSE: the worktree scala equals $BASE: nothing to compare"; exit 2; }
cp -a $W/soc/scala/teaching $OUT/scala-after
git -C $W diff $BASE -- soc/scala/teaching > $OUT/scala.diff
# the teaching boot ROM is read as ../common/src/main/resources/... relative to the private common (the generator runs
# there), so a private common needs a `common` beside it -- m4/gen has the same symlink (found by gen-1, which failed
# before and after alike on NoSuchFileException bootrom.teaching.rv64.img)
ln -s /home/engineer/fpga/teaching-cpu-work/fpga-zynq/common $OUT/common
bash $G/prepare-common.sh $OUT/scala-before/soc/scala/teaching $OUT/common-before | tail -1
bash $G/prepare-common.sh $OUT/scala-after $OUT/common-after | tail -1
OLD="RD2Harness:RD2AtomicXv6FastConfig RD2Harness:RD2DualXv6FastConfig RD2Harness:RD2AtomicBootConfig RD2Harness:RD2DualBootConfig RD2Harness:RD2BootConfig RD2BoardTop:RD2AtomicBoardConfig RD2BoardTop:RD2DualBoardConfig"
norm() { sed -E 's#[[:space:]]*// @\[[^]]*\]##' "$1"; }
echo "== existing configurations: before vs after" | tee $OUT/old.txt
for tc in $OLD; do t=${tc%%:*}; c=${tc#*:}
  bash $G/gen.sh $t $c $OUT/common-before $OUT/before-$c > $OUT/before-$c.log 2>&1; rb=$?
  bash $G/gen.sh $t $c $OUT/common-after $OUT/after-$c > $OUT/after-$c.log 2>&1; ra=$?
  vb=$OUT/before-$c/$t.$c.v; va=$OUT/after-$c/$t.$c.v
  if [ $rb != 0 ] || [ $ra != 0 ] || [ ! -s $vb ] || [ ! -s $va ]; then echo "  $c: GEN FAILED before rc=$rb after rc=$ra" | tee -a $OUT/old.txt; continue; fi
  cmp -s $vb $va && raw="raw identical" || raw="raw differs in $(diff $vb $va | grep -c '^[<>]') lines"
  diff <(norm $vb) <(norm $va) > $OUT/norm-$c.diff && nm="normalized IDENTICAL" || nm="normalized DIFFERS ($(grep -c '^[<>]' $OUT/norm-$c.diff) lines)"
  echo "  $c: $raw; $nm; tcpu_core instances $(grep -cE '^\s*tcpu_core\b' $va), tcpu_core_pipe $(grep -cE '^\s*tcpu_core_pipe\b' $va); sha before $(sha256sum $vb | cut -c1-16) after $(sha256sum $va | cut -c1-16)" | tee -a $OUT/old.txt
done
echo "== pipeline configurations (after)" | tee $OUT/pipe.txt
for c in RD2PipeXv6FastConfig RD2PipeBootConfig; do
  bash $G/gen.sh RD2Harness $c $OUT/common-after $OUT/after-$c > $OUT/after-$c.log 2>&1; ra=$?; v=$OUT/after-$c/RD2Harness.$c.v
  if [ $ra != 0 ] || [ ! -s $v ]; then echo "  $c: GEN FAILED rc=$ra" | tee -a $OUT/pipe.txt; continue; fi
  inst=$(grep -A8 -E '^\s*tcpu_core_pipe\b' $v | tr -s ' \n' ' ' | cut -c1-300)
  echo "  $c: generated $(sha256sum $v | cut -c1-16); tcpu_core_pipe instances $(grep -cE '^\s*tcpu_core_pipe\b' $v), tcpu_core instances $(grep -cE '^\s*tcpu_core\b' $v); instance: $inst" | tee -a $OUT/pipe.txt
done
echo "== configurations that must refuse (after)" | tee $OUT/refuse.txt
for cm in "MC1UnsupportedPipelineConfig:unsupported CORE_IMPL=pipeline with NUM_CORES=2" "P2bUnsupportedImplConfig:unsupported CORE_IMPL=superscalar" \
          "P2bUnsupportedPipeV1Config:unsupported CORE_IMPL=pipeline with atomic=false" "MC2UnsupportedQuadConfig:unsupported NUM_CORES=4" "MC1UnsupportedZeroConfig:unsupported NUM_CORES=0"; do
  c=${cm%%:*}; msg=${cm#*:}
  bash $G/gen.sh RD2Harness $c $OUT/common-after $OUT/refuse-$c > $OUT/refuse-$c.log 2>&1; ra=$?
  if [ $ra = 0 ]; then echo "  $c: ELABORATED -- must refuse" | tee -a $OUT/refuse.txt
  elif grep -qF "$msg" $OUT/refuse-$c/gen.log; then echo "  $c: refused: $(grep -m1 -oF "$msg" $OUT/refuse-$c/gen.log)" | tee -a $OUT/refuse.txt
  else echo "  $c: failed WITHOUT the expected message ($msg)" | tee -a $OUT/refuse.txt; fi
done
# the verdict (judge-gen.sh, re-runnable on the stored Verilog)
bash "$(dirname "$0")/judge-gen.sh" $OUT | tee $OUT/judge-gen.txt; bad=${PIPESTATUS[0]}
echo "GEN_CP4_DONE fails=$bad"; exit $bad
