#!/bin/bash
# PIPE-P1: build every simulator the P1 run needs, from ONE pinned source snapshot, sequentially (verilator -j 4).
#   build-sims.sh <fresh outdir>
# Output: <out>/src (the snapshot actually compiled + src.sha256), <out>/sims/<name>/tcpu_tb, build logs,
# <out>/identity.txt (implementation-selection checks), <out>/sims.txt (name, implementation, flags, sha256).
set -u
W=/home/engineer/fpga/worktrees/pipe-single
OUT=${1:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p $OUT/src/rtl $OUT/src/pipeline $OUT/src/tb $OUT/src/inc $OUT/sims $OUT/logs
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
R=$W/rtl/cpu
cp $R/*.v $R/*.vh $OUT/src/rtl/
# INCLUDE-ONLY directory. Verilator searches every -I directory for MISSING MODULES too (-I = -y), so pointing -I at
# rtl/cpu let a build with the wrong source list silently pick up tcpu_core.v (found by identity check 2 in
# runs/sims-1). Only the header lives here; every module is named explicitly on the command line.
cp $R/tcpu_defs.vh $OUT/src/inc/
cp $R/pipeline/tcpu_core_pipe.v $OUT/src/pipeline/
cp $W/tests/cpu/tb/tcpu_top.v $W/tests/cpu/tb/tcpu_harness.v $W/experiments/pipeline/p1/tb/tcpu_main.cpp $OUT/src/tb/
(cd $OUT/src && find . -type f | sort | xargs sha256sum) > $OUT/src.sha256
{ echo "git: $(git -C $W rev-parse HEAD) ($(git -C $W describe --tags --always 2>/dev/null))"; echo "verilator: $(verilator --version)";
  echo "gcc: $(riscv64-unknown-elf-gcc --version | head -1)"; echo "date: $(date -u +%FT%TZ)"; } > $OUT/tools.txt
S=$OUT/src
MULTI="-I$S/inc $S/rtl/tcpu_core.v $S/rtl/tcpu_regfile.v $S/rtl/tcpu_csr.v $S/rtl/tcpu_muldiv.v $S/rtl/tcpu_cdecode.v $S/rtl/tcpu_xlate.v $S/rtl/tcpu_tlb.v $S/rtl/tcpu_ptw.v $S/rtl/tcpu_permcheck.v $S/rtl/tcpu_ifill.v $S/rtl/tcpu_icache.v $S/rtl/tcpu_cacheable.v"
PIPE="-DTCPU_IMPL_PIPE -I$S/inc $S/pipeline/tcpu_core_pipe.v $S/rtl/tcpu_regfile.v $S/rtl/tcpu_csr.v $S/rtl/tcpu_icache.v $S/rtl/tcpu_cacheable.v"
TB="$S/tb/tcpu_top.v $S/tb/tcpu_harness.v $S/tb/tcpu_main.cpp"
VL="verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED --top-module TeachingTop -CFLAGS -std=c++17"
BOUNDS="-GIRQ_LAT_BOUND=2000 -GPROGRESS_BOUND=5000"
fail=0
build() {  # build <name> <impl m|p> <flags...>
  local n=$1 impl=$2; shift 2
  local src; [ $impl = p ] && src="$PIPE" || src="$MULTI"
  if timeout 900 $VL -Mdir $OUT/sims/$n -o tcpu_tb $BOUNDS "$@" $src $TB > $OUT/logs/build-$n.log 2>&1; then
    echo "$n $impl $* $(sha256sum $OUT/sims/$n/tcpu_tb | cut -c1-16)" >> $OUT/sims.txt; echo "built $n"
  else echo "BUILD FAIL $n"; grep %Error $OUT/logs/build-$n.log | head -3; fail=1; fi
  rm -rf $OUT/sims/$n/*.o $OUT/sims/$n/*.d 2>/dev/null
}
# ---- timing profiles, both implementations: minimum, fixed back-pressure, three recorded random seeds
for impl in m p; do
  build $impl-min   $impl -GREADY_DELAY=0 -GRESP_DELAY=1
  build $impl-fixed $impl -GREADY_DELAY=2 -GRESP_DELAY=5
  for seed in 12345 777 4242; do build $impl-rnd$seed $impl -GRANDOM=1 -GSEED=$seed -GREADY_DELAY=0 -GRESP_DELAY=1; done
done
# ---- pipeline negative controls (fixed profile: long enough responses for the flush windows)
for k in 1 2 3 4 5 6 7 8 9 10 11 12; do build p-fault$k p -GREADY_DELAY=2 -GRESP_DELAY=5 -GPIPE_FAULT=$k; done
# ---- the harness's own monitors and the existing core fault injections, on the pipeline
build p-mon-samecycle   p -GMEM_SAME_CYCLE=1
build p-mon-withdraw    p -GREADY_DELAY=2 -GRESP_DELAY=5 -GREQ_WITHDRAW=1
build p-mon-loadpayload p -GLOAD_WDATA_LEAK=1
build p-fault-x0        p -GX0_WRITABLE=1
build p-fault-nosext    p -GNO_LOAD_SEXT=1
# ---- implementation identity: each mismatch must FAIL TO BUILD for the named reason; counted in the exit status
IDOUT=$OUT/logs; . "$(dirname "$(readlink -f "$0")")/idcheck.sh"
{
  idcheck define-with-multicycle-list "Cannot find file containing module: 'tcpu_core_pipe'" -DTCPU_IMPL_PIPE $MULTI $TB
  idcheck no-define-with-pipeline-list "Cannot find file containing module: 'tcpu_core'" -I$S/inc $S/pipeline/tcpu_core_pipe.v $S/rtl/tcpu_regfile.v $S/rtl/tcpu_csr.v $S/rtl/tcpu_icache.v $S/rtl/tcpu_cacheable.v $TB
  idcheck pipeline-MISA_A-1 "pipe_p1_unsupported_MISA_A" -GMISA_A=1 $PIPE $TB
  idcheck pipeline-PIPE_FAULT-13 "pipe_p1_unsupported_PIPE_FAULT" -GPIPE_FAULT=13 $PIPE $TB
  echo "ID_FAILS=$ID_FAILS"
} > $OUT/identity.txt 2>&1
cat $OUT/identity.txt
idf=$(sed -n 's/^ID_FAILS=//p' $OUT/identity.txt); [ -n "$idf" ] || idf=1      # no count at all is a failure too
echo "BUILD_SIMS_DONE fail=$fail identity_fails=$idf sims=$(wc -l < $OUT/sims.txt)"
[ "$fail" = 0 ] && [ "$idf" = 0 ]
