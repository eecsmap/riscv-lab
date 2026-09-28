#!/usr/bin/env bash
# MC-M1: experiments/teaching-cpu/cpu-su/scripts/run-cpu-su.sh with the cpu RTL directory as a parameter. The testbench ($WS/tb) and the programs are
# unchanged; only the RTL files and the include path point at the named directory.
#   run-cpu-su-rtl.sh <cpu-rtl-dir> <fresh outdir>
RTL=$(readlink -f "${1:?cpu rtl dir}"); shift
# CPU-SU core-level gates in one run.   run-cpu-su.sh <outdir>
#   - builds the simulators (min / fixed / random; the aimed-injection configuration; the three named faults)
#   - builds the prep tests (su01-su12) from experiments/teaching-cpu/cpu-su-prep/tests (source hashed)
#   - su01-su12 under the three memory profiles, exit 0, no protocol errors, priv = M at exit (real CSR port);
#     commit records byte-identical across profiles for the programs without asynchronous events
#   - the aimed U-mode interrupt (su12) with enabled=1 and the retire/RF/mepc chain
#   - the three named negatives, each rejected by the specific check, with the RV64I control passing
set -u; cd /home/engineer/fpga
WS=/home/engineer/fpga/teaching-cpu-work/cpu; PREP=/home/engineer/fpga/experiments/teaching-cpu/cpu-su-prep
P2=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests
OUT=${1:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT/logs $OUT/rtl
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
cp $RTL/*.v $RTL/*.vh $WS/tb/*.v $WS/tb/*.cpp $OUT/rtl/; (cd $OUT/rtl && sha256sum *) > $OUT/source.sha256
{ verilator --version; riscv64-unknown-elf-gcc --version | head -n 1; date -u +%FT%TZ; } > $OUT/tools.txt
bash $PREP/scripts/build.sh $OUT/elf > $OUT/logs/build-tests.log 2>&1 || { echo "TEST BUILD FAIL"; tail -n 5 $OUT/logs/build-tests.log; exit 3; }
riscv64-unknown-elf-gcc -march=rv64i_zicsr -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -I$P2 -T $P2/link.ld -o $OUT/elf/t01.elf $P2/crt.S $P2/t01_alu.S 2>/dev/null
(cd $OUT/elf && sha256sum *.elf) > $OUT/elf.sha256
build() { local n=$1; shift
  verilator --cc --exe --build -j 2 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED \
    --top-module TeachingTop -CFLAGS "-std=c++17 -O2" -Mdir $OUT/obj_$n -o tcpu_tb "$@" \
    -I$RTL $WS/tb/tcpu_top.v $WS/tb/tcpu_harness.v $RTL/tcpu_core.v $RTL/tcpu_regfile.v \
    $RTL/tcpu_csr.v $RTL/tcpu_muldiv.v $RTL/tcpu_cdecode.v $WS/tb/tcpu_main.cpp > $OUT/logs/build-$n.log 2>&1 \
    || { echo "SIM BUILD FAIL $n"; tail -n 5 $OUT/logs/build-$n.log; exit 3; }
  sha256sum $OUT/obj_$n/tcpu_tb >> $OUT/sim.sha256; }
build min; build fixed -GREADY_DELAY=2 -GRESP_DELAY=5; build random -GRANDOM=1 -GSEED=12345
build aimed -GIRQ_POINT=2 -GIRQ_LINE=0 -GIRQ_TIMES=1 -GRESP_DELAY=3
build fault-nodeleg -GFAULT_NO_DELEG=1; build fault-sirqm -GFAULT_S_IRQ_IN_M=1; build fault-sretspp -GFAULT_SRET_SPP=1
fails=0
run() { local cfg=$1 elf=$2 want=$3 label=$4; shift 4
  timeout 900 $OUT/obj_$cfg/tcpu_tb +elf=$OUT/elf/$elf.elf +max-cycles=6000000 "$@" > $OUT/logs/$label.log 2>&1
  local ec=$?; echo $ec > $OUT/logs/$label.exit; local st=ok
  [ "$ec" = "$want" ] || st="UNEXPECTED exit=$ec want=$want"
  [ "$(grep -c 'PROTO ERROR' $OUT/logs/$label.log)" = 0 ] || st="$st PROTO_ERRORS"
  grep -qE "TIMEOUT|argument error|Internal Error|Thread Pool" $OUT/logs/$label.log && st="$st INFRA/TIMEOUT(not a result)"
  printf "  %-26s exit=%-3s want=%-3s %s\n" "$label" "$ec" "$want" "$(grep -oE 'TOHOST code=[0-9]+|TRAPS=[0-9]+|PRIV at exit=[0-9]|CSR CHECK (OK|FAIL)[^,]*|CHAIN (OK|FAIL)[^,]*|FIRE STATE (OK|FAIL)[^,]*|INTERRUPT COUNT (OK|FAIL)|TIMEOUT|TRAP STORM' $OUT/logs/$label.log | tr '\n' ' ')"
  [ "$st" = ok ] || { echo "      -> $st"; return 1; }; return 0; }
TESTS="su01_modes su02_csr_priv su03_deleg su04_strap su05_irq_modes su06_timer_ssip su07_epc_len su08_satp_bare su09_warl su10_wfi su11_mip_sw"
DETERMINISTIC="su01_modes su02_csr_priv su03_deleg su04_strap su07_epc_len su08_satp_bare su09_warl su10_wfi su11_mip_sw"
# su02 reads `cycle` (csr 0xC00): the value is timing-dependent by definition and propagates through the
# handler's register save/restore, so for that one program the records are compared without the value
# column (pc, instruction, destination register and length still must match); every other program is
# compared byte for byte
ident() { if [ "$2" = su02_csr_priv ]; then awk '{ print $1, $2, $3, "-", $5 }' $1; else cat $1; fi; }
echo "== gate 1: the eleven directed tests, three memory profiles, priv = M at exit (real CSR read-back) =="
for t in $TESTS; do for cfg in min fixed random; do
  run $cfg $t 0 "$t-$cfg" +expect-csr=24:3 +commit-trace=$OUT/logs/$t-$cfg.commits || fails=$((fails+1)); done; done
echo "== gate 1b: commit records identical across profiles (programs without asynchronous events) =="
for t in $DETERMINISTIC; do
  if cmp -s <(ident $OUT/logs/$t-min.commits $t) <(ident $OUT/logs/$t-fixed.commits $t) && cmp -s <(ident $OUT/logs/$t-min.commits $t) <(ident $OUT/logs/$t-random.commits $t); then
    echo "  $t: identical ($(grep -vc '^#' $OUT/logs/$t-min.commits) records$([ $t = su02_csr_priv ] && echo ", values excluded: cycle-derived"))"; else echo "  $t: DIFFER"; fails=$((fails+1)); fi; done
for t in su05_irq_modes su06_timer_ssip; do echo "  $t: CLINT-timed, judged by its own checks (order/result/count), records: min $(grep -vc '^#' $OUT/logs/$t-min.commits) fixed $(grep -vc '^#' $OUT/logs/$t-fixed.commits) random $(grep -vc '^#' $OUT/logs/$t-random.commits)"; done
echo "== gate 2: an M-level interrupt aimed at a U-mode instruction with MIE = 0 (enabled below M) =="
T=$(printf '%x' $((0x$(awk '$3=="the_target"{print $1}' $OUT/elf/su12_aimed_u.sym))))
run aimed su12_aimed_u 0 "su12-aimed" +inject-pc=$T +target-pc=$T +target-reg=7:31000 +expect-fire-state=IF_WAIT +expect-interrupts=1 +min-irq-hits=1 +expect-csr=24:3 || fails=$((fails+1))
grep -q "FIRE cycle=.*priv=0" $OUT/logs/su12-aimed.log && echo "      -> the injector fired while priv = U (latched in the FIRE line)" || { echo "      -> FIRE line does not show priv = U"; fails=$((fails+1)); }
echo "== gate 3: named negatives, each rejected by the specific check; the RV64I control passes on every fault core =="
run fault-nodeleg su01_modes 11 "neg-nodeleg-su01" || fails=$((fails+1))     # check 11: the delegated U ecall never reached S (s_count = 0)
run fault-sirqm   su05_irq_modes 14 "neg-sirqm-su05" || fails=$((fails+1))   # check 14: a delegated S interrupt was handled at M level (m_irq_count 4, not 3)
run fault-sretspp su03_deleg 1 "neg-sretspp-su03" || fails=$((fails+1))      # check 1: SPP still set after sret
for f in nodeleg sirqm sretspp; do run fault-$f t01 0 "ctl-$f-t01" || fails=$((fails+1)); done
echo "CPU_SU_DONE fails=$fails"; [ $fails -eq 0 ]
