#!/usr/bin/env bash
# MC-M2a final round, after the pipeline: sync the private common to the worktree scala (the last edits: the
# phys-withdraw activation, the refusal configs), prove the three elaboration refusals, then rerun the directed
# and negative groups into *-final directories (the first rounds stay as history).
#   m2a-final.sh <runs root>
set -u; HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); M2=$(dirname "$HERE"); RUNS=${1:?runs root}; rc=0
W=/home/engineer/fpga/worktrees/mc-dual-backend/soc/scala/teaching; GC=$M2/gen/common-dual
t() { date -u +%FT%TZ; }
echo "== $(t) sync scala =="; cp $W/*.scala $W/*.cpp $GC/src/main/scala/teaching/; (cd $GC/src/main/scala/teaching && sha256sum *.scala *.cpp) | diff - <(cd $W && sha256sum *.scala *.cpp) >/dev/null && echo "private common == worktree" || { echo "SYNC FAILED"; exit 1; }
echo "== $(t) elaboration refusals (must FAIL at generation with the backend's require message) =="; mkdir -p $RUNS/refuse
for c in DualRefuseMissingConfig DualRefuseStrayConfig DualRefuseDupConfig; do
  TOPPROJ=freechips.rocketchip.unittest bash $M2/gen/gen.sh TestHarness $c $GC $RUNS/refuse/$c > $RUNS/refuse/$c.out 2>&1; g=$?
  msg=$(sed 's/\x1b\[[0-9;]*m//g' $RUNS/refuse/$c/gen.log | grep -oE "AtomicBackend: [^\"]*(must resolve to exactly one client|not bound|must be non-empty and unique)[^\"]*" | head -1 | cut -c1-150)
  if [ $g -ne 0 ] && [ -n "$msg" ]; then echo "  $c: refused -- $msg"; else echo "  $c: NOT refused as required (gen rc=$g, msg='$msg')"; rc=1; fi; done
echo "== $(t) directed (final) =="; bash $HERE/dual-all.sh $RUNS/dual-directed-final directed 2>&1 | tee $RUNS/dual-directed-final.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
echo "== $(t) neg (final) =="; bash $HERE/dual-all.sh $RUNS/dual-neg-final neg 2>&1 | tee $RUNS/dual-neg-final.log | tail -1; [ ${PIPESTATUS[0]} = 0 ] || rc=1
echo "== $(t) FINAL_DONE rc=$rc"; exit $rc
