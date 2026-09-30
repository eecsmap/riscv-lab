#!/bin/bash
# PIPE-P4a: every dual-suite group into its own fresh directory, with an unambiguous status per group and overall
# (the earlier `a; b; c; d` launcher exited with the LAST group's status only). RUN_GROUP overrides the group runner.
#   run-dual-all.sh <sims dir> <fresh outroot>
set -u
S=$(cd "$(dirname "$0")" && pwd); SIMS=${1:?sims}; OUT=${2:?outroot}; RUN_GROUP=${RUN_GROUP:-$S/run-dual-suite.sh}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT; bad=0; summary=""
for g in traced neg integ fast; do bash $RUN_GROUP $SIMS $OUT/suite-$g $g > $OUT/suite-$g.log 2>&1; r=$?
  summary="$summary $g=$r"; echo "  group $g: exit $r -- $(tail -n 1 $OUT/suite-$g.log | cut -c1-120)"; [ $r = 0 ] || bad=1; done
echo "P4A_DUAL_ALL_DONE groups:$summary bad=$bad"; exit $bad
