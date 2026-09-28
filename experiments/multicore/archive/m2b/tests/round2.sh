#!/usr/bin/env bash
# Round 2 after the two scala fixes (holdAll only for nHarts > 1; NUM_CORES=0 refusal wording in the hub):
# sync the private common, regenerate the dual configurations and compare their Verilog with round 1
# (identical => the dual results of round 1 stand; else the dual chain is rebuilt and rerun), then the full
# single-core / unit regression again (n1).
set -u; M2B=/home/engineer/fpga/experiments/multicore/m2b; T=$M2B/tests; R=$M2B/runs; W=/home/engineer/fpga/worktrees/mc-dual-core/soc/scala/teaching; GC=$M2B/gen/common-dual; RTL=/home/engineer/fpga/worktrees/mc-dual-core/rtl/cpu
t() { date -u +%FT%TZ; }
echo "== $(t) sync =="; cp $W/*.scala $W/*.cpp $GC/src/main/scala/teaching/; (cd $GC/src/main/scala/teaching && sha256sum *.scala *.cpp) | diff -q - <(cd $W && sha256sum *.scala *.cpp) >/dev/null && echo "private common == worktree" || { echo SYNC FAILED; exit 1; }
echo "== $(t) regenerate dual configs =="; TOPPROJ=teaching bash $M2B/gen/gen.sh RD2Harness RD2DualBootConfig $GC $R/gen-dual-boot-r2 | tail -1; TOPPROJ=teaching bash $M2B/gen/gen.sh RD2Harness RD2DualXv6FastConfig $GC $R/gen-dual-fast-r2 | tail -1
same=1
for pair in "compile-check-1/RD2Harness.RD2DualBootConfig.v gen-dual-boot-r2/RD2Harness.RD2DualBootConfig.v" "gen-dual-fast/RD2Harness.RD2DualXv6FastConfig.v gen-dual-fast-r2/RD2Harness.RD2DualXv6FastConfig.v"; do set -- $pair
  if cmp -s $R/$1 $R/$2; then echo "  dual verilog identical: $2 == $1 ($(sha256sum $R/$2 | cut -c1-16))"; else echo "  dual verilog CHANGED: $1 vs $2"; same=0; fi; done
echo "DUAL_VERILOG_SAME=$same"
if [ $same = 0 ]; then
  echo "== $(t) rebuild dual sims and rerun the dual chain =="
  NHARTS=2 bash $T/build-dual-sim.sh $R/gen-dual-boot-r2/RD2Harness.RD2DualBootConfig.v $RTL $R/sim-dual-boot-r2 | tail -1
  NHARTS=2 bash $T/build-dual-sim.sh $R/gen-dual-fast-r2/RD2Harness.RD2DualXv6FastConfig.v $RTL $R/sim-dual-fast-r2 | tail -1
  rm -rf $R/sim-dual-boot $R/sim-dual-fast; ln -s sim-dual-boot-r2 $R/sim-dual-boot; ln -s sim-dual-fast-r2 $R/sim-dual-fast
  bash $T/smoke2.sh $R/smoke-r2 | tail -1; bash $T/m2b-suite.sh $R/suite-r2 all | tail -1
fi
echo "== $(t) n1 regression, round 2 =="; bash $T/n1-regress.sh $R/n1-r2 2>&1 | tee $R/n1-r2.log | tail -1
echo "== $(t) ROUND2_DONE"
