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
# Checkpoint 2 (Sv39) sections:
#   VA  the CPU-SV39 tests sv01..sv06, sv09 on both cores, 3 profiles (priv = M, satp = 0 at exit); the faulting
#       instructions of sv03 / sv09 never retire (commit counts, as cpu-sv39 gates 1b/1c)
#   VB  architectural differential: the Sv39 tests, p2b_walk_preempt, and generated M+C programs whose body runs in
#       S-mode under Sv39 (4 KiB-mapped code, a 12-page data alias, random sfence.vma), 3 profiles
#   VC  an M interrupt raised at EVERY CYCLE of an S-mode block full of data walks (p2b_irq_walk; replaces sv07's
#       state-aimed injection): independent checks, alignment; how many raises found a PTE read outstanding
#   VD  negatives: knobs 21 (TLB not flushed), 22 (hit skips the permission check), 23 (drain ignores the walker);
#       the CPU-SV39 injections on both cores (PPN truncation, second parcel untranslated, walker without permission
#       checks -- the last is not observable on the pipeline by construction, see REPORT)
#   VE  Sv39 coverage (PIPE COVERAGE-SV39, summed over VB): fetch and data walks, preemption, aborts, killed PTE reads
#   G   shared / multicycle sources unchanged against the tag
set -u
SIMS=${1:?sims dir}; OUT=${2:?outdir}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
W=/home/engineer/fpga/worktrees/pipe-single; P1=$W/experiments/pipeline/p1; P2=$W/experiments/pipeline/p2b
SC=$P1/scripts; SC2=$P2/scripts; T2=$P2/tests
SUP=/home/engineer/fpga/experiments/teaching-cpu/cpu-su-prep; SUT=$SUP/tests; PREP=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests
mkdir -p $OUT/elf $OUT/SA $OUT/SB $OUT/SC $OUT/SD $OUT/VA $OUT/VB $OUT/VC $OUT/VD
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
S() { echo "$SIMS/sims/$1/tcpu_tb"; }
# ---------------------------------------------------------------- programs
bash $SUP/scripts/build.sh $OUT/elf/su > $OUT/elf/su-build.log 2>&1 || { echo "SU TEST BUILD FAIL"; tail -3 $OUT/elf/su-build.log; exit 3; }
GCC="riscv64-unknown-elf-gcc -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wa,--fatal-warnings"
$GCC -march=rv64imc_zicsr -I$SUT -T $SUT/link.ld -o $OUT/elf/p2b_irq_priv.elf $SUT/crt.S $SUT/handlers.S $T2/p2b_irq_priv.S > $OUT/elf/p2b_irq_priv.cc.log 2>&1 || { echo "CC FAIL p2b_irq_priv"; exit 3; }
riscv64-unknown-elf-nm $OUT/elf/p2b_irq_priv.elf > $OUT/elf/p2b_irq_priv.sym
$GCC -march=rv64i_zicsr -I$PREP -T $PREP/link.ld -o $OUT/elf/t01.elf $PREP/crt.S $PREP/t01_alu.S > /dev/null 2>&1 || { echo "CC FAIL t01"; exit 3; }
bash /home/engineer/fpga/experiments/teaching-cpu/cpu-sv39/scripts/build.sh $OUT/elf/sv > $OUT/elf/sv-build.log 2>&1 || { echo "SV TEST BUILD FAIL"; tail -3 $OUT/elf/sv-build.log; exit 3; }
SVT=/home/engineer/fpga/experiments/teaching-cpu/cpu-sv39/tests
for t in p2b_irq_walk p2b_walk_preempt; do
  $GCC -march=rv64imc_zicsr -I$SVT -I$SUT -T $SUT/link.ld -o $OUT/elf/$t.elf $SUT/crt.S $SUT/handlers.S $T2/$t.S > $OUT/elf/$t.cc.log 2>&1 || { echo "CC FAIL $t"; exit 3; }
  riscv64-unknown-elf-nm $OUT/elf/$t.elf > $OUT/elf/$t.sym; done
NSV=20; T1=$P1/tests
for s in $(seq 1 $NSV); do python3 $W/experiments/pipeline/p2a/scripts/gen-hazard-p2a.py $s 400 --m --c --sv > $OUT/elf/hzsv$s.S
  $GCC -march=rv64imc_zicsr_zifencei -I$PREP -I$T1 -T $PREP/link.ld -o $OUT/elf/hzsv$s.elf $T1/p1crt.S $OUT/elf/hzsv$s.S > $OUT/elf/hzsv$s.cc.log 2>&1 || { echo "CC FAIL hzsv$s"; exit 3; }; done
(cd $OUT/elf && sha256sum su/*.elf sv/*.elf *.elf) > $OUT/elf.sha256
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

# ---------------------------------------------------------------- VA
SV="sv01_bare_sv39 sv02_pages sv03_perms sv04_bad_pte sv05_straddle sv06_switch sv09_nonleaf"
echo "== VA: CPU-SV39 tests on both cores (priv = M and satp = 0 at exit)" | tee $OUT/VA.txt
for t in $SV; do for prof in $PROFILES; do
  run pmcs-$prof $OUT/elf/sv/$t.elf $OUT/VA/$t-$prof-p +expect-csr=24:3 +expect-csr=21:0; run m-$prof $OUT/elf/sv/$t.elf $OUT/VA/$t-$prof-m +expect-csr=24:3 +expect-csr=21:0
  echo "  $t $prof: pipeline exit $(cat $OUT/VA/$t-$prof-p.exit) errors $(errs $OUT/VA/$t-$prof-p.log) | multicycle exit $(cat $OUT/VA/$t-$prof-m.exit)" | tee -a $OUT/VA.txt
done; done
svsym() { printf '%x' $((0x$(awk -v n="$2" '$3==n{print $1}' $OUT/elf/sv/$1.sym))); }
run pmcs-min $OUT/elf/sv/sv03_perms.elf $OUT/VA/sv03-noretire +expect-commit-count=$(svsym sv03_perms st_ro):0 +expect-commit-count=$(svsym sv03_perms ld_xo):0 \
  +expect-commit-count=$(svsym sv03_perms ld_upage):0 +expect-commit-count=$(svsym sv03_perms ld_spage):0 +expect-commit-count=$(svsym sv03_perms st_spage):0 \
  +expect-commit-count=$(svsym sv03_perms ld_mprv_u):0 +expect-commit-count=$(svsym sv03_perms jalr_upage):1
echo "  sv03 no-retire (pipeline): exit $(cat $OUT/VA/sv03-noretire.exit) $(grep -c 'COMMIT COUNT OK' $OUT/VA/sv03-noretire.log) commit-count checks OK, $(grep -c 'COMMIT COUNT FAIL' $OUT/VA/sv03-noretire.log) FAIL" | tee -a $OUT/VA.txt
run pmcs-min $OUT/elf/sv/sv09_nonleaf.elf $OUT/VA/sv09-noretire +expect-commit-count=$(svsym sv09_nonleaf nl_ld):0 +expect-commit-count=$(svsym sv09_nonleaf nl_st):0 +expect-commit-count=$(svsym sv09_nonleaf nl_j):6
echo "  sv09 no-retire (pipeline): exit $(cat $OUT/VA/sv09-noretire.exit) $(grep -c 'COMMIT COUNT OK' $OUT/VA/sv09-noretire.log) commit-count checks OK, $(grep -c 'COMMIT COUNT FAIL' $OUT/VA/sv09-noretire.log) FAIL" | tee -a $OUT/VA.txt

# ---------------------------------------------------------------- VB
echo "== VB: architectural differential under Sv39 (PTE reads excluded by owner, not by fetch = 0)" | tee $OUT/VB.txt
for prof in $PROFILES; do
  for t in $SV; do r=$(python3 $SC/p1diff.py --require-complete $OUT/VA/$t-$prof-m $OUT/VA/$t-$prof-p); echo "  $t $prof: $r" | tee -a $OUT/VB.txt; done
  for t in p2b_walk_preempt $(for s in $(seq 1 $NSV); do echo hzsv$s; done); do
    run m-$prof $OUT/elf/$t.elf $OUT/VB/$t-$prof-m; run pmcs-$prof $OUT/elf/$t.elf $OUT/VB/$t-$prof-p
    r=$(python3 $SC/p1diff.py --require-complete $OUT/VB/$t-$prof-m $OUT/VB/$t-$prof-p); echo "  $t $prof: $r" | tee -a $OUT/VB.txt
  done
done

# ---------------------------------------------------------------- VC
echo "== VC: an M interrupt at every cycle of an S-mode block of data walks (independent checks, then alignment)" | tee $OUT/VC.txt
run pmcs-min $OUT/elf/p2b_irq_walk.elf $OUT/VC/noirq
sb=$(awk '$3=="s_blk"{print $1}' $OUT/elf/p2b_irq_walk.sym); ue=$(awk '$3=="u_ecall"{print $1}' $OUT/elf/p2b_irq_walk.sym)
read c0 c1 < <(awk -v s=$sb -v u=$ue '/^CMT/{if (match($0,/pc=[0-9a-f]+/)) {p=substr($0,RSTART+3,RLENGTH-3); split($2,a,"="); if (p==s && !x) x=a[2]}} /^TRP/{ if (match($0,/epc=[0-9a-f]+/)) { e=substr($0,RSTART+4,RLENGTH-4); split($2,a,"="); if (e==u && !y) y=a[2] } } END{print x+0, y+0}' $OUT/VC/noirq.log)
echo "  without an interrupt: exit $(cat $OUT/VC/noirq.exit) (check 2 expected); the S block runs from cycle $c0, its ecall traps at cycle $c1 (min profile)" | tee -a $OUT/VC.txt
vok=0; vfail=0; val=0; vnon=0; during=0
for c in $(seq $((c0 - 10)) 1 $((c1 - 20))); do
  pre=$OUT/VC/c$c; run pmcs-min $OUT/elf/p2b_irq_walk.elf $pre-p +irq-at-cycle=$c
  ec=$(cat $pre-p.exit); e=$(errs $pre-p.log); ni=$(grep -c '^TRP.*irq=1' $pre-p.log)
  d=$(awk -v r=$c '/^PTE cyc=/{split($2,a,"="); last=a[2]} /^(CMT|DREQ|TRP) cyc=/{split($2,a,"="); if (last != "" && a[2] > last) { if (r > last && r <= a[2]) hit=1; last="" } } END{print hit+0}' $pre-p.log)
  during=$((during + d))
  k=$(awk '/^TRP.*irq=1/{print n; exit} /^CMT/{n++}' n=0 $pre-p.log)
  if [ "$ec" = 0 ] && [ "$e" = 0 ] && [ "$ni" = 1 ]; then st=PASS; vok=$((vok+1)); else st="FAIL(exit $ec, errors $e, interrupts $ni)"; vfail=$((vfail+1)); fi
  al="not-aligned"
  if [ -n "$k" ]; then for dd in 0 -1 1 -2 2 -3 3; do np=$((k + dd)); [ $np -ge 1 ] || continue
    run m-min $OUT/elf/p2b_irq_walk.elf $pre-m +irq-at-retire=$np
    km=$(awk '/^TRP.*irq=1/{print n; exit} /^CMT/{n++}' n=0 $pre-m.log)
    if [ "$km" = "$k" ]; then r=$(python3 $SC/p1diff.py --require-complete $pre-m $pre-p); [ $? = 0 ] && { al="aligned(N'=$np): $r"; val=$((val+1)); } || { al="aligned(N'=$np) BUT $r"; vnon=$((vnon+1)); }; break; fi
  done; fi
  [ "$al" = not-aligned ] && vnon=$((vnon+1))
  echo "  p2b_irq_walk cycle=$c: $st k=$k pte_outstanding_at_raise=$d | $al" >> $OUT/VC.txt
done
echo "  VC total: self-checks $vok PASS / $vfail FAIL; aligned and identical $val, not aligned or different $vnon; raised while a PTE read was outstanding: $during" | tee -a $OUT/VC.txt

# ---------------------------------------------------------------- VD
echo "== VD: Sv39 negative controls" | tee $OUT/VD.txt
run pmcs-fault21 $OUT/elf/sv/sv06_switch.elf $OUT/VD/fault21
echo "  knob 21 (TLB_NO_FLUSH) on sv06: $(python3 $SC/mutjudge.py first $OUT/VD/fault21 'TOHOST code=2 ')" | tee -a $OUT/VD.txt
run pmcs-fault22 $OUT/elf/sv/sv03_perms.elf $OUT/VD/fault22
echo "  knob 22 (TLB_HIT_NO_PERM) on sv03: $(python3 $SC/mutjudge.py first $OUT/VD/fault22 'TOHOST code=2 ')" | tee -a $OUT/VD.txt
run pmcs-fault23 $OUT/elf/sv/sv03_perms.elf $OUT/VD/fault23
echo "  knob 23 (DRAIN_NO_WALKER) on sv03: $(python3 $SC/mutjudge.py first $OUT/VD/fault23 'PIPE ASSERT drain')" | tee -a $OUT/VD.txt
for impl in pmcs m; do
  run $impl-trunc $OUT/elf/sv/sv04_bad_pte.elf $OUT/VD/trunc-$impl
  echo "  FAULT_PPN_TRUNC on $impl, sv04: $(python3 $SC/mutjudge.py first $OUT/VD/trunc-$impl 'TOHOST code=8 ')" | tee -a $OUT/VD.txt
done
run m-if2 $OUT/elf/sv/sv05_straddle.elf $OUT/VD/if2-m
echo "  FAULT_IF2_NO_XLATE on m, sv05: $(python3 $SC/mutjudge.py first $OUT/VD/if2-m 'TOHOST code=1 ')" | tee -a $OUT/VD.txt
# the pipeline takes the whole next word from the wrong page (the multicycle core only the parcel): the program
# goes astray differently, so the judgment is WHERE: the first retirement that differs from the uninjected
# reference must be the straddling instruction at 0x30002ffe
run pmcs-if2 $OUT/elf/sv/sv05_straddle.elf $OUT/VD/if2-p
r=$(python3 $SC/p1diff.py $OUT/VA/sv05_straddle-min-m $OUT/VD/if2-p)
echo "  FAULT_IF2_NO_XLATE on pmcs, sv05, against the uninjected reference: $r" | cut -c1-400 | tee -a $OUT/VD.txt
run m-noperm $OUT/elf/sv/sv03_perms.elf $OUT/VD/noperm-m
echo "  FAULT_PTW_NO_PERM on m, sv03: $(python3 $SC/mutjudge.py first $OUT/VD/noperm-m 'TOHOST code=5 ')" | tee -a $OUT/VD.txt
run pmcs-noperm $OUT/elf/sv/sv03_perms.elf $OUT/VD/noperm-p
echo "  FAULT_PTW_NO_PERM on pmcs, sv03 (masked by construction: every translation the pipeline uses is re-checked by tcpu_permcheck; knob 22 removes that check): exit $(cat $OUT/VD/noperm-p.exit), errors $(errs $OUT/VD/noperm-p.log)" | tee -a $OUT/VD.txt
for sim in pmcs-fault21 pmcs-fault22 pmcs-fault23 pmcs-noperm pmcs-if2 pmcs-trunc m-noperm m-if2 m-trunc; do run $sim $OUT/elf/t01.elf $OUT/VD/ctl-$sim
  echo "  control $sim on t01: exit $(cat $OUT/VD/ctl-$sim.exit), errors $(errs $OUT/VD/ctl-$sim.log)" | tee -a $OUT/VD.txt; done

# ---------------------------------------------------------------- VE
echo "== VE: Sv39 coverage on the pipeline, summed over VB (PIPE COVERAGE-SV39)" | tee $OUT/VE.txt
cat $OUT/VB/*-p.log | grep '^PIPE COVERAGE-SV39' | awk '{for (i = 3; i <= NF; i++) { split($i, a, "="); t[a[1]] += a[2] } } END { for (k in t) printf "  %s = %d\n", k, t[k] }' | sort | tee -a $OUT/VE.txt

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
