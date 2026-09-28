#!/usr/bin/env bash
# MC-M1: experiments/teaching-cpu/cpu-a/scripts/run-cpu-a.sh with the cpu RTL directory as a parameter. The testbench ($WS/tb) and the programs are
# unchanged; only the RTL files and the include path point at the named directory.
#   run-cpu-a-rtl.sh <cpu-rtl-dir> <fresh outdir>
RTL=$(readlink -f "${1:?cpu rtl dir}"); shift
# CPU-A stage 2, core level: the A extension in the teaching core. One entry point -- build the programs,
# build each simulator configuration, run, and score with the independent checkers. A build failure, a
# timeout or a crash is infrastructure: it fails the entry point and can never stand in for a negative
# being detected. Every negative must be rejected by its own named check.
#   run-cpu-a.sh <outdir>
set -uo pipefail
cd /home/engineer/fpga
A=/home/engineer/fpga/experiments/teaching-cpu/cpu-a
WS=/home/engineer/fpga/teaching-cpu-work/cpu
P2=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests          # crt.S, link.ld, testmac.h
T2=$WS/tests2                                                          # thandler.S, ihandler.S, irqmac.h
SV=/home/engineer/fpga/experiments/teaching-cpu/cpu-sv39/tests         # sv_env.h
SU=/home/engineer/fpga/experiments/teaching-cpu/cpu-su-prep/tests      # su_env.h, handlers.S, crt.S, link.ld
OUT=$(readlink -f -m "${1:?outdir}"); [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p $OUT/elf $OUT/logs $OUT/sim
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
{ verilator --version; riscv64-unknown-elf-gcc --version | head -1; date -u +%FT%TZ; } > $OUT/tools.txt
(cd $A && sha256sum DESIGN.md tests/*.S scripts/*.py scripts/*.sh) > $OUT/sources.sha256
(cd $RTL && sha256sum *.v *.vh) >> $OUT/sources.sha256
(cd $WS/tb && sha256sum *.v *.cpp) >> $OUT/sources.sha256
infra=0; fails=0; n=0
CF="-mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -Wa,--fatal-warnings"
GCC=riscv64-unknown-elf-gcc

echo "== the test programs =="
build() { local n=$1 march=$2 ld=$3; shift 3
  $GCC -march=$march $CF -T $ld -o $OUT/elf/$n.elf "$@" 2> $OUT/elf/$n.buildlog || {
    echo "  INFRA build $n"; grep -v RWX $OUT/elf/$n.buildlog | head -3 | sed 's/^/      /'; infra=$((infra+1)); return 1; }
  riscv64-unknown-elf-nm $OUT/elf/$n.elf > $OUT/elf/$n.sym
  riscv64-unknown-elf-objdump -d -M no-aliases $OUT/elf/$n.elf > $OUT/elf/$n.dis
  echo "  built $n"; }
python3 $A/scripts/gen-a01.py $OUT/elf/a01_matrix.S > $OUT/logs/gen-a01.log
cmp -s $OUT/elf/a01_matrix.S $A/tests/a01_matrix.S || { echo "  INFRA: the generated a01 differs from the delivered one"; infra=$((infra+1)); }
build a01 rv64ia_zicsr      $P2/link.ld -I$P2            $P2/crt.S $A/tests/a01_matrix.S
build a02 rv64ia_zicsr      $P2/link.ld -I$P2 -I$T2      $P2/crt.S $T2/thandler.S $A/tests/a02_lrsc.S
build a03 rv64iac_zicsr     $SU/link.ld  -I$SV -I$SU     $SU/crt.S $SU/handlers.S $A/tests/a03_except.S
build a04 rv64ia_zicsr      $P2/link.ld -I$P2 -I$T2      $P2/crt.S $T2/ihandler.S $A/tests/a04_irq.S
[ $infra -eq 0 ] || { echo "CPU_A_DONE infra=$infra (builds)"; exit 1; }
(cd $OUT/elf && sha256sum *.elf) > $OUT/elf.sha256
sym() { grep -E " $2\$" $OUT/elf/$1.sym | awk '{print "0x"$1}'; }
A01_ALOG=$(sym a01 alog);  A01_NCASE=$(sym a01 ncase)
A02_ALOG=$(sym a02 alog);  A02_NCASE=$(sym a02 ncase); A02_RACE=$(sym a02 race)
A03_SLOT=$(sym a03 slot)
A04_SLOT=$(sym a04 slot);  A04_AMO=$(grep -E " the_amo\$" $OUT/elf/a04.sym | awk '{print "0x"$1}')

echo "== the simulator configurations =="
vbuild() { local name=$1; shift
  local d=$OUT/sim/$name
  verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED \
    --top-module TeachingTop -CFLAGS "-std=c++17 -O2" -Mdir $d -o tcpu_tb -GMISA_A=1 "$@" \
    -I$RTL $WS/tb/tcpu_top.v $WS/tb/tcpu_harness.v $RTL/tcpu_core.v $RTL/tcpu_regfile.v \
    $RTL/tcpu_csr.v $RTL/tcpu_muldiv.v $RTL/tcpu_cdecode.v $RTL/tcpu_ptw.v $WS/tb/tcpu_main.cpp \
    > $OUT/logs/build-$name.log 2>&1
  [ -x $d/tcpu_tb ] || { echo "  INFRA verilator $name"; grep -E "%Error" $OUT/logs/build-$name.log | head -2 | sed 's/^/      /'; infra=$((infra+1)); return 1; }
  sha256sum $d/tcpu_tb >> $OUT/sim.sha256; echo "  built $name"; }
# three memory timings for the matrix, a racing configuration, an interrupt configuration, the negatives
vbuild t0                                                                      # ready 0, response 1
vbuild t1 -GREADY_DELAY=2 -GRESP_DELAY=5
vbuild t2 -GRANDOM=1 -GSEED=7 -GREADY_DELAY=3 -GRESP_DELAY=4
vbuild race -GEXT_POINT=2 -GEXT_TIMES=2 -GEXT_ADDR=$A02_RACE -GEXT_DATA=0x00000000000AA000 -GREADY_DELAY=2 -GRESP_DELAY=3
vbuild irq  -GIRQ_POINT=12 -GIRQ_LINE=1 -GIRQ_TIMES=1 -GIRQ_NEED_ENABLED=1 -GRESP_DELAY=6
for f in FAULT_A_W_NOSEXT FAULT_A_SC_RESULT FAULT_A_AMO_AS_LOAD FAULT_A_EARLY_RETIRE FAULT_A_NO_RESV_CLEAR; do
  vbuild neg-$f -G$f=1
done
[ $infra -eq 0 ] || { echo "CPU_A_DONE infra=$infra (verilator)"; exit 1; }

run() {  # run <sim> <test> <tag> [extra sim args...]; the per-test artifacts a checker needs are always produced
  local sim=$1 test=$2 tag=$3; shift 3
  local extra=()
  case $test in
    a01) extra=(+commit-trace=$OUT/logs/$tag.commit +mem-dump=$A01_NCASE:900:$OUT/logs/$tag.mem) ;;
    a02) extra=(+mem-dump=$A02_NCASE:80:$OUT/logs/$tag.mem) ;;
    a04) extra=(+commit-trace=$OUT/logs/$tag.commit +target-addr=$A04_SLOT) ;;
  esac
  timeout 900 $OUT/sim/$sim/tcpu_tb +elf=$OUT/elf/$test.elf +max-cycles=800000 "${extra[@]}" "$@" > $OUT/logs/$tag.log 2>&1
  local ec=$?; echo $ec > $OUT/logs/$tag.exit
  if [ $ec -eq 124 ]; then echo "  INFRA $tag timed out"; infra=$((infra+1)); return 99; fi
  return $ec; }
score() { local tag=$1 rc=$2; shift 2; n=$((n+1))
  "$@" > $OUT/logs/$tag.score 2>&1; local sc=$?
  printf "  %-26s sim=%-3s score=%s  %s\n" "$tag" "$rc" "$sc" "$(head -1 $OUT/logs/$tag.score | cut -c1-110)"
  # a positive is only a pass when the process itself exited 0 *and* the checker agrees; the checker is
  # given the exit code and the log so the completion signature and the monitors are checked too
  if [ "$rc" != 0 ]; then echo "      -> the simulator exited $rc"; fails=$((fails+1)); fi
  [ $sc -eq 0 ] || { fails=$((fails+1)); grep FAIL $OUT/logs/$tag.score | head -2 | sed 's/^/      /'; }; }

echo "== the instruction matrix, three memory timings =="
for t in t0 t1 t2; do
  run $t a01 a01-$t; rc=$?
  [ $rc = 99 ] && continue
  score a01-$t $rc python3 $A/scripts/check-a01.py $OUT/logs/a01-$t.commit $OUT/logs/a01-$t.mem $A01_ALOG $A01_NCASE --expect 138 --rc $rc --log $OUT/logs/a01-$t.log
done
echo "== the reservation, quiet and under an external race =="
for t in t0 t1 t2; do
  run $t a02 a02-$t; rc=$?
  [ $rc = 99 ] && continue
  score a02-$t $rc python3 $A/scripts/check-a02.py $OUT/logs/a02-$t.log $OUT/logs/a02-$t.mem $A02_ALOG $A02_NCASE --rc $rc --log $OUT/logs/a02-$t.log
done
run race a02 a02-race; rc=$?
[ $rc != 99 ] && score a02-race $rc python3 $A/scripts/check-a02.py $OUT/logs/a02-race.log $OUT/logs/a02-race.mem \
    $A02_ALOG $A02_NCASE --expect-ext-race 1 --case13-word 0xAA001 --rc $rc --log $OUT/logs/a02-race.log
echo "== exceptions: alignment, access, illegal encodings, Sv39 permission classes =="
for t in t0 t1; do
  run $t a03 a03-$t; rc=$?
  [ $rc = 99 ] && continue
  score a03-$t $rc python3 $A/scripts/check-a03.py $OUT/logs/a03-$t.log $rc $A03_SLOT
done
echo "== an interrupt inside an AMO =="
run irq a04 a04-irq; rc=$?
[ $rc != 99 ] && score a04-irq $rc python3 $A/scripts/check-a04.py $OUT/logs/a04-irq.log $OUT/logs/a04-irq.commit $rc $A04_AMO $A04_SLOT

echo "== the runner's own rule: a clean-looking data set with a non-zero exit must be refused =="
st_out=$(python3 $A/scripts/check-a01.py $OUT/logs/a01-t0.commit $OUT/logs/a01-t0.mem $A01_ALOG $A01_NCASE \
         --expect 138 --rc 3 --log $OUT/logs/a01-t0.log 2>&1); st_rc=$?
n=$((n+1))
if [ $st_rc -ne 0 ] && echo "$st_out" | grep -q "a positive run must exit 0"; then
  echo "  exit-code self-test        refused, as it must: $(echo "$st_out" | grep -m1 'must exit 0' | cut -c1-70)"
else
  echo "  exit-code self-test        NOT refused: the runner would accept a failed process with good data"
  fails=$((fails+1))
fi
# and the same for a missing completion signature
st2=$(python3 $A/scripts/check-a02.py $OUT/logs/a02-t0.log $OUT/logs/a02-t0.mem $A02_ALOG $A02_NCASE \
      --rc 0 --log /dev/null 2>&1); st2_rc=$?
n=$((n+1))
if [ $st2_rc -ne 0 ] && echo "$st2" | grep -q "no \"TOHOST code=0\""; then
  echo "  completion self-test       refused, as it must"
else
  echo "  completion self-test       NOT refused: a run without a completion signature would pass"
  fails=$((fails+1))
fi

echo "== the negatives: each must be rejected by its own named check =="
neg() {  # neg <fault> <test> <signature> <checker args...>
  local f=$1 test=$2 sig=$3; shift 3; n=$((n+1))
  run neg-$f $test neg-$f; local rc=$?
  [ $rc = 99 ] && return
  "$@" > $OUT/logs/neg-$f.score 2>&1
  if grep -qE "$sig" $OUT/logs/neg-$f.score $OUT/logs/neg-$f.log; then
    printf "  %-26s rejected: %s\n" "neg-$f" "$(grep -hm1 -E "$sig" $OUT/logs/neg-$f.score $OUT/logs/neg-$f.log | cut -c1-100)"
  else
    printf "  %-26s NOT rejected by its named check (%s)\n" "neg-$f" "$sig"; fails=$((fails+1)); fi; }
neg FAULT_A_W_NOSEXT a01 "the instruction's inputs give 0xffffffff" \
    python3 $A/scripts/check-a01.py $OUT/logs/neg-FAULT_A_W_NOSEXT.commit $OUT/logs/neg-FAULT_A_W_NOSEXT.mem $A01_ALOG $A01_NCASE --expect 138
neg FAULT_A_SC_RESULT a02 "the SC returned 0, the rule says 1" \
    python3 $A/scripts/check-a02.py $OUT/logs/neg-FAULT_A_SC_RESULT.log $OUT/logs/neg-FAULT_A_SC_RESULT.mem $A02_ALOG $A02_NCASE
neg FAULT_A_NO_RESV_CLEAR a02 "a trap between the LR and the SC drops it" \
    python3 $A/scripts/check-a02.py $OUT/logs/neg-FAULT_A_NO_RESV_CLEAR.log $OUT/logs/neg-FAULT_A_NO_RESV_CLEAR.mem $A02_ALOG $A02_NCASE
neg FAULT_A_AMO_AS_LOAD a01 "the instruction's inputs give" \
    python3 $A/scripts/check-a01.py $OUT/logs/neg-FAULT_A_AMO_AS_LOAD.commit $OUT/logs/neg-FAULT_A_AMO_AS_LOAD.mem $A01_ALOG $A01_NCASE --expect 138
neg FAULT_A_EARLY_RETIRE a01 "A_OBS_FAIL early-retire" true
echo "CPU_A_DONE scenarios=$n infra=$infra fails=$fails"
[ $infra -eq 0 ] && [ $fails -eq 0 ]
