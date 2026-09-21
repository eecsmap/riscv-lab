#!/usr/bin/env bash
# Verilate the RD2 boot harness with the same host fesvr path the M3 regression uses. The only differences
# from m4-prep/sim-regression-2/run/m3-build-sim.sh are the top module and the TEST_HARNESS macro.
#   rd2-build-sim.sh <generated.v> <outdir>
set -u; cd /home/engineer/fpga; WS=/home/engineer/fpga/teaching-cpu-work; FZ=$WS/fpga-zynq
V=${1:?generated verilog}; OUT=${2:?outdir}
[ -s "$V" ] || { echo "missing or empty $V"; exit 2; }
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p $OUT
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
RTL=$WS/cpu/rtl
VSRCS="$V $RTL/tcpu_core.v $RTL/tcpu_regfile.v $RTL/tcpu_csr.v $RTL/tcpu_muldiv.v $RTL/tcpu_cdecode.v $RTL/tcpu_ptw.v \
  $FZ/rocket-chip/vsrc/AsyncResetReg.v $FZ/rocket-chip/vsrc/plusarg_reader.v \
  $FZ/testchipip/vsrc/SimSerial.v $FZ/testchipip/vsrc/SimBlockDevice.v"
RD2SRC=/home/engineer/fpga/experiments/teaching-cpu/reset-drain/rd2/src
CSRCS="$RD2SRC/rd2_boot_main.cpp $RD2SRC/rd2_sim_serial.cc \
  $FZ/testchipip/csrc/SimBlockDevice.cc $FZ/testchipip/csrc/blkdev.cc"
for f in $VSRCS $CSRCS; do sha256sum $f >> $OUT/inputs.sha256; done
{ verilator --version; date -u +%FT%TZ; } > $OUT/tools.txt
verilator --cc --exe --build --vpi --no-timing -O3 --x-assign fast --x-initial fast -j 6 -Wno-fatal -Wno-WIDTH -Wno-STMTDLY -Wno-CASEINCOMPLETE \
  -Wno-UNSIGNED -Wno-DECLFILENAME --x-assign unique --top-module ${TOPMOD:-RD2Harness} \
  +define+PRINTF_COND='$c("Verilated::assertOn()")' +define+STOP_COND='$c("Verilated::assertOn()")' \
  -I$FZ/rocket-chip/vsrc -I$RTL -Mdir $OUT/obj_dir -o sim \
  -CFLAGS "-std=c++17 -O2 -I$WS/install/include -I$FZ/testchipip/csrc -DVERILATOR -DTEST_HARNESS=V${TOPMOD:-RD2Harness} -DHARNESS_TYPE=V${TOPMOD:-RD2Harness} -DHARNESS_HEADER='\"V${TOPMOD:-RD2Harness}.h\"'" \
  -LDFLAGS "-L$WS/install/lib -lfesvr -Wl,-rpath,$WS/install/lib" \
  $VSRCS $CSRCS > $OUT/verilator.log 2>&1; rc=$?
if [ -x $OUT/obj_dir/sim ]; then sha256sum $OUT/obj_dir/sim >> $OUT/inputs.sha256; echo "SIM_BUILD_OK"; exit 0; fi
echo "SIM_BUILD_FAIL rc=$rc"; grep -E "%Error|error:" $OUT/verilator.log | head -10 | cut -c1-200; exit 1
