#!/bin/bash
# PIPE-P2b run: run-p2b.sh <sims dir from build-p2b.sh> <fresh outdir>
# Checkpoint 1 (privilege) sections:
#   SA  the CPU-SU directed tests su01..su11 on both cores, 3 profiles: the pipeline's exit equals the reference's, and
#       the reference equals its recorded baseline (su08 1, su09 8, su11 24: pre-Sv39 expectations, M1 T1.4 "SU 9")
#   SB  architectural differential on the programs without asynchronous events (strict for those that pass;
#       su02 reads `cycle` and su05/su06 are CLINT-timed: judged by their own checks in SA)
#   SC  an M-level interrupt raised at every position across M -> S -> U -> M (p2b_irq_priv; replaces su12's
#       multicycle-state aimed injection): independent checks, then alignment of the reference
#   SD  the CPU-SU fault injections (no delegation, S interrupt taken in M, SRET keeping SPP) on both cores, each
#       rejected by its named check; controls pass
#   G   shared / multicycle sources unchanged against the tag
set -u
SIMS=${1:?sims dir}; OUT=${2:?outdir}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
W=/home/engineer/fpga/worktrees/pipe-single; P1=$W/experiments/pipeline/p1; P2=$W/experiments/pipeline/p2b
SC=$P1/scripts; SC2=$P2/scripts; T2=$P2/tests
SUP=/home/engineer/fpga/experiments/teaching-cpu/cpu-su-prep; SUT=$SUP/tests; PREP=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests
mkdir -p $OUT/elf $OUT/SA $OUT/SB $OUT/SC $OUT/SD
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
S() { echo "$SIMS/sims/$1/tcpu_tb"; }
# ---------------------------------------------------------------- programs
bash $SUP/scripts/build.sh $OUT/elf/su > $OUT/elf/su-build.log 2>&1 || { echo "SU TEST BUILD FAIL"; tail -3 $OUT/elf/su-build.log; exit 3; }
GCC="riscv64-unknown-elf-gcc -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wa,--fatal-warnings"
$GCC -march=rv64imc_zicsr -I$SUT -T $SUT/link.ld -o $OUT/elf/p2b_irq_priv.elf $SUT/crt.S $SUT/handlers.S $T2/p2b_irq_priv.S > $OUT/elf/p2b_irq_priv.cc.log 2>&1 || { echo "CC FAIL p2b_irq_priv"; exit 3; }
riscv64-unknown-elf-nm $OUT/elf/p2b_irq_priv.elf > $OUT/elf/p2b_irq_priv.sym
$GCC -march=rv64i_zicsr -I$PREP -T $PREP/link.ld -o $OUT/elf/t01.elf $PREP/crt.S $PREP/t01_alu.S > /dev/null 2>&1 || { echo "CC FAIL t01"; exit 3; }
(cd $OUT/elf && sha256sum su/*.elf *.elf) > $OUT/elf.sha256
run() {  # run <sim> <elf path> <prefix> [args...]
  local sim=$1 elf=$2 pre=$3; shift 3
  timeout 300 $(S $sim) +elf=$elf +max-cycles=6000000 +max-traps=1000 +pipe-trace \
    +commit-trace=$pre.commits +mem-dump=80000000:8192:$pre.mem "$@" > $pre.log 2>&1
  echo $? > $pre.exit
}
errs() { grep -cE '^(PIPE ASSERT|PROTO ERROR|OBS ERROR|IRQ LATENCY ERROR|PROGRESS ERROR)' "$1"; }
PROFILES="min fixed rnd12345"
SU="su01_modes su02_csr_priv su03_deleg su04_strap su05_irq_modes su06_timer_ssip su07_epc_len su08_satp_bare su09_warl su10_wfi su11_mip_sw"

# ---------------------------------------------------------------- SA
echo "== SA: CPU-SU directed tests on both cores (priv = M at exit checked by the harness)" | tee $OUT/SA.txt
for t in $SU; do for prof in $PROFILES; do
  run pmcs-$prof $OUT/elf/su/$t.elf $OUT/SA/$t-$prof-p +expect-csr=24:3; run m-$prof $OUT/elf/su/$t.elf $OUT/SA/$t-$prof-m +expect-csr=24:3
  echo "  $t $prof: pipeline exit $(cat $OUT/SA/$t-$prof-p.exit) errors $(errs $OUT/SA/$t-$prof-p.log) | multicycle exit $(cat $OUT/SA/$t-$prof-m.exit)" | tee -a $OUT/SA.txt
done; done

# ---------------------------------------------------------------- SB
echo "== SB: architectural differential (multicycle reference), programs without asynchronous events" | tee $OUT/SB.txt
for t in su01_modes su03_deleg su04_strap su07_epc_len su10_wfi su08_satp_bare su09_warl su11_mip_sw; do for prof in $PROFILES; do
  strict="--require-complete"; case $t in su08_satp_bare|su09_warl|su11_mip_sw) strict="";; esac   # the baseline three
  r=$(python3 $SC/p1diff.py $strict $OUT/SA/$t-$prof-m $OUT/SA/$t-$prof-p)
  echo "  $t $prof ${strict:-(baseline failure: equality only)}: $r" | tee -a $OUT/SB.txt
done; done

# ---------------------------------------------------------------- SC
echo "== SC: an M-level interrupt at every position across M -> S -> U -> M (independent checks, then alignment)" | tee $OUT/SC.txt
run pmcs-min $OUT/elf/p2b_irq_priv.elf $OUT/SC/noirq
sb=$(awk '$3=="s_blk"{print $1}' $OUT/elf/p2b_irq_priv.sym); ue=$(awk '$3=="u_end"{print $1}' $OUT/elf/p2b_irq_priv.sym)
# s_blk: its first retirement; u_end: the U-mode ECALL, which traps instead of retiring -- the number of retirements
# before its trap record
read si ui < <(awk -v s=$sb -v u=$ue '/^CMT/{n++; if (match($0,/pc=[0-9a-f]+/)) {p=substr($0,RSTART+3,RLENGTH-3); if (p==s && !a) a=n}} /^TRP/{ if (match($0,/epc=[0-9a-f]+/)) { e=substr($0,RSTART+4,RLENGTH-4); if (e==u && !b) b=n } } END{print a+0, b+0}' $OUT/SC/noirq.log)
[ "$si" -gt 0 ] && [ "$ui" -gt "$si" ] || { echo "  SC: could not locate the S block ($si) and the U ecall ($ui)" | tee -a $OUT/SC.txt; }
echo "  without an interrupt: exit $(cat $OUT/SC/noirq.exit) (check 2 expected: the test requires its interrupt); s_blk at retirement $si, the U ecall after $ui retirements" | tee -a $OUT/SC.txt
cok=0; cfail=0; aok=0; anon=0
# from before the drop to S to six retirements before the U ecall (the interrupt latency is a few cycles); later than
# that the hart is back in M with MIE = 0 and the interrupt is, correctly, never taken
for n in $(seq $((si - 8)) 2 $((ui - 6))); do for prof in $PROFILES; do
  pre=$OUT/SC/irq-$n-$prof; run pmcs-$prof $OUT/elf/p2b_irq_priv.elf $pre-p +irq-at-retire=$n
  ec=$(cat $pre-p.exit); e=$(errs $pre-p.log); ni=$(grep -c '^TRP.*irq=1' $pre-p.log); lat=$(grep -oE 'max=[0-9]+' $pre-p.log | cut -d= -f2)
  k=$(awk '/^TRP.*irq=1/{print n; exit} /^CMT/{n++}' n=0 $pre-p.log)
  if [ "$ec" = 0 ] && [ "$e" = 0 ] && [ "$ni" = 1 ]; then st=PASS; cok=$((cok+1)); else st="FAIL(exit $ec, errors $e, interrupts $ni)"; cfail=$((cfail+1)); fi
  al="not-aligned"
  if [ -n "$k" ]; then for d in 0 -1 1 -2 2 -3 3 -4 4; do np=$((k + d)); [ $np -ge 1 ] || continue
    run m-$prof $OUT/elf/p2b_irq_priv.elf $pre-m +irq-at-retire=$np
    km=$(awk '/^TRP.*irq=1/{print n; exit} /^CMT/{n++}' n=0 $pre-m.log)
    if [ "$km" = "$k" ]; then r=$(python3 $SC/p1diff.py --require-complete $pre-m $pre-p); [ $? = 0 ] && { al="aligned(N'=$np): $r"; aok=$((aok+1)); } || { al="aligned(N'=$np) BUT $r"; anon=$((anon+1)); }; break; fi
  done; fi
  [ "$al" = not-aligned ] && anon=$((anon+1))
  echo "  p2b_irq_priv N=$n $prof: $st k=$k interrupts=$ni max_latency=$lat | $al" | tee -a $OUT/SC.txt
done; done
echo "  SC total: self-checks $cok PASS / $cfail FAIL; reference aligned and identical $aok, not aligned or different $anon" | tee -a $OUT/SC.txt

# ---------------------------------------------------------------- SD
echo "== SD: the CPU-SU fault injections, each rejected by its named check (cpu-su/scripts/run-cpu-su.sh gate 3)" | tee $OUT/SD.txt
for impl in pmcs m; do
  run $impl-nodeleg $OUT/elf/su/su01_modes.elf $OUT/SD/nodeleg-$impl
  echo "  FAULT_NO_DELEG on $impl, su01: $(python3 $SC/mutjudge.py first $OUT/SD/nodeleg-$impl 'TOHOST code=11 ')" | tee -a $OUT/SD.txt
  run $impl-sirqm $OUT/elf/su/su05_irq_modes.elf $OUT/SD/sirqm-$impl
  echo "  FAULT_S_IRQ_IN_M on $impl, su05: $(python3 $SC/mutjudge.py first $OUT/SD/sirqm-$impl 'TOHOST code=14 ')" | tee -a $OUT/SD.txt
  run $impl-sretspp $OUT/elf/su/su03_deleg.elf $OUT/SD/sretspp-$impl
  echo "  FAULT_SRET_SPP on $impl, su03: $(python3 $SC/mutjudge.py first $OUT/SD/sretspp-$impl 'TOHOST code=1 ')" | tee -a $OUT/SD.txt
  for f in nodeleg sirqm sretspp; do run $impl-$f $OUT/elf/t01.elf $OUT/SD/ctl-$f-$impl
    echo "  control $impl-$f on t01: exit $(cat $OUT/SD/ctl-$f-$impl.exit), errors $(errs $OUT/SD/ctl-$f-$impl.log)" | tee -a $OUT/SD.txt; done
done

# ---------------------------------------------------------------- G
echo "== G: shared and multicycle sources compiled vs tag mc-v1-dual" | tee $OUT/G.txt
for f in $SIMS/src/rtl/*.v $SIMS/src/rtl/*.vh; do b=$(basename $f)
  t=$(git -C $W show mc-v1-dual:rtl/cpu/$b 2>/dev/null | sha256sum | cut -c1-16); c=$(sha256sum $f | cut -c1-16)
  [ "$t" = "$c" ] && echo "  unchanged $b $c" >> $OUT/G.txt || echo "  CHANGED $b tag=$t now=$c" | tee -a $OUT/G.txt
done
echo "  $(grep -c unchanged $OUT/G.txt) shared/multicycle RTL files byte-identical to the tag; $(grep -c CHANGED $OUT/G.txt) changed" | tee -a $OUT/G.txt
echo "== verdict" | tee $OUT/verdict.txt
python3 $SC2/p2bverdict.py $OUT | tee -a $OUT/verdict.txt; v=${PIPESTATUS[0]}
echo "RUN_P2B_DONE verdict_rc=$v"; exit $v
