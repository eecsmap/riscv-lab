#!/bin/bash
# PIPE-P2b: build every simulator the P2b run needs from ONE pinned source snapshot, sequentially (verilator -j 4).
#   build-p2b.sh <fresh outdir>
# Modes: m-* the multicycle reference (tag RTL: M, C, S/U, Sv39, A); pmcs-* the pipeline with PIPE_EXT_M, PIPE_EXT_C
# and PIPE_EXT_SU (S/U and Sv39: the pipeline's TLB and the shared walker inside tcpu_ptw_wrap); ma-* / pmcsa-* the
# same with MISA_A=1 (checkpoint 3: the A extension; the CPU-A profiles t0/t1/t2, the external race, the five CPU-A
# injections). The race configuration needs the address of a02's `race` word: a02 is compiled here (as
# cpu-a/scripts/run-cpu-a.sh compiles it) and run-p2b-a.sh runs this very ELF; its race address and hash are recorded
# in a02-race.txt (the run refuses anything else). Output: src/, src.sha256, sims/, sims.txt, identity.txt (idcheck.sh, counted); exit != 0 on failure.
set -u
W=/home/engineer/fpga/worktrees/pipe-single; P1S=$W/experiments/pipeline/p1/scripts
OUT=${1:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p $OUT/src/rtl $OUT/src/pipeline $OUT/src/tb $OUT/src/inc $OUT/sims $OUT/logs
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
R=$W/rtl/cpu
cp $R/*.v $R/*.vh $OUT/src/rtl/; cp $R/tcpu_defs.vh $OUT/src/inc/; cp $R/pipeline/*.v $OUT/src/pipeline/
cp $W/tests/cpu/tb/tcpu_top.v $W/tests/cpu/tb/tcpu_harness.v $W/experiments/pipeline/p1/tb/tcpu_main.cpp $OUT/src/tb/
(cd $OUT/src && find . -type f | sort | xargs sha256sum) > $OUT/src.sha256
{ echo "git: $(git -C $W rev-parse HEAD) (worktree $(git -C $W status --porcelain | wc -l) changed paths)"; echo "verilator: $(verilator --version)"
  echo "gcc: $(riscv64-unknown-elf-gcc --version | head -1)"; echo "date: $(date -u +%FT%TZ)"; } > $OUT/tools.txt
git -C $W status --porcelain > $OUT/worktree-status.txt
S=$OUT/src
MULTI="-I$S/inc $S/rtl/tcpu_core.v $S/rtl/tcpu_regfile.v $S/rtl/tcpu_csr.v $S/rtl/tcpu_muldiv.v $S/rtl/tcpu_cdecode.v $S/rtl/tcpu_xlate.v $S/rtl/tcpu_tlb.v $S/rtl/tcpu_ptw.v $S/rtl/tcpu_permcheck.v $S/rtl/tcpu_ifill.v $S/rtl/tcpu_icache.v $S/rtl/tcpu_cacheable.v"
PIPE1="-DTCPU_IMPL_PIPE -I$S/inc $S/pipeline/tcpu_core_pipe.v $S/rtl/tcpu_regfile.v $S/rtl/tcpu_csr.v $S/rtl/tcpu_icache.v $S/rtl/tcpu_cacheable.v"
SV39SRC="$S/pipeline/tcpu_tlb2.v $S/pipeline/tcpu_ptw_wrap.v $S/rtl/tcpu_ptw.v $S/rtl/tcpu_permcheck.v"
PIPEMCS="$PIPE1 $S/rtl/tcpu_muldiv.v $S/rtl/tcpu_cdecode.v $SV39SRC -GPIPE_EXT_M=1 -GPIPE_EXT_C=1 -GPIPE_EXT_SU=1"
TB="$S/tb/tcpu_top.v $S/tb/tcpu_harness.v $S/tb/tcpu_main.cpp"
VL="verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED --top-module TeachingTop -CFLAGS -std=c++17"
BOUNDS="-GIRQ_LAT_BOUND=2000 -GPROGRESS_BOUND=5000"
fail=0
build() {  # build <name> <mode m|pmcs> <flags...>
  local n=$1 mode=$2; shift 2
  local src; case $mode in m) src="$MULTI";; pmcs) src="$PIPEMCS";; ma) src="$MULTI -GMISA_A=1";; pmcsa) src="$PIPEMCS -GMISA_A=1";; esac
  local how=""
  if ! timeout 900 $VL -Mdir $OUT/sims/$n -o tcpu_tb $BOUNDS "$@" $src $TB > $OUT/logs/build-$n.log 2>&1; then
    mv $OUT/logs/build-$n.log $OUT/logs/build-$n.first-failure.log; rm -rf $OUT/sims/$n; how=" [retried -j 1 after a failed build]"
    timeout 900 ${VL/-j 4/-j 1} -Mdir $OUT/sims/$n -o tcpu_tb $BOUNDS "$@" $src $TB > $OUT/logs/build-$n.log 2>&1
  fi
  if [ $? = 0 ] && [ -x $OUT/sims/$n/tcpu_tb ]; then
    echo "$n $mode $* $(sha256sum $OUT/sims/$n/tcpu_tb | cut -c1-16)$how" >> $OUT/sims.txt; echo "built $n$how"
  else echo "BUILD FAIL $n"; grep %Error $OUT/logs/build-$n.log | head -3; fail=1; fi
  rm -rf $OUT/sims/$n/*.o $OUT/sims/$n/*.d 2>/dev/null
}
for mode in m pmcs; do
  build $mode-min   $mode -GREADY_DELAY=0 -GRESP_DELAY=1
  build $mode-fixed $mode -GREADY_DELAY=2 -GRESP_DELAY=5
  build $mode-rnd12345 $mode -GRANDOM=1 -GSEED=12345 -GREADY_DELAY=0 -GRESP_DELAY=1
  build $mode-nodeleg $mode -GFAULT_NO_DELEG=1
  build $mode-sirqm   $mode -GFAULT_S_IRQ_IN_M=1
  build $mode-sretspp $mode -GFAULT_SRET_SPP=1
  build $mode-noperm  $mode -GFAULT_PTW_NO_PERM=1
  build $mode-if2     $mode -GFAULT_IF2_NO_XLATE=1
  build $mode-trunc   $mode -GFAULT_PPN_TRUNC=1
done
for k in 21 22 23; do build pmcs-fault$k pmcs -GREADY_DELAY=2 -GRESP_DELAY=5 -GPIPE_FAULT=$k; done
# ---- checkpoint 3 (A)
CA=/home/engineer/fpga/experiments/teaching-cpu/cpu-a; PREP=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests
T2H=/home/engineer/fpga/teaching-cpu-work/cpu/tests2
mkdir -p $OUT/aelf
riscv64-unknown-elf-gcc -march=rv64ia_zicsr -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wa,--fatal-warnings \
  -T $PREP/link.ld -I$PREP -I$T2H -o $OUT/aelf/a02.elf $PREP/crt.S $T2H/thandler.S $CA/tests/a02_lrsc.S > $OUT/aelf/a02.cc.log 2>&1 || { echo "CC FAIL a02"; fail=1; }
RACE=0x$(riscv64-unknown-elf-nm $OUT/aelf/a02.elf | awk '$3=="race"{print $1}'); echo "$RACE $(sha256sum $OUT/aelf/a02.elf | cut -c1-16)" > $OUT/a02-race.txt
for mode in ma pmcsa; do
  build $mode-t0 $mode -GREADY_DELAY=0 -GRESP_DELAY=1
  build $mode-t1 $mode -GREADY_DELAY=2 -GRESP_DELAY=5
  build $mode-t2 $mode -GRANDOM=1 -GSEED=7 -GREADY_DELAY=3 -GRESP_DELAY=4
  build $mode-race $mode -GEXT_POINT=2 -GEXT_TIMES=2 -GEXT_ADDR=$RACE -GEXT_DATA=0x00000000000AA000 -GREADY_DELAY=2 -GRESP_DELAY=3
  for f in FAULT_A_W_NOSEXT FAULT_A_SC_RESULT FAULT_A_AMO_AS_LOAD FAULT_A_EARLY_RETIRE FAULT_A_NO_RESV_CLEAR; do build $mode-$f $mode -G$f=1; done
done
IDOUT=$OUT/logs; . $P1S/idcheck.sh
{
  idcheck SU-injection-without-SU "pipe_p1_unsupported_FAULT_SRET_SPP" $PIPE1 -GFAULT_SRET_SPP=1 $TB
  idcheck EXT_SU-2 "pipe_p1_unsupported_PIPE_EXT_SU" $PIPEMCS -GPIPE_EXT_SU=2 $TB
  idcheck C-without-the-decoder-source "Cannot find file containing module: 'tcpu_cdecode'" $PIPE1 $S/rtl/tcpu_muldiv.v -GPIPE_EXT_M=1 -GPIPE_EXT_C=1 $TB
  idcheck SU-without-the-TLB-source "Cannot find file containing module: 'tcpu_tlb2'" $PIPE1 $S/rtl/tcpu_muldiv.v $S/rtl/tcpu_cdecode.v $S/pipeline/tcpu_ptw_wrap.v $S/rtl/tcpu_ptw.v $S/rtl/tcpu_permcheck.v -GPIPE_EXT_M=1 -GPIPE_EXT_C=1 -GPIPE_EXT_SU=1 $TB
  idcheck knob22-without-SU "pipe_p1_unsupported_PIPE_FAULT_needs_SU" $PIPE1 -GPIPE_FAULT=22 $TB
  idcheck SV39-injection-without-SU "pipe_p1_unsupported_FAULT_PPN_TRUNC" $PIPE1 -GFAULT_PPN_TRUNC=1 $TB
  # TLB_ENTRIES is the core's parameter (not the harness top's): this one elaborates the core itself as the top
  VL_TB=$VL; VL="verilator --lint-only -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED --top-module tcpu_core_pipe"
  idcheck TLB_ENTRIES-4 "pipe_p2b_unsupported_TLB_ENTRIES" $PIPEMCS -GTLB_ENTRIES=4
  VL=$VL_TB
  idcheck MISA_A-2 "pipe_p1_unsupported_MISA_A" $PIPEMCS -GMISA_A=2 $TB
  idcheck A-injection-without-A "pipe_p1_unsupported_FAULT_A_SC_RESULT" $PIPEMCS -GFAULT_A_SC_RESULT=1 $TB
  idcheck PIPE_FAULT-24 "pipe_p1_unsupported_PIPE_FAULT" $PIPEMCS -GPIPE_FAULT=24 $TB
  idcheck define-with-multicycle-list "Cannot find file containing module: 'tcpu_core_pipe'" -DTCPU_IMPL_PIPE $MULTI $TB
  echo "ID_FAILS=$ID_FAILS"
} > $OUT/identity.txt 2>&1
cat $OUT/identity.txt
idf=$(sed -n 's/^ID_FAILS=//p' $OUT/identity.txt); [ -n "$idf" ] || idf=1
echo "BUILD_P2B_DONE fail=$fail identity_fails=$idf sims=$(wc -l < $OUT/sims.txt)"
[ "$fail" = 0 ] && [ "$idf" = 0 ]
