#!/bin/bash
# PIPE-P2b: can judge-gen.sh fail? Each mutant is a scratch copy of a passing gen directory (symlinks, with the one
# mutated file copied) and must be judged FAIL; the unmutated copy must PASS.   selftest-judge-gen.sh <passing gen dir>
set -u
G=$(readlink -f ${1:?gen dir}); HERE=$(cd "$(dirname "$0")" && pwd); T=$(mktemp -d /tmp/claude-1000/sjg-XXXX); bad=0
mk() { local d=$T/$1; mkdir -p $d; for x in $G/before-* $G/after-* $G/refuse.txt; do ln -s $x $d/; done; echo $d; }
mut() {  # mut <name> <file relative to the gen dir> <sed expression> -- replace the symlink of the file's directory by a copy
  local d; d=$(mk $1); local rel=$2 dir=$(dirname $2)
  if [ "$dir" != . ]; then rm $d/$dir; mkdir $d/$dir; for x in $G/$dir/*; do ln -s $x $d/$dir/; done; fi
  rm $d/$rel; sed -E "$3" $G/$rel > $d/$rel; cmp -s $G/$rel $d/$rel && { echo "  INVALID mutant $1: the expression changed nothing"; bad=1; return; }
  bash $HERE/judge-gen.sh $d > $d.out 2>&1 && { echo "  mutant $1 ACCEPTED"; bad=1; } || echo "  mutant $1 refused: $(grep -m1 -E 'DIFFERS|instances [0-9]+, tcpu_core instances [1-9]|ok=0|ELABORATED|tcpu_core_pipe [1-9]|MISSING' $d.out | cut -c1-120)"; }
d=$(mk base); bash $HERE/judge-gen.sh $d > $d.out 2>&1 && echo "  unmutated copy: PASS" || { echo "  unmutated copy FAILS"; bad=1; }
mut logic after-RD2AtomicXv6FastConfig/RD2Harness.RD2AtomicXv6FastConfig.v '0,/32'"'"'h80000002/s//32'"'"'h80000003/'
mut string after-RD2BootConfig/RD2Harness.RD2BootConfig.v '0,/channel has invalid opcode \(connected/s//channel has a bad opcode (connected/'
mut pipe-in-old after-RD2DualBoardConfig/RD2BoardTop.RD2DualBoardConfig.v '0,/^(\s*)tcpu_core\b/s//\1tcpu_core_pipe/'
mut wrong-core after-RD2PipeXv6FastConfig/RD2Harness.RD2PipeXv6FastConfig.v '0,/^(\s*)tcpu_core_pipe\b/s//\1tcpu_core/'
mut no-A after-RD2PipeBootConfig/RD2Harness.RD2PipeBootConfig.v '0,/\.MISA_A\(1\)/s//.MISA_A(0)/'
mut elaborated refuse.txt 's/^(  P2bUnsupportedPipeV1Config): refused: .*/\1: ELABORATED -- must refuse/'
d=$(mk missing); rm $d/after-RD2DualXv6FastConfig; bash $HERE/judge-gen.sh $d > $d.out 2>&1 && { echo "  mutant missing ACCEPTED"; bad=1; } || echo "  mutant missing refused: $(grep -m1 MISSING $d.out)"
rm -rf "${T:?}"
echo "SELFTEST_JUDGE_GEN $([ $bad = 0 ] && echo PASS || echo FAIL)"; exit $bad
