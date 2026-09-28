#!/usr/bin/env bash
# MC-M1: experiments/teaching-cpu/cpu-sv39/scripts/run-cpu-sv39.sh with the cpu RTL directory as a parameter. The testbench ($WS/tb) and the programs are
# unchanged; only the RTL files and the include path point at the named directory.
#   run-cpu-sv39-rtl.sh <cpu-rtl-dir> <fresh outdir>
RTL=$(readlink -f "${1:?cpu rtl dir}"); shift
# CPU-SV39 core-level gates in one run.   run-cpu-sv39.sh <outdir>
set -u; cd /home/engineer/fpga
WS=/home/engineer/fpga/teaching-cpu-work/cpu; SV=/home/engineer/fpga/experiments/teaching-cpu/cpu-sv39
PREP=/home/engineer/fpga/experiments/teaching-cpu/cpu-su-prep; P2=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests
OUT=${1:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p $OUT/logs $OUT/rtl
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
cp $RTL/*.v $RTL/*.vh $WS/tb/*.v $WS/tb/*.cpp $OUT/rtl/; (cd $OUT/rtl && sha256sum *) > $OUT/source.sha256
{ verilator --version; riscv64-unknown-elf-gcc --version | head -n 1; date -u +%FT%TZ; } > $OUT/tools.txt
bash $SV/scripts/build.sh $OUT/elf > $OUT/logs/build-tests.log 2>&1 || { echo "TEST BUILD FAIL"; tail -n 5 $OUT/logs/build-tests.log; exit 3; }
# the CPU-SU tests: three as copies with Sv39 expectations (diffs recorded), the rest unchanged
bash $SV/scripts/make-su-copies.sh $OUT/su-copies | sed 's/^/  /'
GCC=riscv64-unknown-elf-gcc; CF="-mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -Wa,--fatal-warnings -I$OUT/su-copies"
for s in $OUT/su-copies/su[0-9]*.S; do n=$(basename $s .S)
  $GCC -march=rv64imc_zicsr $CF -T $OUT/su-copies/link.ld -o $OUT/elf/$n.elf $OUT/su-copies/crt.S $OUT/su-copies/handlers.S $s 2> $OUT/elf/$n.buildlog || { echo "BUILD FAIL $n"; exit 3; }
  riscv64-unknown-elf-nm $OUT/elf/$n.elf > $OUT/elf/$n.sym; done
$GCC -march=rv64i_zicsr $CF -I$P2 -T $P2/link.ld -o $OUT/elf/t01.elf $P2/crt.S $P2/t01_alu.S 2>/dev/null
(cd $OUT/elf && sha256sum *.elf) > $OUT/elf.sha256
# CPU-A closeout: with MISA_A_ONE=1 the simulators are built with the atomic path enabled (misa.A = 1 and
# the A instructions legal), so this suite can be run against the A-enabled configuration too. Unset, which
# is the default, nothing below changes.
AG=${MISA_A_ONE:+-GMISA_A=1}
build() { local n=$1; shift
  verilator --cc --exe --build -j 2 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED \
    ${AG:-} \
    --top-module TeachingTop -CFLAGS "-std=c++17 -O2" -Mdir $OUT/obj_$n -o tcpu_tb "$@" \
    -I$RTL $WS/tb/tcpu_top.v $WS/tb/tcpu_harness.v $RTL/tcpu_core.v $RTL/tcpu_regfile.v \
    $RTL/tcpu_csr.v $RTL/tcpu_muldiv.v $RTL/tcpu_cdecode.v $RTL/tcpu_ptw.v $WS/tb/tcpu_main.cpp > $OUT/logs/build-$n.log 2>&1 \
    || { echo "SIM BUILD FAIL $n"; tail -n 5 $OUT/logs/build-$n.log; exit 3; }
  sha256sum $OUT/obj_$n/tcpu_tb >> $OUT/sim.sha256; }
build min; build fixed -GREADY_DELAY=2 -GRESP_DELAY=5; build random -GRANDOM=1 -GSEED=12345
build irqptw -GIRQ_POINT=11 -GIRQ_LINE=0 -GIRQ_TIMES=1 -GRESP_DELAY=3
build fault-noperm -GFAULT_PTW_NO_PERM=1; build fault-if2 -GFAULT_IF2_NO_XLATE=1; build fault-trunc -GFAULT_PPN_TRUNC=1
fails=0
run() { local cfg=$1 elf=$2 want=$3 label=$4; shift 4
  timeout 900 $OUT/obj_$cfg/tcpu_tb +elf=$OUT/elf/$elf.elf +max-cycles=6000000 "$@" > $OUT/logs/$label.log 2>&1
  local ec=$?; echo $ec > $OUT/logs/$label.exit; local st=ok
  [ "$ec" = "$want" ] || st="UNEXPECTED exit=$ec want=$want"
  [ "$(grep -c 'PROTO ERROR' $OUT/logs/$label.log)" = 0 ] || st="$st PROTO_ERRORS"
  grep -qE "TIMEOUT|argument error|Internal Error|Thread Pool" $OUT/logs/$label.log && st="$st INFRA/TIMEOUT(not a result)"
  printf "  %-26s exit=%-3s want=%-3s %s\n" "$label" "$ec" "$want" "$(grep -oE 'TOHOST code=[0-9]+|TRAPS=[0-9]+|PRIV at exit=[0-9]|CSR CHECK (OK|FAIL)[^,]*|CHAIN (OK|FAIL)[^,]*|FIRE STATE (OK|FAIL)[^,]*|FIRE cycle=[0-9]+ pc=0x[0-9a-f]+ state=[A-Z_0-9]+ enabled=[01] req_valid=[01] req_ready=[01] outstanding=[01] priv=[0-9]|COMMIT COUNT (OK|FAIL)[^,]*|CORE-RESET (OK|FAIL)[^,]*|INTERRUPT COUNT (OK|FAIL)|TIMEOUT|TRAP STORM' $OUT/logs/$label.log | tr '\n' ' ')"
  [ "$st" = ok ] || { echo "      -> $st"; return 1; }; return 0; }
sym() { printf '%x' $((0x$(awk -v n="$2" '$3==n{print $1}' $OUT/elf/$1.sym))); }
SV="sv01_bare_sv39 sv02_pages sv03_perms sv04_bad_pte sv05_straddle sv06_switch sv09_nonleaf"
echo "== gate 1: the six Sv39 tests, three memory profiles, priv = M and satp = 0 at exit (real CSRs), records identical =="
for t in $SV; do for cfg in min fixed random; do
  run $cfg $t 0 "$t-$cfg" +expect-csr=24:3 +expect-csr=21:0 +commit-trace=$OUT/logs/$t-$cfg.commits || fails=$((fails+1)); done
  if cmp -s $OUT/logs/$t-min.commits $OUT/logs/$t-fixed.commits && cmp -s $OUT/logs/$t-min.commits $OUT/logs/$t-random.commits; then
    echo "  $t: records identical ($(grep -vc '^#' $OUT/logs/$t-min.commits))"; else echo "  $t: records DIFFER"; fails=$((fails+1)); fi; done
echo "== gate 1b: the faulting instructions of sv03 never retired (commit counts from the trace) =="
run min sv03_perms 0 "sv03-noretire" +expect-commit-count=$(sym sv03_perms st_ro):0 +expect-commit-count=$(sym sv03_perms ld_xo):0 \
  +expect-commit-count=$(sym sv03_perms ld_upage):0 +expect-commit-count=$(sym sv03_perms ld_spage):0 +expect-commit-count=$(sym sv03_perms st_spage):0 \
  +expect-commit-count=$(sym sv03_perms ld_mprv_u):0 +expect-commit-count=$(sym sv03_perms jalr_upage):1 || fails=$((fails+1))
echo "      (jalr_upage retires: the fault is on its target's fetch; the MXR re-read is a separate instruction)"
echo "== gate 1c: sv09 (non-leaf reserved bits): the 18 faulting accesses never retired; the same program on the walker before the fix fails at its first case =="
run min sv09_nonleaf 0 "sv09-noretire" +expect-commit-count=$(sym sv09_nonleaf nl_ld):0 +expect-commit-count=$(sym sv09_nonleaf nl_st):0 +expect-commit-count=$(sym sv09_nonleaf nl_j):6 || fails=$((fails+1))
echo "      (nl_j retires 6 times: the jalr itself is fine, the fetch of its target faults)"
OLD=/home/engineer/fpga/experiments/teaching-cpu/cpu-sv39/old-rtl/tcpu_ptw.v   # (SV is the test list from here on)
verilator --cc --exe --build -j 2 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED --top-module TeachingTop -CFLAGS "-std=c++17 -O2" -Mdir $OUT/obj_oldptw -o tcpu_tb \
  -I$RTL $WS/tb/tcpu_top.v $WS/tb/tcpu_harness.v $RTL/tcpu_core.v $RTL/tcpu_regfile.v $RTL/tcpu_csr.v $RTL/tcpu_muldiv.v $RTL/tcpu_cdecode.v $OLD $WS/tb/tcpu_main.cpp > $OUT/logs/build-oldptw.log 2>&1 \
  || echo "SKIP oldptw control: it substitutes the pre-Sv39 walker, and this RTL's tcpu_xlate drives pins that walker lacks (leaf_ppn/leaf_level/leaf_r/leaf_w); the control is inapplicable to the TLB/cache cores, not failed"
[ -x $OUT/obj_oldptw/tcpu_tb ] && sha256sum $OUT/obj_oldptw/tcpu_tb $OLD >> $OUT/sim.sha256
if [ -x $OUT/obj_oldptw/tcpu_tb ]; then run oldptw sv09_nonleaf 11 "sv09-on-old-walker" || fails=$((fails+1)); else echo "  SKIP sv09-on-old-walker (no oldptw build)"; fi   # check 11: U on the root pointer did not fault (the walk descended)
if [ -x $OUT/obj_oldptw/tcpu_tb ]; then run oldptw sv02_pages 0 "sv02-on-old-walker" || fails=$((fails+1)); else echo "  SKIP sv02-on-old-walker (no oldptw build)"; fi     # the old walker still passes an ordinary program: the new case is what changed
echo "== gate 2: an interrupt while a PTE read is outstanding: deferred, the walk completes, taken once after the load =="
T7=$(sym sv07_irq_ptw the_target)
run irqptw sv07_irq_ptw 0 "sv07-irq-ptw" +inject-pc=$T7 +target-pc=$T7 +target-reg=7:2468 +expect-fire-state=XLATE +expect-interrupts=1 +min-irq-hits=1 +expect-csr=24:3 || fails=$((fails+1))
grep -q "FIRE cycle=.*outstanding=1" $OUT/logs/sv07-irq-ptw.log && echo "      -> fired with a PTE read outstanding" || { echo "      -> no PTE read was outstanding at the fire"; fails=$((fails+1)); }
echo "== gate 3: a core-only reset during a walk (the bridge model discards the stale PTE answer) =="
for cfg in min fixed random; do run $cfg sv02_pages 0 "sv02-reset-ptw-$cfg" +core-reset-at-op=ptw +core-reset-n=3 || fails=$((fails+1))
  grep -q "CORE-RESET OK" $OUT/logs/sv02-reset-ptw-$cfg.log || { echo "      -> no core-reset evidence"; fails=$((fails+1)); }; done
echo "  stale answers discarded: $(grep -h 'CORE-RESET OK' $OUT/logs/sv02-reset-ptw-*.log | grep -oE 'model=[0-9]+' | tr '\n' ' ')"
echo "== gate 4: named negatives, each rejected by its specific check; the RV64I control passes =="
run fault-noperm sv03_perms 5 "neg-noperm-sv03" || fails=$((fails+1))     # check 5: the execute-only page became readable (the RO store still faults on D = 0)
run fault-if2    sv05_straddle 1 "neg-if2-sv05"  || fails=$((fails+1))     # check 1: the straddler's second half came from the wrong page
run fault-trunc  sv04_bad_pte 8 "neg-trunc-sv04" || fails=$((fails+1))     # check 8: the high-PPN leaf was silently truncated and read
for f in noperm if2 trunc; do run fault-$f t01 0 "ctl-$f-t01" || fails=$((fails+1)); done
echo "== gate 5: the CPU-SU tests on the Sv39 core (su08/su09/su11 as copies with recorded diffs), three profiles =="
for t in su01_modes su02_csr_priv su03_deleg su04_strap su05_irq_modes su06_timer_ssip su07_epc_len su08_satp_bare su09_warl su10_wfi su11_mip_sw; do
  for cfg in min fixed random; do run $cfg $t 0 "$t-$cfg" +expect-csr=24:3 || fails=$((fails+1)); done; done
echo "CPU_SV39_DONE fails=$fails"; [ $fails -eq 0 ]
