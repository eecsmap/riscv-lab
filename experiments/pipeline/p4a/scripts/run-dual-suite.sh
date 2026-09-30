#!/usr/bin/env bash
# PIPE-P4a: the accepted MC-M2b dual-hart suite on the two-pipeline simulators, plus the pipeline integration cases.
# The M2b runner (run-dual.sh), programs (progs/build) and judge (dual_check.py) are used unchanged.
#   run-dual-suite.sh <sims dir> <fresh outdir> [group]     group: traced | fast | neg | integ | all
# traced  sim-boot-assoc (the traced two-pipeline SoC with an association checker per hart): dual01 boot, dual02
#         CLINT/interrupts, dual04 pbus/PLIC, dual05 fence.i, dual03 lock/LR-SC/AMO with the backend trace, dual06 an
#         injected soft reset while BOTH harts have a transaction in flight + reload, dual08 hart-1 store-under-ECALL;
#         every run: dual_check PASS (dual08: its own marker) AND `ASSOC H0 END fails=0` AND `ASSOC H1 END fails=0`
# fast    sim-fast: dual03 under 10 throttle timings, dual07 long run (>= 1M retired per hart)
# neg     the M2b injected-defect programs on sim-fast/sim-boot-assoc: each must be REJECTED by dual_check
# integ   integration negatives: HART_ID swapped between the two harts (dual01, dual02 must be rejected); the core's
#         knob 4 on hart 1 only (dual08: the first association failure must be hart 1's, hart 0 must stay clean)
set -u
M2B=/home/engineer/fpga/experiments/multicore/m2b; T=$M2B/tests; P=$M2B/progs/build; HERE=$(cd "$(dirname "$0")" && pwd)
SIMS=$(readlink -f ${1:?sims}); OUT=$(readlink -f -m ${2:?outdir}); G=${3:-all}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT
FAST=$SIMS/sim-fast/obj_dir/sim; BOOT=$SIMS/sim-boot-assoc/obj_dir/sim
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
bash $HERE/../progs/build.sh $OUT/p4a-progs > /dev/null || { echo "P4A PROGS BUILD FAIL"; exit 3; }
(cd $P && sha256sum *.elf) > $OUT/m2b-elf.sha256
bad=0; n=0
assoc() {  # assoc <run dir>: both harts' association checkers ended clean
  local d=$1 h ok=1; for h in 0 1; do grep -qE "^ASSOC H$h END cycles=[0-9]+ fails=0$" $d/console.txt || ok=0; done
  [ $ok = 1 ] && echo "assoc H0/H1 clean" || { echo "ASSOC NOT CLEAN: $(grep -m2 -E '^ASSOC H[01] (FAIL|END)' $d/console.txt | tr '\n' ' ' | cut -c1-160)"; return 1; }; }
judge() { local d=$1 prog=$2; shift 2; n=$((n+1)); python3 $T/dual_check.py $d --prog $prog "$@" > $d.check 2>&1; local rc=$?
  local a="-"; if [ "$W_ASSOC" = 1 ]; then a=$(assoc $d) || rc=1; fi
  printf "  %-24s %s | %s | %s\n" "$(basename $d)" "$(cut -c1-60 $d/verdict.txt 2>/dev/null)" "$(grep -E '^(PASS|FAIL)' $d.check | cut -c1-40)" "$a"
  grep -E "^  FAIL" $d.check | head -3 | cut -c1-170 | sed 's/^/      /'; [ $rc = 0 ] || bad=$((bad+1)); }
if [ $G = traced ] || [ $G = all ]; then W_ASSOC=1; echo "== traced two-pipeline SoC, association checker on each hart =="
  for p in dual01_boot:400000:120 dual02_clint:8000000:900 dual04_pbus:3000000:600 dual05_fencei:400000:120; do IFS=: read nm cyc wall <<<"$p"
    bash $T/run-dual.sh $BOOT $P/$nm.elf $OUT/$nm $cyc $wall > /dev/null 2>&1; judge $OUT/$nm $nm --elf $P/$nm.elf; done
  bash $T/run-dual.sh $BOOT $P/dual03_lock.elf $OUT/dual03-trace 60000000 3600 > /dev/null 2>&1; judge $OUT/dual03-trace dual03_lock --atomic-floor 20000
  bash $T/run-dual.sh $BOOT $P/dual06_drain.elf $OUT/dual06-drain 4000000 900 +rd2_reset_at=46000 +rd2_reset_when=10 +rd2_reset_len=0 +rd2_reload_after_inject=1 > /dev/null 2>&1
  judge $OUT/dual06-drain dual06_drain --drain
  bash $T/run-dual.sh $BOOT $OUT/p4a-progs/dual08_h1trap.elf $OUT/dual08 400000 300 > /dev/null 2>&1; n=$((n+1))
  e=$(cat $OUT/dual08/exit); m=$(grep -c "P4A-DUAL08-OK" $OUT/dual08/console-clean.txt 2>/dev/null); a=$(assoc $OUT/dual08); ar=$?
  printf "  %-24s exit=%s marker=%s | %s\n" dual08 "$e" "$m" "$a"; { [ "$e" = 0 ] && [ "${m:-0}" -ge 1 ] && [ $ar = 0 ]; } || bad=$((bad+1)); fi
if [ $G = fast ] || [ $G = all ]; then W_ASSOC=0; echo "== fast two-pipeline SoC =="
  for s in 1 2 3 4 5 6 7 8 9 10; do ad=$(( (s * 3) % 5 )); dd=$(( (s * 5) % 4 )); from=$(( s * 7 ))
    bash $T/run-dual.sh $FAST $P/dual03_lock.elf $OUT/dual03-s$s 60000000 1800 +rd2_a_delay=$ad +rd2_d_delay=$dd +rd2_throttle_from=$from > /dev/null 2>&1
    judge $OUT/dual03-s$s dual03_lock --fast; done
  bash $T/run-dual.sh $FAST $P/dual07_long.elf $OUT/dual07-long 200000000 5400 +rd2_progress=5000000 > /dev/null 2>&1
  judge $OUT/dual07-long dual07_long --fast --min-retired 1000000; fi
if [ $G = neg ] || [ $G = all ]; then echo "== M2b injected-defect programs: each must be REJECTED =="
  for p in neg01_nohart1:dual01_boot:400000:120:boot neg02_wronghart:dual01_boot:400000:120:boot neg03_wrongcount:dual03_lock:60000000:1800:fast neg04_early:dual07_long:200000000:3600:fast; do
    IFS=: read nm prog cyc wall which <<<"$p"; sim=$BOOT; fl=""; [ $which = fast ] && { sim=$FAST; fl="--fast"; }
    bash $T/run-dual.sh $sim $P/$nm.elf $OUT/$nm $cyc $wall > /dev/null 2>&1; n=$((n+1)); mr=1; [ $prog = dual07_long ] && mr=1000000
    if python3 $T/dual_check.py $OUT/$nm --prog $prog $fl --min-retired $mr --elf $P/$prog.elf > $OUT/$nm.check 2>&1; then printf "  %-24s ACCEPTED (must be rejected)\n" $nm; bad=$((bad+1))
    else printf "  %-24s rejected: %s\n" $nm "$(grep -m1 '^  FAIL' $OUT/$nm.check | cut -c3-140)"; fi; done; fi
if [ $G = integ ] || [ $G = all ]; then echo "== integration negatives =="
  for nm in dual01_boot dual02_clint; do cyc=400000; wall=120; [ $nm = dual02_clint ] && { cyc=8000000; wall=900; }
    bash $T/run-dual.sh $SIMS/sim-neg-hartid-swap/obj_dir/sim $P/$nm.elf $OUT/neg-hartid-$nm $cyc $wall > /dev/null 2>&1; n=$((n+1))
    if python3 $T/dual_check.py $OUT/neg-hartid-$nm --prog $nm --elf $P/$nm.elf > $OUT/neg-hartid-$nm.check 2>&1; then printf "  %-24s ACCEPTED (must be rejected)\n" neg-hartid-$nm; bad=$((bad+1))
    else printf "  %-24s rejected: %s\n" neg-hartid-$nm "$(grep -m1 '^  FAIL' $OUT/neg-hartid-$nm.check | cut -c3-140)"; fi; done
  bash $T/run-dual.sh $SIMS/sim-neg-pf4-h1/obj_dir/sim $OUT/p4a-progs/dual08_h1trap.elf $OUT/neg-pf4-h1-dual08 400000 300 > /dev/null 2>&1; n=$((n+1))
  f=$(grep -m1 -E '^ASSOC H[01] FAIL' $OUT/neg-pf4-h1-dual08/console.txt); h0=$(grep -c '^ASSOC H0 FAIL' $OUT/neg-pf4-h1-dual08/console.txt)
  if echo "$f" | grep -q '^ASSOC H1 FAIL association' && [ "$h0" = 0 ]; then printf "  %-24s caught on hart 1 only: %s\n" neg-pf4-h1-dual08 "$(echo $f | cut -c1-140)"
  else printf "  %-24s NOT as intended: first '%s', hart-0 failures %s\n" neg-pf4-h1-dual08 "$(echo $f | cut -c1-120)" "$h0"; bad=$((bad+1)); fi; fi
echo "P4A_DUAL_SUITE_DONE group=$G runs=$n bad=$bad"; [ $bad = 0 ]
