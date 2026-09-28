#!/usr/bin/env bash
# kill fix, round 1: the new d13-d17 group on the FIXED backend, then the same group on the OLD backend (reproduction)
set -u; HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); M2=$(dirname "$HERE"); RUNS=${1:?runs root}
echo "== $(date -u +%FT%TZ) kill group, fixed backend =="; bash $HERE/dual-all.sh $RUNS/kill-new kill 2>&1 | tee $RUNS/kill-new.log | tail -1
echo "== $(date -u +%FT%TZ) kill group, OLD backend (d9c4008 AtomicBackend.scala) =="; bash $HERE/kill-repro-old.sh $RUNS/kill-old 2>&1 | tee $RUNS/kill-old.log | tail -1
echo "== $(date -u +%FT%TZ) KILL_ROUND1_DONE"
