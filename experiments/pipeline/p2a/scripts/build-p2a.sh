#!/bin/bash
# PIPE-P2a: build every simulator the P2a run needs from ONE pinned source snapshot, sequentially (verilator -j 4).
#   build-p2a.sh <fresh outdir>
# Modes: m-* the multicycle reference (tag RTL, M and C always present); p1-* the pipeline in its accepted P1
# configuration (RV64I); pm-* the pipeline with PIPE_EXT_M=1. Output as build-sims.sh: src/, src.sha256, sims/,
# sims.txt (name, mode, flags, sha256), identity.txt (counted by idcheck.sh; exit status non-zero on any failure).
set -u
W=/home/engineer/fpga/worktrees/pipe-single; P1S=$W/experiments/pipeline/p1/scripts
OUT=${1:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p $OUT/src/rtl $OUT/src/pipeline $OUT/src/tb $OUT/src/inc $OUT/sims $OUT/logs
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
R=$W/rtl/cpu
cp $R/*.v $R/*.vh $OUT/src/rtl/; cp $R/tcpu_defs.vh $OUT/src/inc/; cp $R/pipeline/tcpu_core_pipe.v $OUT/src/pipeline/
cp $W/tests/cpu/tb/tcpu_top.v $W/tests/cpu/tb/tcpu_harness.v $W/experiments/pipeline/p1/tb/tcpu_main.cpp $OUT/src/tb/
(cd $OUT/src && find . -type f | sort | xargs sha256sum) > $OUT/src.sha256
{ echo "git: $(git -C $W rev-parse HEAD) (worktree $(git -C $W status --porcelain | wc -l) changed paths)"; echo "verilator: $(verilator --version)"
  echo "gcc: $(riscv64-unknown-elf-gcc --version | head -1)"; echo "date: $(date -u +%FT%TZ)"; } > $OUT/tools.txt
git -C $W status --porcelain > $OUT/worktree-status.txt
S=$OUT/src
MULTI="-I$S/inc $S/rtl/tcpu_core.v $S/rtl/tcpu_regfile.v $S/rtl/tcpu_csr.v $S/rtl/tcpu_muldiv.v $S/rtl/tcpu_cdecode.v $S/rtl/tcpu_xlate.v $S/rtl/tcpu_tlb.v $S/rtl/tcpu_ptw.v $S/rtl/tcpu_permcheck.v $S/rtl/tcpu_ifill.v $S/rtl/tcpu_icache.v $S/rtl/tcpu_cacheable.v"
PIPE1="-DTCPU_IMPL_PIPE -I$S/inc $S/pipeline/tcpu_core_pipe.v $S/rtl/tcpu_regfile.v $S/rtl/tcpu_csr.v $S/rtl/tcpu_icache.v $S/rtl/tcpu_cacheable.v"
PIPEM="$PIPE1 $S/rtl/tcpu_muldiv.v -GPIPE_EXT_M=1"
TB="$S/tb/tcpu_top.v $S/tb/tcpu_harness.v $S/tb/tcpu_main.cpp"
VL="verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED --top-module TeachingTop -CFLAGS -std=c++17"
BOUNDS="-GIRQ_LAT_BOUND=2000 -GPROGRESS_BOUND=5000"
fail=0
build() {  # build <name> <mode m|p1|pm> <flags...>
  local n=$1 mode=$2; shift 2
  local src; case $mode in m) src="$MULTI";; p1) src="$PIPE1";; pm) src="$PIPEM";; esac
  local how=""
  if ! timeout 900 $VL -Mdir $OUT/sims/$n -o tcpu_tb $BOUNDS "$@" $src $TB > $OUT/logs/build-$n.log 2>&1; then
    # one retry with a single build thread from the same inputs (Verilator 5.022 has crashed tearing down its thread
    # pool: "attempted to destroy locked Thread Pool"); the first log is kept, and the retry is marked in sims.txt
    mv $OUT/logs/build-$n.log $OUT/logs/build-$n.first-failure.log; rm -rf $OUT/sims/$n; how=" [retried -j 1 after a failed build]"
    timeout 900 ${VL/-j 4/-j 1} -Mdir $OUT/sims/$n -o tcpu_tb $BOUNDS "$@" $src $TB > $OUT/logs/build-$n.log 2>&1
  fi
  if [ $? = 0 ] && [ -x $OUT/sims/$n/tcpu_tb ]; then
    echo "$n $mode $* $(sha256sum $OUT/sims/$n/tcpu_tb | cut -c1-16)$how" >> $OUT/sims.txt; echo "built $n$how"
  else echo "BUILD FAIL $n"; grep %Error $OUT/logs/build-$n.log | head -3; fail=1; fi
  rm -rf $OUT/sims/$n/*.o $OUT/sims/$n/*.d 2>/dev/null
}
for mode in m pm; do
  build $mode-min   $mode -GREADY_DELAY=0 -GRESP_DELAY=1
  build $mode-fixed $mode -GREADY_DELAY=2 -GRESP_DELAY=5
  for seed in 12345 777 4242; do build $mode-rnd$seed $mode -GRANDOM=1 -GSEED=$seed -GREADY_DELAY=0 -GRESP_DELAY=1; done
done
build p1-min p1 -GREADY_DELAY=0 -GRESP_DELAY=1
# negative controls: the core-level knobs (fixed profile) and the unit's own fault injections, on both implementations
build pm-fault15 pm -GREADY_DELAY=2 -GRESP_DELAY=5 -GPIPE_FAULT=15
build pm-fault16 pm -GREADY_DELAY=2 -GRESP_DELAY=5 -GPIPE_FAULT=16
build pm-wsext    pm -GFAULT_W_SEXT=1
build pm-mulhsign pm -GFAULT_MULH_SIGN=1
build m-wsext     m  -GFAULT_W_SEXT=1
build m-mulhsign  m  -GFAULT_MULH_SIGN=1
# ---- identity: each wrong selection must fail to build for its named reason (idcheck.sh; counted)
IDOUT=$OUT/logs; . $P1S/idcheck.sh
{
  idcheck M-without-the-unit-source "Cannot find file containing module: 'tcpu_muldiv'" $PIPE1 -GPIPE_EXT_M=1 $TB
  idcheck knob15-without-M "pipe_p1_unsupported_PIPE_FAULT_needs_M" $PIPE1 -GPIPE_FAULT=15 $TB
  idcheck W_SEXT-injection-without-M "pipe_p1_unsupported_FAULT_W_SEXT" $PIPE1 -GFAULT_W_SEXT=1 $TB
  idcheck EXT_M-2 "pipe_p1_unsupported_PIPE_EXT_M" $PIPE1 $S/rtl/tcpu_muldiv.v -GPIPE_EXT_M=2 $TB
  idcheck EXT_C-not-yet "pipe_p2a_not_implemented_PIPE_EXT_C" $PIPEM -GPIPE_EXT_C=1 $TB
  idcheck PIPE_FAULT-17 "pipe_p1_unsupported_PIPE_FAULT" $PIPEM -GPIPE_FAULT=17 $TB
  idcheck define-with-multicycle-list "Cannot find file containing module: 'tcpu_core_pipe'" -DTCPU_IMPL_PIPE $MULTI $TB
  echo "ID_FAILS=$ID_FAILS"
} > $OUT/identity.txt 2>&1
cat $OUT/identity.txt
idf=$(sed -n 's/^ID_FAILS=//p' $OUT/identity.txt); [ -n "$idf" ] || idf=1
echo "BUILD_P2A_DONE fail=$fail identity_fails=$idf sims=$(wc -l < $OUT/sims.txt)"
[ "$fail" = 0 ] && [ "$idf" = 0 ]
