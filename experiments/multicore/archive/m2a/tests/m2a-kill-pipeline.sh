#!/usr/bin/env bash
# kill fix, round 2: everything the counter change can touch, rerun from the FIXED private common into new
# directories (the pre-fix rounds stay as history): directed 11, random 10, topology 3, negatives 8, the
# original CPU-A 27 (original score.py), the single-core RD2 regression vs M1.   m2a-kill-pipeline.sh <runs root>
set -u; HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); RUNS=${1:?runs root}; rc=0
t() { date -u +%FT%TZ; }
g() { local name=$1 grp=$2; echo "== $(t) $name =="; bash $HERE/dual-all.sh $RUNS/$name $grp 2>&1 | tee $RUNS/$name.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1; }
g dual-directed-fix directed; g dual-random-fix random; g dual-topo-fix topo; g dual-neg-fix neg
echo "== $(t) atomic-rerun-fix =="; bash $HERE/atomic-rerun.sh $RUNS/atomic-rerun-fix 2>&1 | tee $RUNS/atomic-rerun-fix.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
echo "== $(t) rd2-fix =="; bash $HERE/rd2-regress.sh $RUNS/rd2-fix all 2>&1 | tee $RUNS/rd2-fix.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
echo "== $(t) KILL_PIPELINE_DONE rc=$rc"; exit $rc
