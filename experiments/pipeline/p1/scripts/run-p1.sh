#!/bin/bash
# PIPE-P1: the whole standalone verification, deterministic, bounded.   run-p1.sh <sims dir> <fresh outdir> [hazard seeds]
#   A  existing programs with their accepted expectations, on BOTH implementations (the P1 subset, reported per program)
#   B  architectural differential (multicycle = reference): directed P1 programs, the completing existing programs,
#      generated hazard programs; 5 timing profiles (min, fixed, 3 recorded random seeds)
#   C  interrupts: independent self-checks + latency bound on the pipeline, then DUT-directed alignment of the
#      multicycle reference and a full-stream comparison (alignment is an equivalence technique, not the oracle)
#   D  negative controls: each pipeline fault knob must fail its named property (not a timeout / build error)
#   E  monitor self-tests and the existing core fault injections, on the pipeline
#   F  ROI performance, both implementations
#   G  shared / multicycle sources unchanged against the tag
# Exit status: 0 only if p1verdict.py accepts the run (see the end); 2 = refused, 3 = a program did not compile.
set -u
SIMS=${1:?sims dir}; OUT=${2:?outdir}; NHZ=${3:-40}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
W=/home/engineer/fpga/worktrees/pipe-single; P1=$W/experiments/pipeline/p1; T=$P1/tests; SC=$P1/scripts
PREP=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests; WS=/home/engineer/fpga/teaching-cpu-work/cpu
mkdir -p $OUT/elf $OUT/A $OUT/B $OUT/C $OUT/D $OUT/E $OUT/F
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
S() { echo "$SIMS/sims/$1/tcpu_tb"; }
CC="riscv64-unknown-elf-gcc -march=rv64i_zicsr_zifencei -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wa,--fatal-warnings -T $PREP/link.ld"
mk() {  # mk <name> <sources...> [-D...]
  local n=$1; shift
  $CC -I$PREP -I$T -I$WS/tests2 -o $OUT/elf/$n.elf "$@" > $OUT/elf/$n.cc.log 2>&1 || { echo "CC FAIL $n"; grep -v RWX $OUT/elf/$n.cc.log | head -3; exit 3; }
  riscv64-unknown-elf-nm $OUT/elf/$n.elf > $OUT/elf/$n.sym; riscv64-unknown-elf-objdump -d $OUT/elf/$n.elf > $OUT/elf/$n.dis
}
# ---------------------------------------------------------------- programs
for t in t01_alu t01n_x0check t02_branch t03_ldst t04_trap t05_roi; do mk $t $PREP/crt.S $PREP/$t.S; done
for c in c05_mret_count c06_targets c07_handler_fault c08_accessfault c09_ecall_ebreak; do mk $c $PREP/crt.S $WS/tests2/thandler.S $WS/tests2/$c.S; done
for d in d01_highpa d02_misaligned d03_badbranch d04_illegal d06_loadpayload d07_csr_cycle d08_minstret_ok; do mk $d $WS/tests/dcrt.S $WS/tests/$d.S; done
for n in 1 2 3 4 5 6 7; do mk d05_jalr_f$n -DJALR_F3=$n $WS/tests/dcrt.S $WS/tests/d05_jalr_illegal.S; done
P1DIFF="p1_fwd p1_loaduse p1_branch p1_store_trap p1_csr p1_twoflush p1_fencei p1_perf"
P1IRQ="p1_irq_basic p1_irq_masked p1_irq_fault p1_irq_hold p1_irq_empty p1_irq_warm p1_irq_cancel"
for t in $P1DIFF $P1IRQ p1_misa; do mk $t $T/p1crt.S $T/$t.S; done
for s in $(seq 1 $NHZ); do python3 $SC/gen-hazard.py $s 400 > $OUT/elf/hz$s.S; mk hz$s $T/p1crt.S $OUT/elf/hz$s.S; done
(cd $OUT/elf && sha256sum *.elf) > $OUT/elf.sha256
sym() { awk -v n="$2" '$3==n{print $1}' $OUT/elf/$1.sym; }
python3 $PREP/expected-trace.py $OUT/elf/t05_roi.dis 16 > $OUT/t05-expected-trace.txt
ROI_S=$(grep -E "csrrs?\s+s0,minstret" $OUT/elf/t05_roi.dis | head -1 | awk -F: '{print $1}' | tr -d ' ')
ROI_E=$(grep -E "csrrs?\s+s1,minstret" $OUT/elf/t05_roi.dis | head -1 | awk -F: '{print $1}' | tr -d ' ')

run() {  # run <sim> <elf> <prefix> [args...] -> prefix.{log,commits,mem,exit}
  local sim=$1 elf=$2 pre=$3; shift 3
  timeout 120 $(S $sim) +elf=$OUT/elf/$elf.elf +max-cycles=3000000 +max-traps=1000 +pipe-trace \
    +commit-trace=$pre.commits +mem-dump=80000000:8192:$pre.mem "$@" > $pre.log 2>&1
  echo $? > $pre.exit
}
errs() { grep -cE '^(PIPE ASSERT|PROTO ERROR|OBS ERROR|IRQ LATENCY ERROR|PROGRESS ERROR)' "$1"; }

# ---------------------------------------------------------------- A: existing programs, both implementations
echo "== A: the P1 subset of the existing programs, accepted expectations, both implementations (min profile)" | tee $OUT/A.txt
Arun() {  # Arun <label> <elf> <want> [args]
  local label=$1 elf=$2 want=$3; shift 3
  local line="  $(printf '%-22s' $label)"
  for impl in m p; do
    run $impl-min $elf $OUT/A/$label-$impl "$@"
    local ec; ec=$(cat $OUT/A/$label-$impl.exit); local e; e=$(errs $OUT/A/$label-$impl.log)
    local st=PASS; [ "$ec" = "$want" ] || st="FAIL(exit $ec, want $want)"; [ "$e" = 0 ] || st="$st +$e errors"
    line="$line  $impl: $(printf '%-28s' "$st")"
  done
  echo "$line" | tee -a $OUT/A.txt
}
Arun t01_alu t01_alu 0; Arun t02_branch t02_branch 0; Arun t03_ldst t03_ldst 0
Arun t04_trap t04_trap 0 +expect-traps=4 +expect-cause=11
Arun t05_roi t05_roi 0 +roi=${ROI_S}:${ROI_E} +roi-expect=$OUT/t05-expected-trace.txt
Arun t01n_x0check t01n_x0check 1
Arun c05_mret_count c05_mret_count 0 +expect-traps=1 +expect-commit-count=$(sym c05_mret_count the_bad_word):0
Arun c06_targets c06_targets 0 +expect-traps=1 +expect-cause=0
Arun c07_handler_fault c07_handler_fault 13
Arun c08_accessfault c08_accessfault 0 +expect-traps=3 +expect-cause=1
Arun c09_ecall_ebreak c09_ecall_ebreak 0 +expect-traps=2 +expect-commit-count=$(sym c09_ecall_ebreak the_ecall):0 +expect-commit-count=$(sym c09_ecall_ebreak the_ebreak):0
Arun d01_highpa d01_highpa 0 +expect-trap=7 +expect-data-req=0
Arun d02_misaligned d02_misaligned 0 +expect-trap=4 +expect-data-req=0
Arun d03_badbranch d03_badbranch 0
Arun d04_illegal d04_illegal 0 +expect-trap=2 +expect-data-req=0
for n in 1 2 3 4 5 6 7; do Arun d05_jalr_f$n d05_jalr_f$n 0 +expect-trap=2 +expect-reg=9:5a5a5a5a; done
Arun d06_loadpayload d06_loadpayload 0
Arun d07_csr_cycle d07_csr_cycle 0
Arun d08_minstret_ok d08_minstret_ok 0
Arun p1_misa-PIPE-ONLY p1_misa 0

# ---------------------------------------------------------------- B: differential
echo "== B: architectural differential, 5 profiles (multicycle reference vs pipeline)" | tee $OUT/B.txt
PROFILES="min fixed rnd12345 rnd777 rnd4242"
BSET="t01_alu t02_branch t03_ldst t04_trap t05_roi c05_mret_count c08_accessfault c09_ecall_ebreak d03_badbranch d06_loadpayload d08_minstret_ok $P1DIFF"
for s in $(seq 1 $NHZ); do BSET="$BSET hz$s"; done
bok=0; bfail=0
for prof in $PROFILES; do
  for t in $BSET; do
    run m-$prof $t $OUT/B/$t-$prof-m; run p-$prof $t $OUT/B/$t-$prof-p
    r=$(python3 $SC/p1diff.py --require-complete $OUT/B/$t-$prof-m $OUT/B/$t-$prof-p); rc=$?   # every B program must finish
    echo "$prof $t $r" >> $OUT/B/results.txt
    if [ $rc = 0 ]; then bok=$((bok+1)); else bfail=$((bfail+1)); echo "  FAIL $prof $t: $r" | tee -a $OUT/B.txt; fi
  done
done
echo "  B total: $bok DIFF_OK, $bfail DIFF_FAIL over $(echo $PROFILES | wc -w) profiles x $(echo $BSET | wc -w) programs" | tee -a $OUT/B.txt
# the exit codes seen in B (a program that exits non-zero identically on both would still "match": list them)
awk '{print $3}' $OUT/B/results.txt | sort | uniq -c | tee -a $OUT/B.txt

# ---------------------------------------------------------------- C: interrupts
echo "== C: interrupts -- independent checks on the pipeline, then DUT-directed alignment of the reference" | tee $OUT/C.txt
Cspec="p1_irq_basic:20,30,40,60,70 p1_irq_masked:12,20,30 p1_irq_fault:14,16,18,20,22,24,26,30 p1_irq_hold:20,30 p1_irq_empty:12,14,18,20,21,22,23,24,26 p1_irq_warm:40,60,80,100,120,150 p1_irq_cancel:44,45,46,47,48,49,50,51"
cok=0; cfail=0; aok=0; anon=0
for spec in $Cspec; do
  t=${spec%%:*}; for n in $(echo ${spec#*:} | tr , ' '); do for prof in min fixed rnd12345; do
    pre=$OUT/C/$t-$n-$prof; run p-$prof $t $pre-p +irq-at-retire=$n
    ec=$(cat $pre-p.exit); e=$(errs $pre-p.log); ni=$(grep -c '^TRP.*irq=1' $pre-p.log)
    lat=$(grep -oE 'max=[0-9]+' $pre-p.log | cut -d= -f2)
    k=$(awk '/^TRP.*irq=1/{print n; exit} /^CMT/{n++}' n=0 $pre-p.log)
    need=1; [ $t = p1_irq_cancel ] && need=0
    if [ "$ec" = 0 ] && [ "$e" = 0 ] && [ "$ni" -ge $need ]; then st=PASS; cok=$((cok+1)); else st="FAIL(exit $ec, errors $e, interrupts $ni)"; cfail=$((cfail+1)); fi
    # alignment: find a raise position N' at which the reference takes its first interrupt after exactly k retirements
    al="not-aligned"
    [ -z "$k" ] && { al="n/a (no interrupt taken on the pipeline: independent checks only)"; echo "  $t N=$n $prof: $st interrupts=$ni max_latency=$lat cancelled=$(grep -oE 'irq_cancelled=[0-9]+' $pre-p.log) | $al" | tee -a $OUT/C.txt; continue; }
    for d in 0 -1 1 -2 2 -3 3 -4 4; do
      np=$((k + d)); [ $np -ge 1 ] || continue
      run m-$prof $t $pre-m +irq-at-retire=$np
      km=$(awk '/^TRP.*irq=1/{print n; exit} /^CMT/{n++}' n=0 $pre-m.log)
      if [ "$km" = "$k" ]; then
        r=$(python3 $SC/p1diff.py --require-complete $pre-m $pre-p); [ $? = 0 ] && { al="aligned(N'=$np): $r"; aok=$((aok+1)); } || { al="aligned(N'=$np) BUT $r"; anon=$((anon+1)); }
        break
      fi
    done
    [ "$al" = not-aligned ] && anon=$((anon+1))
    echo "  $t N=$n $prof: $st k=$k interrupts=$ni max_latency=$lat | $al" | tee -a $OUT/C.txt
  done; done
done
echo "  C total: self-checks $cok PASS / $cfail FAIL; reference aligned and identical $aok, not aligned or different $anon" | tee -a $OUT/C.txt

# ---------------------------------------------------------------- D: negative controls
echo "== D: pipeline fault knobs (fixed profile), each must fail its INTENDED property as its FIRST failure" | tee $OUT/D.txt
Dfirst() {  # Dfirst <knob> <prog> <regex> [args]
  local k=$1 prog=$2 rx=$3; shift 3
  run p-fault$k $prog $OUT/D/fault$k-$prog "$@"
  echo "  knob $k on $prog: $(python3 $SC/mutjudge.py first $OUT/D/fault$k-$prog "$rx")" | tee -a $OUT/D.txt
}
Deff() {  # Deff <knob> <prog>: the core's logged fault effect must be the first divergence from the reference
  local k=$1 prog=$2
  run p-fault$k $prog $OUT/D/fault$k-$prog; run m-fixed $prog $OUT/D/ref-$prog
  echo "  knob $k on $prog: $(python3 $SC/mutjudge.py effect $OUT/D/fault$k-$prog $OUT/D/ref-$prog)" | tee -a $OUT/D.txt
}
Dfirst 1  p1_loaduse    'PIPE ASSERT once-only'
Dfirst 2  p1_branch     'PIPE ASSERT redirect-once'
Dfirst 3  hz10          'PIPE ASSERT fetch-delivery'
Dfirst 4  p1_store_trap 'PIPE ASSERT oldest-issue'
Dfirst 5  p1_loaduse    'PIPE ASSERT load-use'
Deff   6  p1_fwd
Deff   7  p1_fwd
Deff   8  p1_fwd
Dfirst 9  p1_fwd        'TOHOST code=7 '
Dfirst 10 p1_irq_empty  'TOHOST code=1 ' +irq-at-retire=20
Dfirst 11 p1_csr        'PIPE ASSERT drain'
Dfirst 12 c08_accessfault 'PIPE ASSERT spec-uncached'   # a jump to non-existent (uncached) space: the fetch must wait
# controls: the same faulty cores on a program that does not exercise the fault pass (the knob is the cause)
for kp in "9:p1_loaduse" "10:p1_fwd" "3:p1_fwd" "12:p1_fwd"; do k=${kp%%:*}; prog=${kp#*:}
  run p-fault$k $prog $OUT/D/ctl$k-$prog; echo "  control knob $k on $prog: exit $(cat $OUT/D/ctl$k-$prog.exit), errors $(errs $OUT/D/ctl$k-$prog.log)" | tee -a $OUT/D.txt; done

# ---------------------------------------------------------------- E: monitors and existing injections on the pipeline
echo "== E: monitor self-tests and existing core fault injections on the pipeline" | tee $OUT/E.txt
Em() { local sim=$1 prog=$2 want=$3; run $sim $prog $OUT/E/$sim-$prog
  local hit; hit=$(grep -m1 -F "$want" $OUT/E/$sim-$prog.log)
  if [ -n "$hit" ]; then echo "  $sim on $prog: exit $(cat $OUT/E/$sim-$prog.exit) -> caught: $hit"; else echo "  $sim on $prog: exit $(cat $OUT/E/$sim-$prog.exit) NOT CAUGHT ($want)"; fi | tee -a $OUT/E.txt; }
Em p-mon-samecycle   t03_ldst        "PROTO ERROR: response in the request handshake cycle"
Em p-mon-withdraw    t03_ldst        "PROTO ERROR: request withdrawn before the handshake"
Em p-mon-loadpayload d06_loadpayload "PROTO ERROR: read request carried a write payload"
Em p-fault-x0        t01_alu         "TOHOST code=1 "
Em p-fault-nosext    t03_ldst        "TOHOST code=3 "

# ---------------------------------------------------------------- F: performance
echo "== F: ROI measurements (second pass, warm I-cache)" | tee $OUT/F.txt
for prof in min fixed; do for impl in m p; do
  run $impl-$prof p1_perf $OUT/F/perf-$prof-$impl
  echo "  $impl ($prof):" | tee -a $OUT/F.txt; python3 $SC/perf.py $OUT/F/perf-$prof-$impl.log $OUT/elf/p1_perf.sym | sed 's/^/    /' | tee -a $OUT/F.txt
done; done

# ---------------------------------------------------------------- G: shared and multicycle sources unchanged
echo "== G: sources compiled vs tag mc-v1-dual" | tee $OUT/G.txt
for f in $SIMS/src/rtl/*.v $SIMS/src/rtl/*.vh; do b=$(basename $f)
  t=$(git -C $W show mc-v1-dual:rtl/cpu/$b 2>/dev/null | sha256sum | cut -c1-16); c=$(sha256sum $f | cut -c1-16)
  [ "$t" = "$c" ] && echo "  unchanged $b $c" >> $OUT/G.txt || echo "  CHANGED $b tag=$t now=$c" | tee -a $OUT/G.txt
done
echo "  $(grep -c unchanged $OUT/G.txt) shared/multicycle RTL files byte-identical to the tag; $(grep -c CHANGED $OUT/G.txt) changed" | tee -a $OUT/G.txt

# ---------------------------------------------------------------- coverage over every pipeline run (each log once)
python3 $SC/p1coverage.py $OUT | tee $OUT/coverage.txt

# ---------------------------------------------------------------- verdict: the exit status of this script
# p1verdict.py names the only tolerated positive-test failures (A baseline exceptions) and fails the run on anything
# else: an unexpected failure, missing output, an uncaught negative control, a changed shared source, zero coverage.
echo "== verdict" | tee $OUT/verdict.txt
python3 $SC/p1verdict.py $OUT --nhz $NHZ | tee -a $OUT/verdict.txt; v=${PIPESTATUS[0]}
echo "RUN_P1_DONE verdict_rc=$v"
exit $v
