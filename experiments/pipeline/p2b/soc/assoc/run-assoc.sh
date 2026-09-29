#!/usr/bin/env bash
# PIPE-P2b: directed short SoC runs on an association-checker simulator (build-assoc-sim.sh).
#   run-assoc.sh <sim> <fresh outdir> [programs]       programs: all (default) or a space-separated label list
# Programs: the accepted SoC programs (cpu-a-closeout/soc-run6/prog, m1/runs/closeout2-elf), P2b's S-mode Sv39
# programs (p2b/runs/run-4/elf: p2b_walk_preempt, hzsv1-3), P1's p1_store_trap and p2b_assoc_trap (compiled here), five R-BOOT
# restarts during boot12's atomic phase. Per run: the simulator exit, the program's HTIF exit code, and the checker's
# ASSOC END line (missing = failure). Summary: assoc.txt; exit 0 only if every run is as expected.
set -u
SIM=${1:?sim}; OUT=${2:?outdir}; ONLY=${3:-all}
[ -x "$SIM" ] || { echo "REFUSE: no simulator $SIM"; exit 2; }; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p $OUT/elf $OUT/logs
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
P=/home/engineer/fpga/worktrees/pipe-single/experiments/pipeline; TC=/home/engineer/fpga/experiments/teaching-cpu
S6=$TC/cpu-a-closeout/soc-run6/prog; C2=/home/engineer/fpga/experiments/multicore/m1/runs/closeout2-elf/elf; R4=$P/p2b/runs/run-4/elf
PREP=$TC/m2-prep/tests
cp $S6/boot09_muldiv_atomic.elf $S6/boot10_rvc_atomic.elf $S6/boot11_sv39.elf $S6/boot12_amo.elf $S6/hello.riscv $OUT/elf/
cp $C2/boot04_badaddr.elf $C2/tlb01_sfence.elf $C2/tlb02_canonical.elf $C2/ext04_sv39.elf $OUT/elf/
cp $R4/p2b_walk_preempt.elf $R4/hzsv1.elf $R4/hzsv2.elf $R4/hzsv3.elf $OUT/elf/
riscv64-unknown-elf-gcc -march=rv64i_zicsr_zifencei -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 \
  -Wa,--fatal-warnings -I$PREP -I$P/p1/tests -T $PREP/link.ld -o $OUT/elf/p1_store_trap.elf $P/p1/tests/p1crt.S \
  $P/p1/tests/p1_store_trap.S > $OUT/elf/p1_store_trap.cc.log 2>&1 || { echo "CC FAIL p1_store_trap"; exit 3; }
riscv64-unknown-elf-gcc -march=rv64i_zicsr_zifencei -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 \
  -Wa,--fatal-warnings -I$PREP -I$P/p1/tests -T $PREP/link.ld -o $OUT/elf/p2b_assoc_trap.elf $P/p1/tests/p1crt.S \
  $P/p2b/soc/assoc/p2b_assoc_trap.S > $OUT/elf/p2b_assoc_trap.cc.log 2>&1 || { echo "CC FAIL p2b_assoc_trap"; exit 3; }
(cd $OUT/elf && sha256sum *.elf *.riscv) > $OUT/elf.sha256
# label elf max-cycles [plusargs]
PROGS="boot09:boot09_muldiv_atomic.elf boot10:boot10_rvc_atomic.elf boot11:boot11_sv39.elf boot12:boot12_amo.elf hello:hello.riscv
boot04:boot04_badaddr.elf tlb01:tlb01_sfence.elf tlb02:tlb02_canonical.elf ext04:ext04_sv39.elf walk_preempt:p2b_walk_preempt.elf
hzsv1:hzsv1.elf hzsv2:hzsv2.elf hzsv3:hzsv3.elf store_trap:p1_store_trap.elf assoc_trap:p2b_assoc_trap.elf
drain42751:boot12_amo.elf drain43119:boot12_amo.elf drain43488:boot12_amo.elf drain43856:boot12_amo.elf drain45000:boot12_amo.elf"
bad=0
for pe in $PROGS; do l=${pe%%:*}; e=${pe#*:}
  [ "$ONLY" = all ] || echo " $ONLY " | grep -q " $l " || continue
  extra=(); case $l in drain*) extra=(+rboot=1 +rd2_restart_at=${l#drain} +rd2_restart_rounds=1);; esac
  timeout 1800 $SIM +max-cycles=12000000 "${extra[@]}" $OUT/elf/$e > $OUT/logs/$l.log 2>&1; ec=$?
  code=$(grep -m1 -oE "HOSTDONE exit_code=[0-9-]+" $OUT/logs/$l.log | cut -d= -f2)
  endl=$(grep -m1 "^ASSOC END" $OUT/logs/$l.log); nf=$(echo "$endl" | sed -n 's/.*fails=\([0-9]*\).*/\1/p')
  first=$(grep -m1 "^ASSOC FAIL" $OUT/logs/$l.log | cut -c1-200)
  st=ok; { [ $ec = 0 ] && [ "$code" = 0 ] && [ "$nf" = 0 ]; } || { st=FAIL; bad=1; }
  dr=""
  case $l in drain*)   # the bus side of the drain: every Get matched by its Put, the restart asserted (accepted judge)
    python3 $TC/cpu-a/scripts/check-drain.py $OUT/logs/$l.log $ec > $OUT/logs/$l.drain 2>&1; dc=$?
    dr=" | check-drain=$dc $(grep -m1 '^DRAIN' $OUT/logs/$l.drain | cut -c1-110)"; [ $dc = 0 ] || { st=FAIL; bad=1; };;
  esac
  printf "  %-13s sim=%s htif=%s %s  %s%s\n" $l $ec "${code:-none}" "${endl:-NO ASSOC END}" "$st${first:+ first: $first}" "$dr" | tee -a $OUT/assoc.txt
done
# coverage summed over the runs (max_* is the maximum)
cat $OUT/logs/*.log | grep "^ASSOC COVER" | tr ' ' '\n' | grep -E "^[a-z_]+=[0-9]+$" | awk -F= '{ if ($1 ~ /^max_/) { if ($2 > t[$1]) t[$1] = $2 } else t[$1] += $2 } END{for (k in t) printf "%s=%d\n", k, t[k]}' | sort > $OUT/cover.txt
echo "  coverage (summed): $(tr '\n' ' ' < $OUT/cover.txt)" | tee -a $OUT/assoc.txt
echo "ASSOC_RUN_DONE bad=$bad" | tee -a $OUT/assoc.txt; exit $bad
