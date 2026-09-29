#!/bin/bash
# PIPE-P2a (M part): run-p2a.sh <sims dir from build-p2a.sh> <fresh outdir> [hazard seeds]
#   A  m01 (every M operation on edge operands, explicit expected values, gen_m01.py) on the pipeline M build, 5
#      profiles, self-checking; the multicycle reference on the same program; the P1 configuration must refuse M
#      (illegal instruction at the first M instruction) -- RV64I mode retained
#   B  architectural differential vs the multicycle reference, 5 profiles: m01 without its misa check, the directed
#      M programs, generated hazard programs with M
#   C  interrupts around long M operations: independent checks, then DUT-directed alignment of the reference
#   D  negative controls: knob 15 (stale result) and 16 (duplicate start) by their named properties as the FIRST
#      failure; the unit's fault injections by gen_m01's derived check numbers, on both implementations
#   F  M ROIs, both implementations (reported, not gated)
#   G  shared / multicycle sources unchanged against the tag
set -u
SIMS=${1:?sims dir}; OUT=${2:?outdir}; NHZ=${3:-40}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
W=/home/engineer/fpga/worktrees/pipe-single; P1=$W/experiments/pipeline/p1; P2=$W/experiments/pipeline/p2a
SC=$P1/scripts; SC2=$P2/scripts; T1=$P1/tests; T2=$P2/tests
PREP=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests; CM=/home/engineer/fpga/experiments/teaching-cpu/cpu-m
mkdir -p $OUT/elf $OUT/A $OUT/B $OUT/C $OUT/D $OUT/F
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
S() { echo "$SIMS/sims/$1/tcpu_tb"; }
CC="riscv64-unknown-elf-gcc -march=rv64im_zicsr_zifencei -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wa,--fatal-warnings -T $PREP/link.ld"
mk() { local n=$1; shift
  $CC -I$PREP -I$T1 -o $OUT/elf/$n.elf "$@" > $OUT/elf/$n.cc.log 2>&1 || { echo "CC FAIL $n"; grep -v RWX $OUT/elf/$n.cc.log | head -3; exit 3; }
  riscv64-unknown-elf-nm $OUT/elf/$n.elf > $OUT/elf/$n.sym; riscv64-unknown-elf-objdump -d $OUT/elf/$n.elf > $OUT/elf/$n.dis; }
# ---------------------------------------------------------------- programs
python3 $CM/tests/gen_m01.py $OUT/elf/m01.S --fault-codes > $OUT/elf/gen_m01.log                       # misa I+M
python3 $CM/tests/gen_m01.py $OUT/elf/m01mc.S --misa=0x8000000000141104 > /dev/null                   # the tag core's misa
# the differential copy: identical up to the misa read, which differs by design, then PASS
awk '/csrr +t0, misa/{skip=1} /^ *PASS/{skip=0} !skip' $OUT/elf/m01.S > $OUT/elf/m01x.S
grep -q 'misa' $OUT/elf/m01x.S && { echo "m01x still reads misa"; exit 3; }
mk m01 $PREP/crt.S $OUT/elf/m01.S; mk m01mc $PREP/crt.S $OUT/elf/m01mc.S; mk m01x $PREP/crt.S $OUT/elf/m01x.S
mk t01_alu $PREP/crt.S $PREP/t01_alu.S
for t in p2a_md_hazard p2a_md_fault p2a_md_irq p2a_md_perf; do mk $t $T1/p1crt.S $T2/$t.S; done
for s in $(seq 1 $NHZ); do python3 $SC2/gen-hazard-p2a.py $s 400 --m > $OUT/elf/hzm$s.S; mk hzm$s $T1/p1crt.S $OUT/elf/hzm$s.S; done
(cd $OUT/elf && sha256sum *.elf) > $OUT/elf.sha256
echo "M instructions in m01: $(grep -cE '\s(mul|mulh|mulhsu|mulhu|div|divu|rem|remu|mulw|divw|divuw|remw|remuw)\s' $OUT/elf/m01.dis)" | tee $OUT/programs.txt
echo "M instructions in the $NHZ hazard programs: $(cat $OUT/elf/hzm*.dis | grep -cE '\s(mul|mulh|mulhsu|mulhu|div|divu|rem|remu|mulw|divw|divuw|remw|remuw)\s')" | tee -a $OUT/programs.txt
run() {  # run <sim> <elf> <prefix> [args...]
  local sim=$1 elf=$2 pre=$3; shift 3
  timeout 300 $(S $sim) +elf=$OUT/elf/$elf.elf +max-cycles=6000000 +max-traps=1000 +pipe-trace \
    +commit-trace=$pre.commits +mem-dump=80000000:8192:$pre.mem "$@" > $pre.log 2>&1
  echo $? > $pre.exit
}
errs() { grep -cE '^(PIPE ASSERT|PROTO ERROR|OBS ERROR|IRQ LATENCY ERROR|PROGRESS ERROR)' "$1"; }
PROFILES="min fixed rnd12345 rnd777 rnd4242"

# ---------------------------------------------------------------- A
echo "== A: m01 self-checks (all 13 operations, edge operands, misa), and RV64I mode retained" | tee $OUT/A.txt
for prof in $PROFILES; do
  run pm-$prof m01 $OUT/A/m01-$prof-pm; run m-$prof m01mc $OUT/A/m01mc-$prof-m
  echo "  $prof: pipeline M exit $(cat $OUT/A/m01-$prof-pm.exit) errors $(errs $OUT/A/m01-$prof-pm.log) | multicycle exit $(cat $OUT/A/m01mc-$prof-m.exit) errors $(errs $OUT/A/m01mc-$prof-m.log)" | tee -a $OUT/A.txt
done
first_md=$(grep -m1 -E '^\s*[0-9a-f]+:\s+[0-9a-f]{8}\s+(mul|mulh|mulhsu|mulhu|div|divu|rem|remu|mulw|divw|divuw|remw|remuw)\s' $OUT/elf/m01.dis | awk -F: '{print $1}' | tr -d ' ')
run p1-min m01 $OUT/A/m01-p1
t=$(grep -m1 '^TRP' $OUT/A/m01-p1.log)
echo "  P1 configuration on m01: exit $(cat $OUT/A/m01-p1.exit); first trap: $t; first M instruction at 0x$first_md" | tee -a $OUT/A.txt

# ---------------------------------------------------------------- B
echo "== B: architectural differential vs the multicycle reference, 5 profiles" | tee $OUT/B.txt
BSET="m01x p2a_md_hazard p2a_md_fault t01_alu"; for s in $(seq 1 $NHZ); do BSET="$BSET hzm$s"; done
bok=0; bfail=0
for prof in $PROFILES; do for t in $BSET; do
  run m-$prof $t $OUT/B/$t-$prof-m; run pm-$prof $t $OUT/B/$t-$prof-p
  r=$(python3 $SC/p1diff.py --require-complete $OUT/B/$t-$prof-m $OUT/B/$t-$prof-p); rc=$?
  echo "$prof $t $r" >> $OUT/B/results.txt
  if [ $rc = 0 ]; then bok=$((bok+1)); else bfail=$((bfail+1)); echo "  FAIL $prof $t: $r" | tee -a $OUT/B.txt; fi
done; done
echo "  B total: $bok DIFF_OK, $bfail DIFF_FAIL over $(echo $PROFILES | wc -w) profiles x $(echo $BSET | wc -w) programs" | tee -a $OUT/B.txt

# ---------------------------------------------------------------- C
echo "== C: interrupts around long M operations (independent checks, then alignment of the reference)" | tee $OUT/C.txt
cok=0; cfail=0; aok=0; anon=0
t=p2a_md_irq
for n in $(seq 8 2 60); do for prof in min fixed rnd12345; do
  pre=$OUT/C/$t-$n-$prof; run pm-$prof $t $pre-p +irq-at-retire=$n
  ec=$(cat $pre-p.exit); e=$(errs $pre-p.log); ni=$(grep -c '^TRP.*irq=1' $pre-p.log)
  lat=$(grep -oE 'max=[0-9]+' $pre-p.log | cut -d= -f2)
  k=$(awk '/^TRP.*irq=1/{print n; exit} /^CMT/{n++}' n=0 $pre-p.log)
  if [ "$ec" = 0 ] && [ "$e" = 0 ] && [ "$ni" -ge 1 ]; then st=PASS; cok=$((cok+1)); else st="FAIL(exit $ec, errors $e, interrupts $ni)"; cfail=$((cfail+1)); fi
  al="not-aligned"
  if [ -n "$k" ]; then for d in 0 -1 1 -2 2 -3 3 -4 4; do
    np=$((k + d)); [ $np -ge 1 ] || continue
    run m-$prof $t $pre-m +irq-at-retire=$np
    km=$(awk '/^TRP.*irq=1/{print n; exit} /^CMT/{n++}' n=0 $pre-m.log)
    if [ "$km" = "$k" ]; then
      r=$(python3 $SC/p1diff.py --require-complete $pre-m $pre-p); [ $? = 0 ] && { al="aligned(N'=$np): $r"; aok=$((aok+1)); } || { al="aligned(N'=$np) BUT $r"; anon=$((anon+1)); }
      break
    fi
  done; fi
  [ "$al" = not-aligned ] && anon=$((anon+1))
  echo "  $t N=$n $prof: $st k=$k interrupts=$ni max_latency=$lat | $al" | tee -a $OUT/C.txt
done; done
echo "  C total: self-checks $cok PASS / $cfail FAIL; reference aligned and identical $aok, not aligned or different $anon" | tee -a $OUT/C.txt

# ---------------------------------------------------------------- D
echo "== D: negative controls" | tee $OUT/D.txt
run pm-fault15 p2a_md_fault $OUT/D/fault15-p2a_md_fault
echo "  knob 15 (MD_STALE_RESULT) on p2a_md_fault: $(python3 $SC/mutjudge.py first $OUT/D/fault15-p2a_md_fault 'PIPE ASSERT md-owner')" | tee -a $OUT/D.txt
run pm-fault16 p2a_md_hazard $OUT/D/fault16-p2a_md_hazard
echo "  knob 16 (MD_RESTART) on p2a_md_hazard: $(python3 $SC/mutjudge.py first $OUT/D/fault16-p2a_md_hazard 'PIPE ASSERT md-once')" | tee -a $OUT/D.txt
WS=$(grep -oE 'FAULT_CODES wsext=[0-9]+' $OUT/elf/gen_m01.log | grep -oE '[0-9]+$'); MH=$(grep -oE 'mulhsign=[0-9]+' $OUT/elf/gen_m01.log | grep -oE '[0-9]+$')
echo "  expected rejections (derived by gen_m01.py): FAULT_W_SEXT -> check $WS, FAULT_MULH_SIGN -> check $MH" | tee -a $OUT/D.txt
for impl in pm m; do e=m01; [ $impl = m ] && e=m01mc
  run $impl-wsext $e $OUT/D/wsext-$impl; run $impl-mulhsign $e $OUT/D/mulhsign-$impl
  echo "  FAULT_W_SEXT on $impl: $(python3 $SC/mutjudge.py first $OUT/D/wsext-$impl "TOHOST code=$WS ")" | tee -a $OUT/D.txt
  echo "  FAULT_MULH_SIGN on $impl: $(python3 $SC/mutjudge.py first $OUT/D/mulhsign-$impl "TOHOST code=$MH ")" | tee -a $OUT/D.txt
done
for kp in "pm-fault15:t01_alu" "pm-fault16:t01_alu" "pm-wsext:t01_alu" "pm-mulhsign:t01_alu"; do sim=${kp%%:*}; prog=${kp#*:}
  run $sim $prog $OUT/D/ctl-$sim-$prog; echo "  control $sim on $prog: exit $(cat $OUT/D/ctl-$sim-$prog.exit), errors $(errs $OUT/D/ctl-$sim-$prog.log)" | tee -a $OUT/D.txt; done

# ---------------------------------------------------------------- F
echo "== F: M ROIs (second pass, warm I-cache); reported, not gated" | tee $OUT/F.txt
for prof in min fixed; do for impl in m pm; do
  run $impl-$prof p2a_md_perf $OUT/F/perf-$prof-$impl
  echo "  $impl ($prof):" | tee -a $OUT/F.txt; python3 $SC/perf.py $OUT/F/perf-$prof-$impl.log $OUT/elf/p2a_md_perf.sym | sed 's/^/    /' | tee -a $OUT/F.txt
done; done

# ---------------------------------------------------------------- G
echo "== G: shared and multicycle sources compiled vs tag mc-v1-dual" | tee $OUT/G.txt
for f in $SIMS/src/rtl/*.v $SIMS/src/rtl/*.vh; do b=$(basename $f)
  t=$(git -C $W show mc-v1-dual:rtl/cpu/$b 2>/dev/null | sha256sum | cut -c1-16); c=$(sha256sum $f | cut -c1-16)
  [ "$t" = "$c" ] && echo "  unchanged $b $c" >> $OUT/G.txt || echo "  CHANGED $b tag=$t now=$c" | tee -a $OUT/G.txt
done
echo "  $(grep -c unchanged $OUT/G.txt) shared/multicycle RTL files byte-identical to the tag; $(grep -c CHANGED $OUT/G.txt) changed" | tee -a $OUT/G.txt
echo "== verdict" | tee $OUT/verdict.txt
python3 $SC2/p2averdict.py $OUT --nhz $NHZ | tee -a $OUT/verdict.txt; v=${PIPESTATUS[0]}
echo "RUN_P2A_DONE verdict_rc=$v"
exit $v
