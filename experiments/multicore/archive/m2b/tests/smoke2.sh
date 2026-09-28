#!/usr/bin/env bash
# M2b smoke 2: the short programs on the tracing dual simulator, judged by dual_check.py
set -u; M2B=/home/engineer/fpga/experiments/multicore/m2b; T=$M2B/tests; R=$M2B/runs; SIM=$R/sim-dual-boot/obj_dir/sim; OUT=${1:-$R/smoke2}
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
mkdir -p $OUT; bad=0
for p in dual01_boot:400000:120 dual02_clint:8000000:900 dual04_pbus:3000000:600 dual05_fencei:400000:120; do
  n=${p%%:*}; rest=${p#*:}; cyc=${rest%%:*}; wall=${rest#*:}
  echo "== $(date -u +%FT%TZ) $n =="; bash $T/run-dual.sh $SIM $M2B/progs/build/$n.elf $OUT/$n $cyc $wall 2>&1 | tail -1
  python3 $T/dual_check.py $OUT/$n --prog $n --elf $M2B/progs/build/$n.elf 2>&1 | tee $OUT/$n.check | grep -E "^(PASS|FAIL|INFO|  FAIL)" | cut -c1-200; grep -q "^PASS" $OUT/$n.check || bad=$((bad+1)); done
echo "SMOKE2_DONE bad=$bad"
