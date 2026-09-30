#!/usr/bin/env bash
# PIPE-P4a (copy of p2b/soc/run-xv6-p2b.sh with the TWO-hart judgements: m3_check.py without --n1 -- both harts
# must reach the scheduler and commit user-mode instructions, hart 1 at least --min-user1 = 100000).
# Originally: PIPE-P2b checkpoint 5: single-core xv6 in the RD2 simulator, through the accepted runners, with named inputs.
#   run-xv6-p2b.sh <case> <sim binary> <fresh outdir>
# cases (kernel / disk are fixed per case and checked by hash; the runners copy the disk fresh for every run):
#   m4smoke    multicore/m4/tests/run-xv6.sh, workload m4smoke (b0compute, m3par2, m3fs), kernel-deploy-4 1e4749c0...,
#              fs-deploy.img d8e50269...; judge: m4/tests/m3_check.py --n1
#   perf-short multicore/perf/tests/run-xv6.sh, workload perf-short (mtimetest, perfcompute 20000, perfarray 1),
#              measurement kernel d713744a..., fs-perf.img d558e444...; judges: m3_check.py --n1 (the unchanged M4 copy,
#              against the perf profile table: perfjudge/) and perf/tests/perf_check.py
# Exit 0 only if the runner exited 0 and every judge passed; a timeout, a missing input or a wrong hash fails.
set -u
MC=/home/engineer/fpga/experiments/multicore; HERE=$(cd "$(dirname "$0")" && pwd)
CASE=${1:?case}; SIM=${2:?sim}; OUT=${3:?outdir}
case $CASE in
  m4smoke)    RUNNER=$MC/m4/tests/run-xv6.sh;   K=$MC/m4/sw/out/kernel-deploy-4;   D=$MC/m4/sw/out/fs-deploy.img; KH=1e4749c0f7c1e7ee; DH=d8e502693bba1b14;;
  perf-short) RUNNER=$MC/perf/tests/run-xv6.sh; K=$MC/perf/sw/out/kernel-deploy-4; D=$MC/perf/sw/out/fs-perf.img;  KH=d713744a5e478764; DH=d558e4444abcea60;;
  *) echo "REFUSE: unknown case $CASE"; exit 2;;
esac
[ -x "$SIM" ] || { echo "REFUSE: no simulator $SIM"; exit 2; }
[ "$(sha256sum $K | cut -c1-16)" = $KH ] || { echo "REFUSE: $K is not kernel $KH"; exit 2; }
[ "$(sha256sum $D | cut -c1-16)" = $DH ] || { echo "REFUSE: $D is not disk $DH"; exit 2; }
bash $RUNNER "$SIM" $K $D $CASE "$OUT" 2000000000 ${XV6_WALL:-7200} ${XV6_STAGE:-3600}; rc=$?
fails=0
[ $rc = 0 ] || { echo "XV6 runner rc=$rc"; fails=$((fails+1)); }
# the run used exactly these inputs (the runner records them)
grep -q "kernel=$K ($KH" "$OUT/cmd.txt" && grep -q "disk=$D ($DH" "$OUT/cmd.txt" && grep -q "sim=$SIM ($(sha256sum $SIM | cut -c1-16))" "$OUT/cmd.txt" \
  || { echo "XV6 the run's recorded inputs are not the named ones"; fails=$((fails+1)); }
if [ $CASE = m4smoke ]; then
  python3 $MC/m4/tests/m3_check.py "$OUT" > "$OUT/check.txt" 2>&1 || fails=$((fails+1))
else
  python3 $HERE/../../p2b/soc/perfjudge/tests/m3_check.py "$OUT" > "$OUT/check.txt" 2>&1 || fails=$((fails+1))
  python3 $MC/perf/tests/perf_check.py "$OUT" --min-dmtime 1 --sizes compute=20000,array=1 > "$OUT/perf-check.txt" 2>&1 || fails=$((fails+1))
  tail -1 "$OUT/perf-check.txt"
fi
tail -1 "$OUT/check.txt"
grep -hE "^(HARTS|HARTS_USER|CYCLES)" "$OUT/run/console.txt" 2>/dev/null
echo "XV6_P2B_DONE case=$CASE rc=$rc fails=$fails"
[ $fails = 0 ]
