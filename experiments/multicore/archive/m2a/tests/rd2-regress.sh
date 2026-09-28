#!/usr/bin/env bash
# MC-M2a single-core RD2 regression: the SAME judge chain as the accepted M1 closeout (rd2-probes.sh ->
# probe_console.py, compare-probes.py, the frozen ELF set runs/closeout2-elf, rboot-run.sh), with the ONLY
# intended difference being the generated Verilog from the mc-dual-backend scala (multi-hart backend, one
# hart bound). The BEFORE side is M1's accepted closeout2-after-* run; the AFTER side is generated here.
#   rd2-regress.sh <outroot> <step>    step: gen | probes | compare | rboot | all
set -uo pipefail
R=/home/engineer/fpga; M1=$R/experiments/multicore/m1; HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); M2=$(dirname "$HERE"); GC=$M2/gen/common-dual
RTL=$R/worktrees/mc-dual-backend/rtl/cpu; OUT=$(readlink -f -m "${1:?outroot}"); STEP=${2:-all}; mkdir -p "$OUT"
ELF=$M1/runs/closeout2-elf; ONLY="boot01_marker boot02_clint boot03_ddr boot04_badaddr boot11_sv39 boot12_amo cache01_smc ext01_m ext02_c ext04_sv39 hello tlb01_sfence tlb02_canonical"
cd $R; rc=0
if [ $STEP = gen ] || [ $STEP = all ]; then
  for c in RD2AtomicXv6FastConfig RD2AtomicBootConfig; do [ -e $OUT/gen-$c ] && { echo "skip gen-$c (exists)"; continue; }
    TOPPROJ=teaching bash $M2/gen/gen.sh RD2Harness $c $GC $OUT/gen-$c | tail -1; done
fi
if [ $STEP = probes ] || [ $STEP = all ]; then
  ELFDIR=$ELF ONLY="$ONLY" bash $M2/tests/rd2-probes.sh $OUT/gen-RD2AtomicXv6FastConfig/RD2Harness.RD2AtomicXv6FastConfig.v $RTL m2a $OUT/probes-fast > $OUT/probes-fast.log 2>&1; echo "probes-fast rc=$? $(tail -1 $OUT/probes-fast.log | cut -c1-120)"
  ELFDIR=$ELF ONLY="$ONLY" bash $M2/tests/rd2-probes.sh $OUT/gen-RD2AtomicBootConfig/RD2Harness.RD2AtomicBootConfig.v $RTL m2a $OUT/probes-trace trace > $OUT/probes-trace.log 2>&1; echo "probes-trace rc=$? $(tail -1 $OUT/probes-trace.log | cut -c1-120)"
fi
if [ $STEP = compare ] || [ $STEP = all ]; then
  set +u; source $R/experiments/chipyard-env.sh >/dev/null; set -u
  python3 $M2/tests/compare-probes.py $M1/runs/closeout2-after-fast  $OUT/probes-fast  --expect short         > $OUT/compare-fast.txt 2>&1;  r1=$?; echo "compare-fast  rc=$r1 $(tail -1 $OUT/compare-fast.txt | cut -c1-140)"
  python3 $M2/tests/compare-probes.py $M1/runs/closeout2-after-trace $OUT/probes-trace --expect short --trace > $OUT/compare-trace.txt 2>&1; r2=$?; echo "compare-trace rc=$r2 $(tail -1 $OUT/compare-trace.txt | cut -c1-140)"
  [ $r1 = 0 ] && [ $r2 = 0 ] || rc=1
fi
if [ $STEP = rboot ] || [ $STEP = all ]; then
  MAXCYC=300000 WALL=900 bash $R/experiments/teaching-cpu/restart-boot/scripts/rboot-run.sh $OUT/probes-trace/sim/obj_dir/sim $OUT/rboot > $OUT/rboot.log 2>&1; r3=$?; echo "rboot rc=$r3 $(tail -1 $OUT/rboot.log | cut -c1-140)"
  diff <(grep -E "^\s+g[0-9]" $M1/runs/rboot-after.log) <(grep -E "^\s+g[0-9]" $OUT/rboot.log) > $OUT/rboot-diff.txt && echo "rboot gates: identical to M1 rboot-after ($(grep -cE '^\s+g[0-9]' $OUT/rboot.log) lines)" || { echo "rboot gates DIFFER from M1 (see rboot-diff.txt)"; rc=1; }
  [ $r3 = 0 ] || rc=1
fi
echo "RD2_REGRESS step=$STEP rc=$rc"; exit $rc
