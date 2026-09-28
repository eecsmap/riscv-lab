#!/usr/bin/env bash
# MC-M2b dual-hart suite (after smoke2): everything that needs the FAST simulator plus the drain scenario and
# the tracing cross-check of dual03. Budgets are arguments to run-dual.sh; a timeout is a failure, never a retry.
#   m2b-suite.sh <outroot> [group]    group: seeds | long | drain | trace03 | neg | all
set -u; M2B=/home/engineer/fpga/experiments/multicore/m2b; T=$M2B/tests; R=$M2B/runs; P=$M2B/progs/build
FAST=$R/sim-dual-fast/obj_dir/sim; BOOT=$R/sim-dual-boot/obj_dir/sim; OUT=$(readlink -f -m "${1:?outroot}"); G=${2:-all}; mkdir -p $OUT
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
bad=0; n=0
judge() { local d=$1 prog=$2; shift 2; n=$((n+1)); python3 $T/dual_check.py $d --prog $prog "$@" > $d.check 2>&1; local rc=$?
  printf "  %-26s %s | %s\n" "$(basename $d)" "$(cat $d/verdict.txt 2>/dev/null | cut -c1-90)" "$(grep -E '^(PASS|FAIL)' $d.check | cut -c1-60)"; grep -E "^  FAIL|^INFO" $d.check | head -4 | cut -c1-170 | sed 's/^/      /'
  [ $rc = 0 ] || bad=$((bad+1)); }
if [ $G = seeds ] || [ $G = all ]; then echo "== dual03 lock/LR-SC/AMO/publish/errors: 10 timing variants on the FAST simulator (throttle plusargs perturb the interleaving) =="
  # seed s: a-delay and d-delay on every hart's master path (the RD2Throttle inside each hart), from transaction s*7
  for s in 1 2 3 4 5 6 7 8 9 10; do ad=$(( (s * 3) % 5 )); dd=$(( (s * 5) % 4 )); from=$(( s * 7 ))
    bash $T/run-dual.sh $FAST $P/dual03_lock.elf $OUT/dual03-s$s 60000000 1800 +rd2_a_delay=$ad +rd2_d_delay=$dd +rd2_throttle_from=$from > /dev/null 2>&1
    judge $OUT/dual03-s$s dual03_lock --fast; done
fi
if [ $G = long ] || [ $G = all ]; then echo "== dual07 long-run progress (>= 1M retired per hart) on the FAST simulator =="
  bash $T/run-dual.sh $FAST $P/dual07_long.elf $OUT/dual07-long 200000000 5400 +rd2_progress=5000000 > /dev/null 2>&1
  judge $OUT/dual07-long dual07_long --fast --min-retired 1000000
fi
if [ $G = drain ] || [ $G = all ]; then echo "== dual06: an injected soft reset while BOTH harts have a transaction in flight, host reload, second boot (tracing simulator) =="
  bash $T/run-dual.sh $BOOT $P/dual06_drain.elf $OUT/dual06-drain 4000000 900 +rd2_reset_at=46000 +rd2_reset_when=10 +rd2_reset_len=0 +rd2_reload_after_inject=1 > /dev/null 2>&1
  judge $OUT/dual06-drain dual06_drain --drain
fi
if [ $G = trace03 ] || [ $G = all ]; then echo "== dual03 once on the TRACING simulator: backend AT trace cross-checks the counts (SC_OK / AMO_START per hart) =="
  bash $T/run-dual.sh $BOOT $P/dual03_lock.elf $OUT/dual03-trace 60000000 3600 > /dev/null 2>&1
  judge $OUT/dual03-trace dual03_lock --atomic-floor 20000
fi
if [ $G = neg ] || [ $G = all ]; then echo "== injected-defect programs: the checker must REJECT each (a timeout is a rejection, not a pass) =="
  for p in neg01_nohart1:dual01_boot:400000:120:boot neg02_wronghart:dual01_boot:400000:120:boot neg03_wrongcount:dual03_lock:60000000:1800:fast neg04_early:dual07_long:200000000:3600:fast; do
    IFS=: read nm prog cyc wall which <<<"$p"; sim=$BOOT; fl=""; [ $which = fast ] && { sim=$FAST; fl="--fast"; }
    bash $T/run-dual.sh $sim $P/$nm.elf $OUT/$nm $cyc $wall > /dev/null 2>&1
    n=$((n+1)); mr=1; [ $prog = dual07_long ] && mr=1000000
    if python3 $T/dual_check.py $OUT/$nm --prog $prog $fl --min-retired $mr --elf $P/$prog.elf > $OUT/$nm.check 2>&1; then printf "  %-26s ACCEPTED (must be rejected)\n" $nm; bad=$((bad+1))
    else printf "  %-26s rejected: %s\n" $nm "$(grep -m1 '^  FAIL' $OUT/$nm.check | cut -c3-150)"; fi; done
fi
echo "M2B_SUITE_DONE group=$G runs=$n bad=$bad"; [ $bad = 0 ]
