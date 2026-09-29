#!/bin/bash
# PIPE-P2b checkpoint 5, SoC-level: the pipeline behind the hart wrapper on the TRACED RD2 configuration
# (RD2PipeBootConfig, gen-3), judged by the accepted SoC checkers, unchanged:
#   S1  the CPU-A SoC programs as cpu-a/scripts/run-soc-a.sh runs them on the atomic configuration (same ELFs:
#       cpu-a-closeout/soc-run6/prog; check-m3.py boot + check-axi.py; boot12 also check-boot12.py): boot09 muldiv,
#       boot10 rvc, boot11 S-mode Sv39, boot12 S-mode Sv39 spinlock / LR/SC / AMOs, hello
#   S2  the R-BOOT gates (restart-boot/scripts/rboot-run.sh: restarts with read / write DMA in flight, three
#       rounds, stuck device, late recovery); gate lines compared with the multicycle's (m1/runs/rboot-after.log)
#   S3  a restart during boot12's atomic phase (check-drain.py): the accepted points 45000..60000 (those before the
#       program's end) and four points inside the PIPELINE's atomic phase (read from its own S1 run); at least one must
#       land with an atomic in flight
#   chain-cp5c.sh <gen dir> <fresh outdir>
set -u
W=/home/engineer/fpga/worktrees/pipe-single; P=$W/experiments/pipeline/p2b; TC=/home/engineer/fpga/experiments/teaching-cpu
CK=/home/engineer/fpga/teaching-cpu-work/cpu; A=$TC/cpu-a; PROG=$TC/cpu-a-closeout/soc-run6/prog
GEN=${1:?gen dir}; OUT=${2:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT/logs
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
bash $P/soc/build-rd2-pipe-sim.sh $GEN/after-RD2PipeBootConfig/RD2Harness.RD2PipeBootConfig.v $W/rtl/cpu $OUT/sim-boot || { echo "BUILD FAIL"; exit 1; }
SIM=$OUT/sim-boot/obj_dir/sim; (cd $PROG && sha256sum *.elf *.riscv) > $OUT/prog.sha256
fails=0; infra=0
runp() {  # runp <elf> <label> <marker> <extra check args>   (run-soc-a.sh's runp)
  local elf=$1 label=$2 marker=$3 extra=$4
  timeout 1200 $SIM +max-cycles=4000000 $elf > $OUT/logs/$label.log 2>&1; local ec=$?; echo $ec > $OUT/logs/$label.exit
  if [ $ec -eq 124 ]; then printf "  %-22s INFRA timed out\n" $label; infra=$((infra+1)); return; fi
  python3 $CK/check-m3.py $OUT/logs/$label.log boot --exit=0 --assert-free --host-ok $marker $extra \
    --axi-min-reads=1 --axi-min-writes=1 > $OUT/logs/$label.check 2>&1; local c=$?
  python3 $CK/check-axi.py $OUT/logs/$label.log > $OUT/logs/$label.axi 2>&1; local a=$?
  local pa=$(grep -c "^PIPE ASSERT" $OUT/logs/$label.log)
  printf "  %-22s sim=%s check-m3=%s check-axi=%s pipe-asserts=%s  %s\n" $label $ec $c $a $pa "$(grep -oE 'HOSTDONE exit_code=[0-9-]+' $OUT/logs/$label.log | head -1)"
  grep -E "FAIL" $OUT/logs/$label.check | head -2 | sed 's/^/      /'
  [ $ec = 0 ] && [ $c = 0 ] && [ $a = 0 ] && [ $pa = 0 ] || fails=$((fails+1)); }
echo "== S1: the CPU-A SoC programs on the pipeline (RD2PipeBootConfig)"
runp $PROG/boot09_muldiv_atomic.elf boot09 "--marker=M3-MULDIV-OK" "--irqs=1 --sync-traps=0"
runp $PROG/boot10_rvc_atomic.elf    boot10 "--marker=M3-RVC-OK"    "--irqs=1 --sync-traps=0"
runp $PROG/boot11_sv39.elf          boot11 "--marker=M3-SV39-OK"   "--irqs=1 --sync-traps=2"
runp $PROG/hello.riscv              hello  "--marker=PASS"         "--irqs=1 --sync-traps=0"
runp $PROG/boot12_amo.elf           boot12 "--marker=M3-AMO-OK"    "--irqs=1 --sync-traps=1"
python3 $A/scripts/check-boot12.py $OUT/logs/boot12.log > $OUT/logs/boot12.score 2>&1; c=$?
printf "  %-22s score=%s  %s\n" "boot12-events" $c "$(head -1 $OUT/logs/boot12.score | cut -c1-110)"; [ $c = 0 ] || fails=$((fails+1))
echo "== S2: the R-BOOT gates on the pipeline"
MAXCYC=300000 WALL=900 bash $TC/restart-boot/scripts/rboot-run.sh $SIM $OUT/rboot > $OUT/logs/rboot.log 2>&1; rb=$?
grep -E "^  g[0-9]|DONE" $OUT/logs/rboot.log | sed 's/^/  /'; [ $rb = 0 ] || fails=$((fails+1))
diff <(grep -E "^\s+g[0-9]" /home/engineer/fpga/experiments/multicore/m1/runs/rboot-after.log) <(grep -E "^\s+g[0-9]" $OUT/logs/rboot.log) > $OUT/rboot-diff.txt \
  && echo "  gate lines identical to the multicycle's (m1/runs/rboot-after.log)" || { echo "  gate lines DIFFER from the multicycle's"; fails=$((fails+1)); }
echo "== S3: a restart during boot12's atomic phase"
read a0 a1 < <(awk '/^AT +[0-9]+ CPU_REQ/ && (/amo= *[1-9]/ || /lrsc=[12]/) {c=$2; if (!f) f=c; l=c} END{print f+0, l+0}' $OUT/logs/boot12.log)
echo "  the pipeline's atomic phase in S1: cycles $a0..$a1"
pts="45000 50000 55000 60000"; [ $a1 -gt $a0 ] && pts="$pts $((a0 + (a1-a0)/5)) $((a0 + 2*(a1-a0)/5)) $((a0 + 3*(a1-a0)/5)) $((a0 + 4*(a1-a0)/5))"
# a point after the program's own end (its HOSTDONE in S1) cannot restart anything -- the accepted points were chosen for
# the multicycle core's timing; the pipeline may finish boot12 before them. Such a point is reported, not run.
hd=$(grep -m1 -oE "^EVH +[0-9]+ HOSTDONE " $OUT/logs/boot12.log | awk '{print $2}'); echo "  boot12 ends (HOSTDONE) at cycle ${hd:-?} in S1"
inflight=0
for at in $pts; do
  if [ -n "$hd" ] && [ $at -ge $hd ]; then printf "  %-22s not applicable: after the program's end at cycle %s\n" "drain-$at" $hd; continue; fi
  timeout 1800 $SIM +max-cycles=8000000 +rboot=1 +rd2_restart_at=$at +rd2_restart_rounds=1 $PROG/boot12_amo.elf > $OUT/logs/drain-$at.log 2>&1
  ec=$?; echo $ec > $OUT/logs/drain-$at.exit
  if [ $ec -eq 124 ]; then printf "  %-22s INFRA timed out\n" "drain-$at"; infra=$((infra+1)); continue; fi
  python3 $A/scripts/check-drain.py $OUT/logs/drain-$at.log $ec > $OUT/logs/drain-$at.score 2>&1; c=$?
  grep -q "atomic in flight at the reset" $OUT/logs/drain-$at.score && inflight=$((inflight+1))
  pa=$(grep -c "^PIPE ASSERT" $OUT/logs/drain-$at.log)
  printf "  %-22s sim=%s score=%s pipe-asserts=%s  %s\n" "drain-$at" $ec $c $pa "$(grep -m1 '^DRAIN' $OUT/logs/drain-$at.score | cut -c1-120)"
  [ $c = 0 ] && [ $pa = 0 ] || { fails=$((fails+1)); grep FAIL $OUT/logs/drain-$at.score | head -2 | sed 's/^/      /'; }
done
[ $inflight -ge 1 ] && echo "  $inflight restart(s) landed with an atomic in flight" || { echo "  no restart landed with an atomic in flight"; fails=$((fails+1)); }
echo "SOC_PIPE_DONE infra=$infra fails=$fails"
[ $infra = 0 ] && [ $fails = 0 ]
