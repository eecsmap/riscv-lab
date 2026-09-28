#!/usr/bin/env bash
# Verilate the RD2 xv6 harness against a NAMED cpu RTL directory.
#
# Same relationship as tests/build-sim.sh has to m3-build-sim.sh: opt01-aligned-fetch/build-sim.sh does
# this with its RTL directory hardcoded, and that tree is a read-only input here. xv6 uses a DIFFERENT
# generated config from the SoC gates -- RD2Harness.RD2AtomicXv6FastConfig -- so it needs its own build.
#
#   build-xv6-sim.sh <generated.v> <cpu-rtl-dir> <fresh outdir>
set -u
cd /home/engineer/fpga
WS=/home/engineer/fpga/teaching-cpu-work; FZ=$WS/fpga-zynq
V=${1:?generated verilog}; RTL=${2:?cpu rtl dir}; OUT=${3:?outdir}
[ -s "$V" ]   || { echo "REFUSE: missing or empty $V"; exit 2; }
[ -d "$RTL" ] || { echo "REFUSE: missing rtl dir $RTL"; exit 2; }
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
for f in tcpu_core.v tcpu_regfile.v tcpu_csr.v tcpu_muldiv.v tcpu_cdecode.v tcpu_ptw.v tcpu_defs.vh; do
  [ -f "$RTL/$f" ] || { echo "REFUSE: $RTL is missing $f"; exit 2; }
done
mkdir -p "$OUT"
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
VSRCS="$V $RTL/tcpu_core.v $RTL/tcpu_regfile.v $RTL/tcpu_csr.v $RTL/tcpu_muldiv.v $RTL/tcpu_cdecode.v $RTL/tcpu_ptw.v \
  $FZ/rocket-chip/vsrc/AsyncResetReg.v $FZ/rocket-chip/vsrc/plusarg_reader.v \
  $FZ/testchipip/vsrc/SimSerial.v $FZ/testchipip/vsrc/SimBlockDevice.v"
RD2SRC=/home/engineer/fpga/experiments/teaching-cpu/reset-drain/rd2/src
CSRCS="$RD2SRC/rd2_boot_main.cpp $RD2SRC/rd2_sim_serial.cc \
  $FZ/testchipip/csrc/SimBlockDevice.cc $FZ/testchipip/csrc/blkdev.cc"
for f in $VSRCS $CSRCS; do sha256sum $f >> "$OUT/inputs.sha256"; done
{ verilator --version; date -u +%FT%TZ; echo "cpu rtl dir: $RTL"; sha256sum $RTL/tcpu_core.v; } > "$OUT/tools.txt"
TOPMOD=${TOPMOD:-RD2Harness}
verilator --cc --exe --build --vpi --no-timing -O3 --x-assign fast --x-initial fast -j 4 \
  -Wno-fatal -Wno-WIDTH -Wno-STMTDLY -Wno-CASEINCOMPLETE -Wno-UNSIGNED -Wno-DECLFILENAME \
  --x-assign unique --top-module $TOPMOD \
  +define+PRINTF_COND='$c("Verilated::assertOn()")' +define+STOP_COND='$c("Verilated::assertOn()")' \
  -I$FZ/rocket-chip/vsrc -I$RTL -Mdir "$OUT/obj_dir" -o sim \
  -CFLAGS "-std=c++17 -O2 -I$WS/install/include -I$FZ/testchipip/csrc -DVERILATOR -DTEST_HARNESS=V$TOPMOD -DHARNESS_TYPE=V$TOPMOD -DHARNESS_HEADER='\"V$TOPMOD.h\"'" \
  -LDFLAGS "-L$WS/install/lib -lfesvr -Wl,-rpath,$WS/install/lib" \
  $VSRCS $CSRCS > "$OUT/verilator.log" 2>&1; rc=$?
if [ -x "$OUT/obj_dir/sim" ]; then sha256sum "$OUT/obj_dir/sim" >> "$OUT/inputs.sha256"; echo "XV6_SIM_BUILD_OK $RTL"; exit 0; fi
echo "XV6_SIM_BUILD_FAIL rc=$rc"; grep -E "%Error|error:" "$OUT/verilator.log" | head -10 | cut -c1-200; exit 1
