#!/bin/bash
# PIPE-P2b checkpoint 3 (A) sections; called by run-p2b.sh, runnable alone:  run-p2b-a.sh <sims dir> <outdir>
#   AA  the CPU-A directed tests on both cores (ma-* the multicycle reference with MISA_A=1, pmcsa-* the pipeline with
#       M, C, S/U, Sv39 and A), scored by the CPU-A checkers (experiments/teaching-cpu/cpu-a/scripts, unchanged):
#       a01 the 138-case AMO matrix and a02 the LR/SC reservation rules at t0/t1/t2, a02 under the external race
#       (EXT_POINT=2 writes the reservation word between the LR and the SC), a03 the A exceptions (alignment, access,
#       illegal encodings, Sv39 permission classes) at t0/t1/t2. A positive needs exit 0 AND a clean score.
#   AB  architectural differential of every AA run against the reference (p1diff --require-complete)
#   AC  an M interrupt raised at EVERY CYCLE of a block of AMOs and an LR/SC loop (p2b_irq_amo; replaces a04's
#       multicycle-state aimed injection): the test's own checks (every AMO performed exactly once, the watched words
#       written exactly 5 times), alignment of the reference; how many raises landed inside an atomic access
#   AD  the five CPU-A injections on both cores, each rejected by its own named check (ajudge.py), controls pass
set -u
SIMS=${1:?sims dir}; OUT=${2:?outdir}
W=/home/engineer/fpga/worktrees/pipe-single; SC=$W/experiments/pipeline/p1/scripts; SC2=$W/experiments/pipeline/p2b/scripts
T2=$W/experiments/pipeline/p2b/tests
CA=/home/engineer/fpga/experiments/teaching-cpu/cpu-a; CK=$CA/scripts
PREP=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests; T2H=/home/engineer/fpga/teaching-cpu-work/cpu/tests2
SUT=/home/engineer/fpga/experiments/teaching-cpu/cpu-su-prep/tests; SVT=/home/engineer/fpga/experiments/teaching-cpu/cpu-sv39/tests
mkdir -p $OUT/aelf $OUT/AA $OUT/AC $OUT/AD || exit 3
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
S() { echo "$SIMS/sims/$1/tcpu_tb"; }
# ---------------------------------------------------------------- programs (as cpu-a/scripts/run-cpu-a.sh builds them)
GCC="riscv64-unknown-elf-gcc -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wa,--fatal-warnings"
E=$OUT/aelf
python3 $CK/gen-a01.py $E/a01_matrix.S > $E/gen-a01.log 2>&1; cmp -s $E/a01_matrix.S $CA/tests/a01_matrix.S || { echo "A: the generated a01 differs from the delivered one"; exit 3; }
cc() { local n=$1; shift; $GCC "$@" -o $E/$n.elf > $E/$n.cc.log 2>&1 || { echo "CC FAIL $n"; exit 3; }; riscv64-unknown-elf-nm $E/$n.elf > $E/$n.sym; }
cc a01 -march=rv64ia_zicsr -T $PREP/link.ld -I$PREP $PREP/crt.S $CA/tests/a01_matrix.S
# a02: the race simulators were built for its `race` word, so the run uses the very ELF build-p2b.sh compiled (the
# assembler's temporary names make a recompiled ELF differ byte-wise; its code would not)
cp $SIMS/aelf/a02.elf $E/a02.elf && riscv64-unknown-elf-nm $E/a02.elf > $E/a02.sym || { echo "A: no a02 from the build"; exit 3; }
cc a03 -march=rv64iac_zicsr -T $SUT/link.ld -I$SVT -I$SUT $SUT/crt.S $SUT/handlers.S $CA/tests/a03_except.S
cc p2b_irq_amo -march=rv64ia_zicsr -T $SUT/link.ld -I$SUT $SUT/crt.S $SUT/handlers.S $T2/p2b_irq_amo.S
cc t01 -march=rv64i_zicsr -T $PREP/link.ld -I$PREP $PREP/crt.S $PREP/t01_alu.S
(cd $E && sha256sum *.elf) > $E/elf.sha256
sym() { echo "0x$(awk -v n=$2 '$3==n{print $1}' $E/$1.sym)"; }
A01_ALOG=$(sym a01 alog); A01_NCASE=$(sym a01 ncase); A02_ALOG=$(sym a02 alog); A02_NCASE=$(sym a02 ncase); A03_SLOT=$(sym a03 slot)
read race_built a02_built < $SIMS/a02-race.txt
if [ "$race_built" != "$(sym a02 race)" ] || [ "$a02_built" != "$(sha256sum $E/a02.elf | cut -c1-16)" ]; then
  echo "A: the race simulators were built for a02 race=$race_built sha=$a02_built, this a02 has race=$(sym a02 race)"; exit 3; fi
run() {  # run <sim> <elf> <prefix> [args...]
  local sim=$1 elf=$2 pre=$3; shift 3
  timeout 300 $(S $sim) +elf=$elf +max-cycles=800000 +max-traps=1000 +pipe-trace \
    +commit-trace=$pre.commits +mem-dump=80000000:8192:$pre.mem "$@" > $pre.log 2>&1
  echo $? > $pre.exit
}
errs() { grep -cE '^(PIPE ASSERT|PROTO ERROR|OBS ERROR|A_OBS_FAIL|IRQ LATENCY ERROR|PROGRESS ERROR)' "$1"; }
score() {  # score <prefix> <test> [extra checker args]: the checker's exit code
  local pre=$1 t=$2; shift 2; local rc; rc=$(cat $pre.exit)
  case $t in
    a01) python3 $CK/check-a01.py $pre.commits $pre.mem $A01_ALOG $A01_NCASE --expect 138 --rc $rc --log $pre.log "$@" ;;
    a02) python3 $CK/check-a02.py $pre.log $pre.mem $A02_ALOG $A02_NCASE --rc $rc --log $pre.log "$@" ;;
    a03) python3 $CK/check-a03.py $pre.log $rc $A03_SLOT "$@" ;;
  esac > $pre.score 2>&1; echo $?
}

# ---------------------------------------------------------------- AA / AB
echo "== AA: the CPU-A directed tests on both cores, scored by the CPU-A checkers" | tee $OUT/AA.txt
echo "== AB: architectural differential of the AA runs (multicycle MISA_A=1 reference)" > $OUT/AB.txt
for case in a01:t0 a01:t1 a01:t2 a02:t0 a02:t1 a02:t2 a02:race a03:t0 a03:t1 a03:t2; do
  t=${case%:*}; prof=${case#*:}; extra=()
  [ $prof = race ] && extra=(--expect-ext-race 1 --case13-word 0xAA001)
  for impl in pmcsa ma; do pre=$OUT/AA/$t-$prof-$impl; run $impl-$prof $E/$t.elf $pre; done
  sp=$(score $OUT/AA/$t-$prof-pmcsa $t "${extra[@]}"); sm=$(score $OUT/AA/$t-$prof-ma $t "${extra[@]}")
  echo "  $t $prof: pipeline exit $(cat $OUT/AA/$t-$prof-pmcsa.exit) errors $(errs $OUT/AA/$t-$prof-pmcsa.log) score $sp ($(head -1 $OUT/AA/$t-$prof-pmcsa.score | cut -c1-90)) | multicycle exit $(cat $OUT/AA/$t-$prof-ma.exit) score $sm" | tee -a $OUT/AA.txt
  r=$(python3 $SC/p1diff.py --require-complete $OUT/AA/$t-$prof-ma $OUT/AA/$t-$prof-pmcsa); echo "  $t $prof: $r" | tee -a $OUT/AB.txt
done
# the runner's own rules, on real data: a clean data set with a failed process, and a log without completion
st=$(python3 $CK/check-a01.py $OUT/AA/a01-t0-pmcsa.commits $OUT/AA/a01-t0-pmcsa.mem $A01_ALOG $A01_NCASE --expect 138 --rc 3 --log $OUT/AA/a01-t0-pmcsa.log 2>&1); r1=$?
st2=$(python3 $CK/check-a02.py $OUT/AA/a02-t0-pmcsa.log $OUT/AA/a02-t0-pmcsa.mem $A02_ALOG $A02_NCASE --rc 0 --log /dev/null 2>&1); r2=$?
[ $r1 != 0 ] && echo "$st" | grep -q "a positive run must exit 0" && echo "  self-test exit code: refused" | tee -a $OUT/AA.txt || echo "  self-test exit code: NOT refused" | tee -a $OUT/AA.txt
[ $r2 != 0 ] && echo "$st2" | grep -q 'no "TOHOST code=0"' && echo "  self-test completion: refused" | tee -a $OUT/AA.txt || echo "  self-test completion: NOT refused" | tee -a $OUT/AA.txt

# ---------------------------------------------------------------- AC
echo "== AC: an M interrupt at every cycle of a block of AMOs and an LR/SC loop (independent checks, then alignment)" | tee $OUT/AC.txt
WA=$(sym p2b_irq_amo slot); WAW=$(sym p2b_irq_amo slotw)
run pmcsa-t0 $E/p2b_irq_amo.elf $OUT/AC/noirq +target-addr=$WA
bk=$(awk '$3=="blk"{print $1}' $E/p2b_irq_amo.sym); be=$(awk '$3=="blk_end"{print $1}' $E/p2b_irq_amo.sym)
read c0 c1 < <(awk -v s=$bk -v e=$be '/^CMT/{if (match($0,/pc=[0-9a-f]+/)) {p=substr($0,RSTART+3,RLENGTH-3); split($2,a,"="); if (p==s && !x) x=a[2]; if (p==e && !y) y=a[2]}} END{print x+0, y+0}' $OUT/AC/noirq.log)
echo "  without an interrupt: exit $(cat $OUT/AC/noirq.exit) (check 8 expected: the test requires its interrupt), $(grep -oE 'WATCH .*writes=[0-9]+' $OUT/AC/noirq.log); the block retires from cycle $c0 to $c1 (t0)" | tee -a $OUT/AC.txt
aok=0; afail=0; aal=0; anon=0; inside=0
wlo=$(printf '%08x' $((WA & 0xffffffff))); whi=$(printf '%08x' $((WAW & 0xffffffff)))
for c in $(seq $((c0 - 6)) 1 $((c1 + 4))); do
  pre=$OUT/AC/c$c; run pmcsa-t0 $E/p2b_irq_amo.elf $pre-p +irq-at-cycle=$c +target-addr=$WA
  ec=$(cat $pre-p.exit); e=$(errs $pre-p.log); ni=$(grep -c '^TRP.*irq=1' $pre-p.log); w=$(grep -oE 'writes=[0-9]+' $pre-p.log | cut -d= -f2)
  # inside an atomic access: raised after the request of an atomic to slot / slotw and no later than its retirement
  d=$(awk -v r=$c -v a="addr=$wlo" -v b="addr=$whi" '/^DREQ/ && ($3==a || $3==b) {split($2,x,"="); q=x[2]} /^(CMT|TRP)/ && q != "" {split($2,x,"="); if (r >= q && r <= x[2]) hit=1; q=""} END{print hit+0}' $pre-p.log)
  inside=$((inside + d))
  k=$(awk '/^TRP.*irq=1/{print n; exit} /^CMT/{n++}' n=0 $pre-p.log)
  if [ "$ec" = 0 ] && [ "$e" = 0 ] && [ "$ni" = 1 ] && [ "$w" = 5 ]; then st=PASS; aok=$((aok+1)); else st="FAIL(exit $ec, errors $e, interrupts $ni, writes $w)"; afail=$((afail+1)); fi
  al="not-aligned"
  if [ -n "$k" ]; then for dd in 0 -1 1 -2 2 -3 3; do np=$((k + dd)); [ $np -ge 1 ] || continue
    run ma-t0 $E/p2b_irq_amo.elf $pre-m +irq-at-retire=$np +target-addr=$WA
    km=$(awk '/^TRP.*irq=1/{print n; exit} /^CMT/{n++}' n=0 $pre-m.log)
    if [ "$km" = "$k" ]; then r=$(python3 $SC/p1diff.py --require-complete $pre-m $pre-p); [ $? = 0 ] && { al="aligned(N'=$np): $r"; aal=$((aal+1)); } || { al="aligned(N'=$np) BUT $r"; anon=$((anon+1)); }; break; fi
  done; fi
  [ "$al" = not-aligned ] && anon=$((anon+1))
  echo "  p2b_irq_amo cycle=$c: $st k=$k inside_atomic=$d | $al" >> $OUT/AC.txt
done
echo "  AC total: self-checks $aok PASS / $afail FAIL; aligned and identical $aal, not aligned or different $anon; raised inside an atomic access: $inside" | tee -a $OUT/AC.txt

# ---------------------------------------------------------------- AD
echo "== AD: the CPU-A injections on both cores, each rejected by its own named check" | tee $OUT/AD.txt
for impl in pmcsa ma; do
  pre=$OUT/AD/FAULT_A_W_NOSEXT-$impl; run $impl-FAULT_A_W_NOSEXT $E/a01.elf $pre; score $pre a01 > /dev/null
  echo "  FAULT_A_W_NOSEXT on $impl, a01: $(python3 $SC2/ajudge.py $pre "the instruction's inputs give 0xffffffff" $pre.score)" | tee -a $OUT/AD.txt
  pre=$OUT/AD/FAULT_A_AMO_AS_LOAD-$impl; run $impl-FAULT_A_AMO_AS_LOAD $E/a01.elf $pre; score $pre a01 > /dev/null
  echo "  FAULT_A_AMO_AS_LOAD on $impl, a01: $(python3 $SC2/ajudge.py $pre "the instruction's inputs give" $pre.score)" | tee -a $OUT/AD.txt
  pre=$OUT/AD/FAULT_A_SC_RESULT-$impl; run $impl-FAULT_A_SC_RESULT $E/a02.elf $pre; score $pre a02 > /dev/null
  echo "  FAULT_A_SC_RESULT on $impl, a02: $(python3 $SC2/ajudge.py $pre "the SC returned 0, the rule says 1" $pre.score)" | tee -a $OUT/AD.txt
  pre=$OUT/AD/FAULT_A_NO_RESV_CLEAR-$impl; run $impl-FAULT_A_NO_RESV_CLEAR $E/a02.elf $pre; score $pre a02 > /dev/null
  echo "  FAULT_A_NO_RESV_CLEAR on $impl, a02: $(python3 $SC2/ajudge.py $pre "a trap between the LR and the SC drops it" $pre.score)" | tee -a $OUT/AD.txt
  pre=$OUT/AD/FAULT_A_EARLY_RETIRE-$impl; run $impl-FAULT_A_EARLY_RETIRE $E/a01.elf $pre
  echo "  FAULT_A_EARLY_RETIRE on $impl, a01: $(python3 $SC2/ajudge.py $pre "^A_OBS_FAIL early-retire")" | tee -a $OUT/AD.txt
  for f in FAULT_A_W_NOSEXT FAULT_A_AMO_AS_LOAD FAULT_A_SC_RESULT FAULT_A_NO_RESV_CLEAR FAULT_A_EARLY_RETIRE; do
    run $impl-$f $E/t01.elf $OUT/AD/ctl-$f-$impl
    echo "  control $impl-$f on t01: exit $(cat $OUT/AD/ctl-$f-$impl.exit), errors $(errs $OUT/AD/ctl-$f-$impl.log)" | tee -a $OUT/AD.txt; done
done
echo "RUN_P2B_A_DONE"
