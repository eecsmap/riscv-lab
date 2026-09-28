#!/usr/bin/env bash
# judge the two race-test run directories (no re-simulation): fixed kernel readers=1 consumed=1 OK; negative
# build readers=2 consumed=2 FAIL (both harts read the planted word inside the window -> the window was real)
set -u; R=${1:-/home/engineer/fpga/experiments/multicore/m3/runs}; bad=0
for k in racepos raceneg; do line=$(grep -E "HTIF-RACE-TEST" $R/race-$k/run/console.txt | head -1 | tr -d '\r'); echo "$k: $line"
  case $k in racepos) grep -q "readers=1 consumed=1 expected=1 OK" <<<"$line" || { echo "  FAIL: fixed kernel must show readers=1 consumed=1 OK"; bad=$((bad+1)); };;
             raceneg) grep -q "readers=2 consumed=2 expected=1 FAIL" <<<"$line" || { echo "  FAIL: negative build must show readers=2 consumed=2 FAIL"; bad=$((bad+1)); };; esac
  grep -q "xv6 kernel is booting" $R/race-$k/run/console.txt || { echo "  FAIL: no kernel banner"; bad=$((bad+1)); }; done
echo "RACE_JUDGE bad=$bad"; [ $bad = 0 ]
