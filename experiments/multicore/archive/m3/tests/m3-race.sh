#!/usr/bin/env bash
# the controlled HTIF input race: fixed kernel (consumed must be 1) and the negative build (every hart polls;
# consumed must be 2 and both harts must have read the word, proving the window was real)
set -u; M3=/home/engineer/fpga/experiments/multicore/m3; T=$M3/tests; R=$M3/runs; O=$M3/sw/out; SIM=$R/sim-dual/obj_dir/sim; bad=0
for k in racepos raceneg; do rm -rf $R/race-$k; echo "== $(date -u +%FT%TZ) race test: $k =="; bash $T/run-xv6.sh $SIM $O/kernel-$k $O/fs-prod.img m3boot $R/race-$k 200000000 900 150 2>&1 | tail -1
  line=$(grep -E "HTIF-RACE-TEST" $R/race-$k/run/console.txt | head -1); echo "  $line"
  case $k in racepos) grep -q "readers=1 consumed=1 expected=1 OK" <<<"$line" || { echo "  FAIL: fixed kernel must show readers=1 consumed=1"; bad=$((bad+1)); };;
              raceneg) grep -q "readers=2 consumed=2 expected=1 FAIL" <<<"$line" || { echo "  FAIL: the negative build must show both harts reading and consuming (readers=2 consumed=2)"; bad=$((bad+1)); };; esac; done
echo "RACE_DONE bad=$bad"
