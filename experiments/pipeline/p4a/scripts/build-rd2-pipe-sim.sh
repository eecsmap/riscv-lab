#!/usr/bin/env bash
# PIPE-P4a copy of p2b/soc/build-rd2-pipe-sim.sh: NHARTS (default 2) harts; the generated Verilog must instantiate
# tcpu_core_pipe exactly NHARTS times, and the simulator main is built with M2B_NHARTS=NHARTS.
# PIPE-P2b checkpoint 5: verilate the RD2 harness of a PIPELINE configuration (one hart) from an explicit source
# manifest. Same flags, C++ sources and main as the accepted single-core simulator (multicore/m3/tests/
# build-xv6-dual-sim.sh with NHARTS=1), with one deliberate difference: the teaching-CPU sources are the files
# rtl/cpu/pipeline/SOURCES.pipe names, copied into <outdir>/rtl, and the only CPU directory on the search path is
# <outdir>/inc holding tcpu_defs.vh -- so nothing the generated Verilog instantiates can be found by Verilator's
# -I module auto-discovery. The build refuses generated Verilog that instantiates the multicycle tcpu_core.
#   build-rd2-pipe-sim.sh <generated.v> <rtl/cpu dir> <fresh outdir>
set -u
cd /home/engineer/fpga
WS=/home/engineer/fpga/teaching-cpu-work; FZ=$WS/fpga-zynq
V=${1:?generated verilog}; RTL=${2:?rtl/cpu dir}; OUT=${3:?outdir}
MAN=$RTL/pipeline/SOURCES.pipe
[ -s "$V" ]   || { echo "REFUSE: missing or empty $V"; exit 2; }
[ -s "$MAN" ] || { echo "REFUSE: no manifest $MAN"; exit 2; }
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
NH=${NHARTS:-2}; n=$(grep -cE "^\s*tcpu_core_pipe\b" "$V"); [ "$n" = "$NH" ] || { echo "REFUSE: $V instantiates tcpu_core_pipe $n times, NHARTS=$NH"; exit 2; }
grep -qE '^\s*tcpu_core\b' "$V" && { echo "REFUSE: $V instantiates the multicycle tcpu_core"; exit 2; }
mkdir -p "$OUT/rtl" "$OUT/inc"
SRCS=""
while read -r kind path; do
  case "$kind" in ''|\#*) continue;; esac
  [ -f "$RTL/$path" ] || { echo "REFUSE: the manifest names $path, missing in $RTL"; exit 2; }
  case "$kind" in
    include) cp "$RTL/$path" "$OUT/inc/";;
    top|module) cp "$RTL/$path" "$OUT/rtl/"; SRCS="$SRCS $OUT/rtl/$(basename $path)";;
    *) echo "REFUSE: manifest kind $kind"; exit 2;;
  esac
done < "$MAN"
cp "$MAN" "$OUT/SOURCES.pipe"
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
VSRCS="$V $SRCS $FZ/rocket-chip/vsrc/AsyncResetReg.v $FZ/rocket-chip/vsrc/plusarg_reader.v \
  $FZ/testchipip/vsrc/SimSerial.v $FZ/testchipip/vsrc/SimBlockDevice.v"
RD2SRC=/home/engineer/fpga/experiments/teaching-cpu/reset-drain/rd2/src; M2BT=/home/engineer/fpga/experiments/multicore/m3/tests
CSRCS="$M2BT/m3_main.cpp $RD2SRC/rd2_sim_serial.cc $FZ/testchipip/csrc/SimBlockDevice.cc $FZ/testchipip/csrc/blkdev.cc"
for f in $VSRCS $CSRCS $OUT/inc/*; do sha256sum $f >> "$OUT/inputs.sha256"; done
{ verilator --version; date -u +%FT%TZ; echo "rtl dir: $RTL"; echo "manifest: $MAN"; } > "$OUT/tools.txt"
TOPMOD=${TOPMOD:-RD2Harness}
# PIPE-P4a runner fix: the verilator command is overridable (tests inject a stub) and success needs BOTH its status 0
# AND the executable -- an executable left behind by a failed build is not a build
"${VERILATOR:-verilator}" --cc --exe --build --vpi --no-timing -O3 --x-assign fast --x-initial fast -j 4 \
  -Wno-fatal -Wno-WIDTH -Wno-STMTDLY -Wno-CASEINCOMPLETE -Wno-UNSIGNED -Wno-DECLFILENAME \
  --x-assign unique --top-module $TOPMOD \
  +define+PRINTF_COND='$c("Verilated::assertOn()")' +define+STOP_COND='$c("Verilated::assertOn()")' \
  -I$FZ/rocket-chip/vsrc -I$OUT/inc -Mdir "$OUT/obj_dir" -o sim \
  -CFLAGS "-std=c++17 -O2 -I$WS/install/include -I$FZ/testchipip/csrc -DVERILATOR -DM2B_NHARTS=$NH -DTEST_HARNESS=V$TOPMOD -DHARNESS_TYPE=V$TOPMOD -DHARNESS_HEADER='\"V$TOPMOD.h\"'" \
  -LDFLAGS "-L$WS/install/lib -lfesvr -Wl,-rpath,$WS/install/lib" \
  $VSRCS $CSRCS > "$OUT/verilator.log" 2>&1; rc=$?
if [ "$rc" = 0 ] && [ -x "$OUT/obj_dir/sim" ]; then
  rm -f "$OUT"/obj_dir/*.o "$OUT"/obj_dir/*.d
  sha256sum "$OUT/obj_dir/sim" >> "$OUT/inputs.sha256"; echo "RD2_PIPE_SIM_BUILD_OK $(sha256sum $OUT/obj_dir/sim | cut -c1-16)"; exit 0; fi
echo "RD2_PIPE_SIM_BUILD_FAIL rc=$rc"; grep -E "%Error|error:" "$OUT/verilator.log" | head -10 | cut -c1-200; exit 1
