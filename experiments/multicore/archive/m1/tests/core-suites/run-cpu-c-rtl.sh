#!/usr/bin/env bash
# MC-M1: experiments/teaching-cpu/cpu-c/scripts/run-cpu-c.sh with the cpu RTL directory as a parameter. The testbench ($WS/tb) and the programs are
# unchanged; only the RTL files and the include path point at the named directory.
#   run-cpu-c-rtl.sh <cpu-rtl-dir> <fresh outdir>
RTL=$(readlink -f "${1:?cpu rtl dir}"); shift
# CPU-C core-level gates (2, 3, 4, 5-regression) in one run.   run-cpu-c.sh <outdir>
set -u; cd /home/engineer/fpga
WS=/home/engineer/fpga/teaching-cpu-work/cpu; PREP=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests
CM=/home/engineer/fpga/experiments/teaching-cpu/cpu-m; CC=/home/engineer/fpga/experiments/teaching-cpu/cpu-c
OUT=${1:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT/logs $OUT/elf $OUT/rtl
# CPU-SU: the misa the M programs expect and the M2-3 copy-runner to use (defaults = the CPU-C delivery)
MISA=${MISA:-0x8000000000001104}; M23=${M23:-$CC/scripts/run-m23-with-c.sh}; echo "misa expected $MISA; regression runner $M23"
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
cp $RTL/*.v $RTL/*.vh $WS/tb/*.v $WS/tb/*.cpp $OUT/rtl/; (cd $OUT/rtl && sha256sum *) > $OUT/source.sha256
{ verilator --version; riscv64-unknown-elf-gcc --version | head -n 1; date -u +%FT%TZ; } > $OUT/tools.txt
GCC=riscv64-unknown-elf-gcc
CF="-mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -Wa,--fatal-warnings -I$PREP -I$WS/tests2"
b() { local n=$1 arch=$2 ld=$3; shift 3
  $GCC -march=$arch $CF -T $ld -o $OUT/elf/$n.elf "$@" 2> $OUT/elf/$n.buildlog || { echo "BUILD FAIL $n"; grep -v RWX $OUT/elf/$n.buildlog | head -n 3; exit 3; }
  riscv64-unknown-elf-objdump -d -M no-aliases $OUT/elf/$n.elf > $OUT/elf/$n.dis; riscv64-unknown-elf-nm $OUT/elf/$n.elf > $OUT/elf/$n.sym; }
# c01 carries its own misa expectation (check 34): on a core with more extensions it is built from a copy
# with that one value changed, and the diff is recorded next to the ELF
C01=$CC/tests/c01_compressed.S
if [ "$MISA" != 0x8000000000001104 ]; then
  sed "s/misa_expect:.*0x8000000000001104/misa_expect: .dword $MISA/" $C01 > $OUT/elf/c01_compressed.S
  diff -u $C01 $OUT/elf/c01_compressed.S > $OUT/elf/c01_compressed.diff; C01=$OUT/elf/c01_compressed.S
  echo "c01 copy: $(grep -c '^[-+][^-+]' $OUT/elf/c01_compressed.diff) changed line(s) (misa), see elf/c01_compressed.diff"
fi
b c01 rv64imc_zicsr $PREP/link.ld $PREP/crt.S $C01
b c02 rv64imc_zicsr $CC/tests/link-c02.ld $PREP/crt.S $CC/tests/c02_boundary.S
python3 $CM/tests/gen_m01.py $OUT/elf/m01_muldiv.S --fault-codes --misa=$MISA > $OUT/elf/gen_m01.log
b m01 rv64im_zicsr $PREP/link.ld $PREP/crt.S $OUT/elf/m01_muldiv.S
b m02 rv64im_zicsr $PREP/link.ld $PREP/crt.S $WS/tests2/ihandler.S $CM/tests/m02_irq_muldiv.S
b i01 rv64i_zicsr $PREP/link.ld $PREP/crt.S $WS/tests2/ihandler.S $WS/tests2/i01_basic.S
b t01 rv64i_zicsr $PREP/link.ld $PREP/crt.S $PREP/t01_alu.S
(cd $OUT/elf && sha256sum *.elf) > $OUT/elf.sha256
sym() { awk -v n="$2" '$3==n{print $1}' $OUT/elf/$1.sym; }
STRADDLE=$(printf "%x" $((0x$(sym c02 straddle)))); BAD1=$(sym c02 bad1)
echo "straddle at 0x$STRADDLE; bad1 at 0x$BAD1"

build() { local n=$1; shift
  verilator --cc --exe --build -j 2 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED \
    --top-module TeachingTop -CFLAGS "-std=c++17 -O2" -Mdir $OUT/obj_$n -o tcpu_tb "$@" \
    -I$RTL $WS/tb/tcpu_top.v $WS/tb/tcpu_harness.v $RTL/tcpu_core.v $RTL/tcpu_regfile.v \
    $RTL/tcpu_csr.v $RTL/tcpu_muldiv.v $RTL/tcpu_cdecode.v $WS/tb/tcpu_main.cpp > $OUT/logs/build-$n.log 2>&1 \
    || { echo "SIM BUILD FAIL $n"; tail -n 5 $OUT/logs/build-$n.log; exit 3; }
  sha256sum $OUT/obj_$n/tcpu_tb >> $OUT/sim.sha256; }
build min; build fixed -GREADY_DELAY=2 -GRESP_DELAY=5; build random -GRANDOM=1 -GSEED=12345
build irq-if2req  -GIRQ_POINT=9  -GIRQ_LINE=1 -GIRQ_TIMES=1 -GREADY_DELAY=3 -GRESP_DELAY=4
build irq-if2resp -GIRQ_POINT=10 -GIRQ_LINE=1 -GIRQ_TIMES=1 -GRESP_DELAY=6
build fetcherr-first  -GFETCH_ERR_ADDR=0x$STRADDLE
build fetcherr-second -GFETCH_ERR_ADDR=0x$(printf '%x' $((0x$STRADDLE + 2)))
build fault-cimm -GFAULT_C_IMM=1; build fault-creg -GFAULT_C_REG=1
fails=0
run() { local cfg=$1 elf=$2 want=$3 label=$4; shift 4
  timeout 600 $OUT/obj_$cfg/tcpu_tb +elf=$OUT/elf/$elf.elf +max-cycles=4000000 "$@" > $OUT/logs/$label.log 2>&1
  local ec=$?; echo $ec > $OUT/logs/$label.exit
  local perr; perr=$(grep -c "PROTO ERROR" $OUT/logs/$label.log); local st=ok
  if [ "$want" = nz ]; then [ "$ec" != 0 ] || st="UNEXPECTED exit 0"; else [ "$ec" = "$want" ] || st="UNEXPECTED exit=$ec want=$want"; fi
  [ "$perr" = 0 ] || st="$st PROTO_ERRORS=$perr"
  printf "  %-24s exit=%-3s want=%-3s %s\n" "$label" "$ec" "$want" "$(grep -oE 'TOHOST code=[0-9]+|TRAPS=[0-9]+ last_cause=[0-9]+ last_epc=0x[0-9a-f]+ last_tval=0x[0-9a-f]+|IRQ hits=[0-9]+ fires=[0-9]+|FIRE cycle=[0-9]+ pc=0x[0-9a-f]+ state=[A-Z_0-9]+|INTERRUPT COUNT (OK|FAIL)|IRQ COVERAGE (OK|FAIL)|DIRECTED (OK|FAIL)[^,]*|CORE-RESET (OK|FAIL)|TIMEOUT' $OUT/logs/$label.log | tr '\n' ' ')"
  [ "$st" = ok ] || { echo "      -> $st"; return 1; }; return 0; }

echo "== gate 2: every integer C instruction, three timing profiles, commit records identical =="
for cfg in min fixed random; do run $cfg c01 0 "c01-$cfg" +commit-trace=$OUT/logs/c01-$cfg.commits || fails=$((fails+1)); done
cmp -s $OUT/logs/c01-min.commits $OUT/logs/c01-fixed.commits && cmp -s $OUT/logs/c01-min.commits $OUT/logs/c01-random.commits \
  && echo "  commit records (pc/insn/rd/value/len) identical across the three profiles: $(grep -vc '^#' $OUT/logs/c01-min.commits) records" \
  || { echo "  commit records differ across profiles"; fails=$((fails+1)); }
python3 $CC/scripts/check-c-coverage.py $OUT/logs/c01-min.commits $OUT/elf/c01.dis | sed 's/^/  /'; [ ${PIPESTATUS[0]} = 0 ] || fails=$((fails+1))
echo "== gate 2: the M programs on the C core (misa now I+M+C) =="
for cfg in min fixed random; do run $cfg m01 0 "m01-$cfg" || fails=$((fails+1)); done
echo "== gate 3: start positions, the 4 KiB straddle, illegal/reserved parcels, c.ebreak, mret to a halfword =="
run min c02 0 "c02-boundary" +commit-trace=$OUT/logs/c02.commits +expect-traps=3 || fails=$((fails+1))
python3 $CC/scripts/check-c-coverage.py $OUT/logs/c02.commits $OUT/elf/c02.dis --no-mnemonics --require-straddle=0x$STRADDLE | sed 's/^/  /'; [ ${PIPESTATUS[0]} = 0 ] || fails=$((fails+1))
echo "== gate 3: a fetch error on the first parcel, and on the second parcel, of the straddling instruction =="
# both belong to the instruction at `straddle`: mepc = straddle; mtval = the address that failed
run fetcherr-first  c02 4 "fetcherr-first"  +stop-at-trap +expect-cause=1 +expect-commit-count=0x$STRADDLE:0 +commit-trace=$OUT/logs/fetcherr-first.commits  || fails=$((fails+1))
run fetcherr-second c02 4 "fetcherr-second" +stop-at-trap +expect-cause=1 +expect-commit-count=0x$STRADDLE:0 +commit-trace=$OUT/logs/fetcherr-second.commits || fails=$((fails+1))
for l in fetcherr-first fetcherr-second; do
  epc=$(grep -oE "last_epc=0x[0-9a-f]+" $OUT/logs/$l.log | cut -d= -f2); tval=$(grep -oE "last_tval=0x[0-9a-f]+" $OUT/logs/$l.log | cut -d= -f2)
  want_tval=$([ $l = fetcherr-first ] && echo 0x$STRADDLE || printf '0x%x' $((0x$STRADDLE + 2)))
  [ "$epc" = "0x$STRADDLE" ] && [ "$tval" = "$want_tval" ] && echo "      -> mepc=$epc mtval=$tval as required" \
    || { echo "      -> mepc=$epc mtval=$tval, expected mepc=0x$STRADDLE mtval=$want_tval"; fails=$((fails+1)); }
  n=$(grep -c "^0x0*$STRADDLE " $OUT/logs/$l.commits); r=$(grep -vc '^#' $OUT/logs/$l.commits)
  grep -q "COMMIT COUNT OK: pc 0x$STRADDLE retired 0 times" $OUT/logs/$l.log && [ "$n" = 0 ] && [ "$r" -gt 0 ] \
    && echo "      -> $r retired before the trap, the faulting pc 0 times (commit trace and counter agree)" \
    || { echo "      -> retirement evidence incomplete ($r retired, faulting pc $n times)"; fails=$((fails+1)); }
done
echo "== gate 4: a persistent IRQ while the second parcel is requested / outstanding; core reset mid-fetch =="
# aimed (Codex review): the target is the instruction right after the first `csrrs ... mstatus` (MIE set) in
# i01 -- a 32-bit `lui t2,imm` -- so the injection lands with enabled=1 and the visible result is x7 = imm<<12
T=$(awk '/csrrs[[:space:]]+zero,mstatus/{getline; print; exit}' $OUT/elf/i01.dis)
TPC=$(echo "$T" | awk -F: '{print $1}' | tr -d ' '); TMN=$(echo "$T" | awk '{print $3}'); TARG=$(echo "$T" | awk '{print $4}')
[ "$TMN" = lui ] && [ "$(echo $TARG | cut -d, -f1)" = t2 ] || { echo "  target after MIE enable is not 'lui t2': '$T'"; exit 3; }
TVAL=$(printf '%x' $(( $(echo $TARG | cut -d, -f2) << 12 )))
echo "  target: pc=0x$TPC '$TMN $TARG' -> x7=0x$TVAL (derived from the disassembly)"
run irq-if2req  i01 0 "irq-if2req"  +inject-pc=$TPC +target-pc=$TPC +target-reg=7:$TVAL +expect-fire-state=IF2_REQ  +expect-interrupts=1 +expect-cause=7 +min-irq-hits=1 || fails=$((fails+1))
run irq-if2resp i01 0 "irq-if2resp" +inject-pc=$TPC +target-pc=$TPC +target-reg=7:$TVAL +expect-fire-state=IF2_WAIT +expect-interrupts=1 +expect-cause=7 +min-irq-hits=1 || fails=$((fails+1))
for l in irq-if2req irq-if2resp; do
  grep -q "FIRE STATE OK" $OUT/logs/$l.log && grep -q "CHAIN OK" $OUT/logs/$l.log && grep -q "enabled=1" $OUT/logs/$l.log \
    && [ "$(grep -oE 'first_irq_epc=0x[0-9a-f]+' $OUT/logs/$l.log | cut -d= -f2)" = "0x$(printf '%x' $((0x$TPC + 4)))" ] \
    && echo "      -> enabled=1, target retired once before the interrupt, x7 visible, mepc=target+4" \
    || { echo "      -> aimed-IRQ evidence incomplete in $l"; fails=$((fails+1)); }
done
# the reset lands while the second parcel is outstanding; with the slower profiles the memory answers after the
# restart, and the bridge model must swallow that answer (no spliced half)
for cfg in min fixed random; do
  run $cfg c01 0 "corereset-if2-c01-$cfg" +core-reset-at-op=if2 +core-reset-n=5 || fails=$((fails+1))
  run $cfg c02 0 "corereset-if2-c02-$cfg" +core-reset-at-op=if2 +core-reset-n=3 +expect-traps=3 || fails=$((fails+1))
  for l in corereset-if2-c01-$cfg corereset-if2-c02-$cfg; do grep -q "CORE-RESET OK" $OUT/logs/$l.log || { echo "      -> core-reset evidence missing in $l"; fails=$((fails+1)); }; done
done
echo "  stale responses discarded: $(grep -h "CORE-RESET OK" $OUT/logs/corereset-if2-*.log | grep -oE "model=[0-9]+" | tr "\n" " ")"
echo "== gate 1b/4: named negatives on the core =="
NCHK=$(awk '/^[[:space:]]*c\.addi4spn/{f=1} f && /CHECK_EQ_R\(/{match($0,/, *([0-9]+)\)/,m); print m[1]; exit}' $CC/tests/c01_compressed.S)
echo "  the faults must trip check $NCHK (the first check after c.addi4spn in c01's source); timeouts/build errors are not rejections"
run fault-cimm c01 $NCHK "neg-cimm-c01" || fails=$((fails+1))
run fault-creg c01 $NCHK "neg-creg-c01" || fails=$((fails+1))
run fault-cimm t01 0 "ctl-cimm-t01" || fails=$((fails+1)); run fault-creg t01 0 "ctl-creg-t01" || fails=$((fails+1))
echo "== gate 5: the IM/CSR/exception/interrupt regression on the C core (copies with recorded diffs) =="
bash $M23 $OUT/m23 > $OUT/logs/m23.log 2>&1; m23=$?
grep -E "recorded changes|M2_3_DONE|M23_WITH_C_DONE|M23_WITH_SU_DONE|attempt" $OUT/logs/m23.log | sed 's/^/  /'
[ $m23 = 0 ] || { echo "  regression FAILED (exit $m23)"; fails=$((fails+1)); }
echo "== gate 5: the CPU-M IRQ test on the C core =="
build irq-muldiv -GIRQ_POINT=8 -GIRQ_LINE=1 -GIRQ_TIMES=2 -GIRQ_ARM_REQUIRED=1
run irq-muldiv m02 0 "m02-irq-muldiv" +expect-interrupts=2 +expect-cause=7 +min-irq-hits=2 || fails=$((fails+1))
echo "CPU_C_DONE fails=$fails"; [ $fails -eq 0 ]
