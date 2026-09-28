#!/usr/bin/env bash
# MC-M2a: the remaining evidence groups back to back (one heavy job; each group writes its own directory and
# its own DONE line; a failing group does not stop the later ones -- the report needs all of them).
#   m2a-pipeline.sh <runs root>
set -u; HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); RUNS=${1:?runs root}; rc=0
t() { date -u +%FT%TZ; }
echo "== $(t) topo =="; bash $HERE/dual-all.sh $RUNS/dual-topo topo 2>&1 | tee $RUNS/dual-topo.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
echo "== $(t) neg =="; bash $HERE/dual-all.sh $RUNS/dual-neg neg 2>&1 | tee $RUNS/dual-neg.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
echo "== $(t) atomic-rerun =="; bash $HERE/atomic-rerun.sh $RUNS/atomic-rerun 2>&1 | tee $RUNS/atomic-rerun.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
echo "== $(t) rd2 =="; bash $HERE/rd2-regress.sh $RUNS/rd2 all 2>&1 | tee $RUNS/rd2.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
echo "== $(t) PIPELINE_DONE rc=$rc"; exit $rc
