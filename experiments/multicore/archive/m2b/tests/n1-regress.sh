#!/usr/bin/env bash
# MC-M2b single-core (NUM_CORES=1) and unit-harness regressions from the m2b private common (the scala with
# the multi-hart SoC): the same chains as M2a's, so nothing here is new judgement -- it is the proof that the
# one-hart build still behaves exactly as M1's accepted closeout, that the backend unit scenarios (incl. the
# kill group) still pass, and that the matrix entries that must refuse still refuse.
#   n1-regress.sh <outroot>
set -u; M2B=/home/engineer/fpga/experiments/multicore/m2b; M2A=/home/engineer/fpga/experiments/multicore/m2a; T=$M2B/tests; OUT=$(readlink -f -m "${1:?outroot}"); mkdir -p $OUT; rc=0
t() { date -u +%FT%TZ; }
echo "== $(t) matrix refusals (pipeline, 0, 4 must fail at elaboration with 'unsupported' and the value) =="
for c in MC1UnsupportedPipelineConfig MC1UnsupportedZeroConfig MC2UnsupportedQuadConfig; do
  TOPPROJ=teaching bash $M2B/gen/gen.sh RD2Harness $c $M2B/gen/common-dual $OUT/refuse-$c > $OUT/refuse-$c.out 2>&1; g=$?
  msg=$(sed 's/\x1b\[[0-9;]*m//g' $OUT/refuse-$c/gen.log | grep -oE "unsupported (CORE_IMPL|NUM_CORES)=[^\"]{0,80}" | head -1)
  if [ $g -ne 0 ] && [ -n "$msg" ]; then echo "  $c: refused -- $msg"; else echo "  $c: NOT refused (rc=$g '$msg')"; rc=1; fi; done
echo "== $(t) RD2 single-core regression vs M1 closeout2 (gen x2, probes fast+trace, compare, R-BOOT) =="
bash $T/rd2-regress.sh $OUT/rd2 all 2>&1 | tee $OUT/rd2.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
echo "== $(t) the original CPU-A 27 scenarios (original score.py) from the m2b common =="
bash $T/atomic-rerun.sh $OUT/atomic-rerun 2>&1 | tee $OUT/atomic-rerun.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
echo "== $(t) M2a directed + kill groups from the m2b common (backend unchanged; the harness scala is) =="
GC=$M2B/gen/common-dual bash $M2A/tests/dual-all.sh $OUT/dual-directed directed 2>&1 | tee $OUT/dual-directed.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
GC=$M2B/gen/common-dual bash $M2A/tests/dual-all.sh $OUT/dual-kill kill 2>&1 | tee $OUT/dual-kill.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
echo "== $(t) N1_REGRESS_DONE rc=$rc"; exit $rc
