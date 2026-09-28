#!/usr/bin/env bash
# MC-M1: experiments/teaching-cpu/cpu-m/scripts/run-cpu-m.sh with the cpu RTL directory as a parameter. The testbench ($WS/tb) and the programs are
# unchanged; only the RTL files and the include path point at the named directory.
#   run-cpu-m-rtl.sh <cpu-rtl-dir> <fresh outdir>
RTL=$(readlink -f "${1:?cpu rtl dir}"); shift
# CPU-M core-level gates 2-4, plus the existing M2-3 regression re-run with the one recorded expectation change.
#   run-cpu-m.sh <outdir>
set -u; cd /home/engineer/fpga
WS=/home/engineer/fpga/teaching-cpu-work/cpu; PREP=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests
CM=/home/engineer/fpga/experiments/teaching-cpu/cpu-m
OUT=${1:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT/logs $OUT/elf $OUT/rtl
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
cp $RTL/*.v $RTL/*.vh $WS/tb/*.v $WS/tb/*.cpp $OUT/rtl/; (cd $OUT/rtl && sha256sum *) > $OUT/source.sha256
{ verilator --version; riscv64-unknown-elf-gcc --version | head -n 1; date -u +%FT%TZ; } > $OUT/tools.txt
CC=riscv64-unknown-elf-gcc
CF="-mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -Wa,--fatal-warnings -I$PREP -I$WS/tests2"
python3 $CM/tests/gen_m01.py $OUT/elf/m01_muldiv.S --fault-codes > $OUT/elf/gen_m01.log
$CC -march=rv64im_zicsr $CF -T $PREP/link.ld -o $OUT/elf/m01.elf $PREP/crt.S $OUT/elf/m01_muldiv.S 2> $OUT/elf/m01.buildlog || { echo "BUILD FAIL m01"; exit 3; }
$CC -march=rv64im_zicsr $CF -T $PREP/link.ld -o $OUT/elf/m02.elf $PREP/crt.S $WS/tests2/ihandler.S $CM/tests/m02_irq_muldiv.S 2> $OUT/elf/m02.buildlog || { echo "BUILD FAIL m02"; grep -v RWX $OUT/elf/m02.buildlog | head -n 3; exit 3; }
$CC -march=rv64i_zicsr $CF -T $PREP/link.ld -o $OUT/elf/t01.elf $PREP/crt.S $PREP/t01_alu.S 2>/dev/null || { echo "BUILD FAIL t01"; exit 3; }
(cd $OUT/elf && sha256sum *.elf) > $OUT/elf.sha256
for e in m01 m02; do riscv64-unknown-elf-objdump -d -M no-aliases $OUT/elf/$e.elf > $OUT/elf/$e.dis; done
echo "M instructions in m01: $(grep -cE '\b(mul|mulh|mulhsu|mulhu|div|divu|rem|remu|mulw|divw|divuw|remw|remuw)\b' $OUT/elf/m01.dis)"

build() {  # build <name> <-G...>
  local n=$1; shift
  verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED \
    --top-module TeachingTop -CFLAGS "-std=c++17 -O2" -Mdir $OUT/obj_$n -o tcpu_tb "$@" \
    -I$RTL $WS/tb/tcpu_top.v $WS/tb/tcpu_harness.v $RTL/tcpu_core.v $RTL/tcpu_regfile.v \
    $RTL/tcpu_csr.v $RTL/tcpu_muldiv.v $WS/tb/tcpu_main.cpp > $OUT/logs/build-$n.log 2>&1 \
    || { echo "SIM BUILD FAIL $n"; tail -n 5 $OUT/logs/build-$n.log; exit 3; }
  sha256sum $OUT/obj_$n/tcpu_tb >> $OUT/sim.sha256
}
build min; build fixed -GREADY_DELAY=2 -GRESP_DELAY=5; build random -GRANDOM=1 -GSEED=12345
build irq-muldiv -GIRQ_POINT=8 -GIRQ_LINE=1 -GIRQ_TIMES=2 -GIRQ_ARM_REQUIRED=1
build irq-muldiv-slow -GIRQ_POINT=8 -GIRQ_LINE=1 -GIRQ_TIMES=2 -GIRQ_ARM_REQUIRED=1 -GREADY_DELAY=2 -GRESP_DELAY=8
build fault-wsext -GFAULT_W_SEXT=1; build fault-mulhsign -GFAULT_MULH_SIGN=1
fails=0
run() {  # run <cfg> <elf> <want exit|nz> <label> [args]
  local cfg=$1 elf=$2 want=$3 label=$4; shift 4
  timeout 600 $OUT/obj_$cfg/tcpu_tb +elf=$OUT/elf/$elf.elf +max-cycles=4000000 "$@" > $OUT/logs/$label.log 2>&1
  local ec=$?; echo $ec > $OUT/logs/$label.exit
  local perr; perr=$(grep -c "PROTO ERROR" $OUT/logs/$label.log); local st=ok
  if [ "$want" = nz ]; then [ "$ec" != 0 ] || st="UNEXPECTED exit 0"; else [ "$ec" = "$want" ] || st="UNEXPECTED exit=$ec want=$want"; fi
  [ "$perr" = 0 ] || st="$st PROTO_ERRORS=$perr"
  printf "  %-24s exit=%-3s want=%-3s %s\n" "$label" "$ec" "$want" "$(grep -oE 'TOHOST code=[0-9]+|IRQ hits=[0-9]+ fires=[0-9]+|FIRE cycle=[0-9]+ pc=0x[0-9a-f]+ state=[A-Z_]+|INTERRUPT COUNT (OK|FAIL)|IRQ COVERAGE (OK|FAIL)|TIMEOUT' $OUT/logs/$label.log | tr '\n' ' ')"
  [ "$st" = ok ] || { echo "      -> $st"; return 1; }; return 0
}
echo "== gate 2: all 13 operations, overlap, x0, chain, misa -- three timing profiles, zero protocol errors =="
for cfg in min fixed random; do run $cfg m01 0 "m01-$cfg" +commit-trace=$OUT/logs/m01-$cfg.commits || fails=$((fails+1)); done
if cmp -s $OUT/logs/m01-min.commits $OUT/logs/m01-fixed.commits && cmp -s $OUT/logs/m01-min.commits $OUT/logs/m01-random.commits; then
  echo "  commit records (pc/insn/rd/value) identical across the three profiles: $(grep -vc '^#' $OUT/logs/m01-min.commits) records"
else echo "  commit records differ across profiles"; fails=$((fails+1)); fi
echo "== gate 3: a persistent IRQ during a multiply and during a divide =="
for cfg in irq-muldiv irq-muldiv-slow; do
  run $cfg m02 0 "m02-$cfg" +expect-interrupts=2 +expect-cause=7 +min-irq-hits=2 || fails=$((fails+1))
  grep -q "FIRE cycle=.* state=MUL" $OUT/logs/m02-$cfg.log && echo "      -> the line was raised while the core was in S_MUL" \
    || { echo "      -> the injection did not land in S_MUL"; fails=$((fails+1)); }
done
echo "== gate 3b: a core reset applied while a multiply, then while a divide, is in progress =="
# The reset covers the core and the unit (bd_core_rst); the memory model keeps its contents. Required by the
# main's own check: the reset lands in S_MUL on the named family, nothing commits before the reset vector,
# the interrupted instruction retires in the re-run, and the program still ends with exit 0.
for fam in mul div; do
  run min m01 0 "corereset-$fam" +core-reset-at-op=$fam +core-reset-n=3 || fails=$((fails+1))
  grep -oE "CORE RESET cycle=[0-9]+ pc=0x[0-9a-f]+ insn=0x[0-9a-f]+ state=MUL family=$fam[^\n]*|CORE-RESET (OK|FAIL)[^\n]*" $OUT/logs/corereset-$fam.log | sed 's/^/      /'
  grep -q "CORE-RESET OK" $OUT/logs/corereset-$fam.log || { echo "      -> the core-reset evidence is missing"; fails=$((fails+1)); }
done

echo "== gate 4: named negatives rejected by their own result checks; controls still pass =="
# The expected check numbers are looked up in the generated program rather than typed: the first MULW check
# and the first MULH check in m01_muldiv.S. If the generator's ordering changes, the numbers follow it.
# The generator applies each fault's model to its own reference and reports the first check that would
# reject it -- so the expected code is derived from the same source as the expectations, not typed.
WSEXT_CODE=$(grep -oE "FAULT_CODES wsext=[0-9]+" $OUT/elf/gen_m01.log | grep -oE "[0-9]+$")
MULH_CODE=$(grep -oE "mulhsign=[0-9]+" $OUT/elf/gen_m01.log | grep -oE "[0-9]+$")
echo "  expected rejections (derived by gen_m01.py): FAULT_W_SEXT -> check $WSEXT_CODE, FAULT_MULH_SIGN -> check $MULH_CODE"
run fault-wsext    m01 $WSEXT_CODE "neg-wsext-m01"    || fails=$((fails+1))
run fault-mulhsign m01 $MULH_CODE  "neg-mulhsign-m01" || fails=$((fails+1))
run fault-wsext    t01 0 "ctl-wsext-t01"    || fails=$((fails+1))
run fault-mulhsign t01 0 "ctl-mulhsign-t01" || fails=$((fails+1))
echo "== gate 4: the existing I/CSR/exception/interrupt regression on the M core (run-m23-with-m.sh) =="
# one runner for this, the one that was fixed: the earlier inline splice in this file produced a script
# without the unit's source file (core-run1/logs/m23.log records that build failure) and never patched the
# program's own misa expectation. Kept as evidence; not maintained as a second variant.
bash $CM/scripts/run-m23-with-m.sh $OUT/m23 > $OUT/logs/m23.log 2>&1; m23=$?
grep -E "recorded changes|M2_3_DONE|M23_WITH_M_DONE|attempt" $OUT/logs/m23.log | sed 's/^/  /'
[ $m23 = 0 ] || { echo "  M2-3 regression on the M core FAILED (exit $m23)"; fails=$((fails+1)); }
echo "CPU_M_DONE fails=$fails"; [ $fails -eq 0 ]
