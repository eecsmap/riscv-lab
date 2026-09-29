#!/bin/bash
# PIPE-P2a walker-wrapper unit bench: build one bench per variant (WRAP_FAULT) from a pinned snapshot, then sweep
# 24 profiles: port arbitration (always granted / every third cycle) x ready delay 0..2 x response delay 1..4.  run-wb.sh <fresh outdir> <variant>...  variant = name:WRAP_FAULT
set -u
OUT=${1:?outdir}; shift; [ $# -ge 1 ] || { echo "no variants"; exit 2; }; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
W=/home/engineer/fpga/worktrees/pipe-single; R=$W/rtl/cpu; WBD=$(dirname "$(readlink -f "$0")")
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
mkdir -p $OUT/src
cp $R/tcpu_ptw.v $R/tcpu_permcheck.v $R/tcpu_cacheable.v $R/pipeline/tcpu_ptw_wrap.v $WBD/wb_tb.v $OUT/src/
(cd $OUT/src && sha256sum *) > $OUT/src.sha256
for f in tcpu_ptw.v tcpu_permcheck.v tcpu_cacheable.v; do
  t=$(git -C $W show mc-v1-dual:rtl/cpu/$f | sha256sum | cut -c1-16); c=$(sha256sum $OUT/src/$f | cut -c1-16)
  [ "$t" = "$c" ] && echo "unchanged $f $c (tag mc-v1-dual)" || echo "CHANGED $f tag=$t now=$c"; done | tee $OUT/shared.txt
fail=0
for v in "$@"; do n=${v%%:*}; wf=${v#*:}; mkdir -p $OUT/$n
  if ! timeout 600 verilator --binary --timing -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED \
      -Wno-MULTIDRIVEN -Wno-BLKSEQ --top-module wb_tb -GWF=$wf -Mdir $OUT/$n/obj -o wb_tb $OUT/src/wb_tb.v \
      $OUT/src/tcpu_ptw_wrap.v $OUT/src/tcpu_ptw.v $OUT/src/tcpu_permcheck.v $OUT/src/tcpu_cacheable.v > $OUT/$n/build.log 2>&1; then
    echo "BUILD FAIL $n"; grep %Error $OUT/$n/build.log | head -5; fail=1; continue; fi
  cp $OUT/$n/obj/wb_tb $OUT/$n/; rm -rf $OUT/$n/obj
  for gm in 0 1; do for rd in 0 1 2; do for rs in 1 2 3 4; do
    timeout 300 $OUT/$n/wb_tb +grant-mode=$gm +ready-delay=$rd +resp-delay=$rs > $OUT/$n/gm$gm-rd$rd-rs$rs.log 2>&1
    echo "$n gm=$gm rd=$rd rs=$rs rc=$? $(grep '^WB TOTAL' $OUT/$n/gm$gm-rd$rd-rs$rs.log)"; done; done; done | tee $OUT/$n/sweep.txt
done
echo "RUN_WB_DONE fail=$fail"; exit $fail
