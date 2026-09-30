#!/bin/bash
# Self-test of hart_check.py on ARCHIVED board consoles: the MC-M5 dual multicycle board m4smoke and the MC-PERF dual
# perf-board must pass; the P3b single-pipeline m4smoke and perf-board (same kernels, one hart) must fail; a dual
# console with the line removed or doubled must fail.
J=${1:-$(dirname "$0")/../hart_check.py}; bad=0; T=$(mktemp -d)
M5=/home/engineer/fpga/experiments/multicore/m5-board/sessions/session-dual-20260927T191016Z/xv6-m4smoke-20260927T192841Z/run/console.txt
PF=$(find /home/engineer/fpga/experiments/multicore/perf/sessions -name console.txt -path "*perf-board*" | sort | head -1)
P3=/home/engineer/fpga/worktrees/pipe-single/experiments/pipeline/p3/board/results/session-pipe-20260929T231052Z
sed '/^hart 1 starting/d' "$M5" > $T/removed.txt; sed 's/^hart 1 starting.*/&\nhart 1 starting/' "$M5" > $T/doubled.txt
for c in "pass:$M5" "pass:$PF" "fail:$P3/xv6-m4smoke-20260929T232528Z/run/console.txt" "fail:$P3/xv6-perf-board-20260929T233029Z/run/console.txt" "fail:$T/removed.txt" "fail:$T/doubled.txt"; do
  w=${c%%:*}; f=${c#*:}; python3 "$J" "$f" > $T/out 2>&1; rc=$?
  { [ $w = pass ] && [ $rc = 0 ]; } || { [ $w = fail ] && [ $rc = 1 ]; } && echo "ok   want $w: $(cat $T/out) [$f]" || { echo "FAIL want $w rc=$rc: $(cat $T/out) [$f]"; bad=$((bad+1)); }
done
echo "SELFTEST $([ $bad = 0 ] && echo PASS || echo "FAIL $bad")"; [ $bad = 0 ]
