#!/usr/bin/env bash
# Build the step-5 system simulator: the RD2 SoC (generated Verilog, in teaching/step5/sim) with YOUR core inside,
# verilated together with the host driver. Takes about 20 seconds.
#   step5-build-sim.sh <core-dir> <out-dir>
# Needs Verilator 5 and fesvr. Neither is in this repository:
#   VERILATOR_ENV  a bash script that puts verilator on PATH, sourced only if verilator is not already there
#   FZ             the fpga-zynq checkout: rocket-chip/vsrc and testchipip/{vsrc,csrc} simulation models
#   FESVR          the fesvr install prefix (include/fesvr, lib/libfesvr.so)
set -u
CORE=$(cd "${1:?core dir}" && pwd); OUT=${2:?out dir}
HERE=$(cd "$(dirname "$0")/.." && pwd); ROOT=$(cd "$HERE/.." && pwd); S5=$HERE/step5/sim
FZ=${FZ:-/home/engineer/fpga/teaching-cpu-work/fpga-zynq}
FESVR=${FESVR:-/home/engineer/fpga/teaching-cpu-work/install}
VERILATOR_ENV=${VERILATOR_ENV:-/home/engineer/fpga/experiments/chipyard-env.sh}
command -v verilator >/dev/null || { set +u; source "$VERILATOR_ENV" >/dev/null; set -u; }
command -v verilator >/dev/null || { echo "step5: no verilator on PATH (set VERILATOR_ENV)"; exit 2; }
for f in "$FZ/testchipip/csrc/SimSerial.cc" "$FESVR/lib/libfesvr.so"; do
  [ -e "$f" ] || { echo "step5: missing $f (set FZ / FESVR)"; exit 2; }; done
core_srcs=$(ls "$CORE"/*.v 2>/dev/null) || { echo "step5: no .v files in $CORE"; exit 2; }

mkdir -p "$OUT"
V=$OUT/RD2Harness.RD2BootConfig.v
[ -s "$V" ] || xz -dc "$S5/RD2Harness.RD2BootConfig.v.xz" > "$V"
rm -rf "$OUT/obj_dir"
# The SoC instantiates `tcpu_core #(.RESET_PC(65600))`, i.e. 0x10040, the boot ROM's wait loop. Assertions are the
# TileLink protocol monitors inside the SoC: a bus-protocol violation by your core stops the run with "Assertion".
verilator --cc --exe --build --vpi --no-timing -j 8 -Wno-fatal -Wno-WIDTH -Wno-STMTDLY -Wno-CASEINCOMPLETE \
  -Wno-UNSIGNED -Wno-DECLFILENAME --x-assign unique --top-module RD2Harness \
  +define+PRINTF_COND='$c("Verilated::assertOn()")' +define+STOP_COND='$c("Verilated::assertOn()")' \
  -I"$FZ/rocket-chip/vsrc" -I"$ROOT/rtl/cpu" -I"$CORE" -Mdir "$OUT/obj_dir" -o sim \
  -CFLAGS "-std=c++17 -I$FESVR/include -I$FZ/testchipip/csrc -DVERILATOR" \
  -LDFLAGS "-L$FESVR/lib -lfesvr -Wl,-rpath,$FESVR/lib" \
  "$V" $core_srcs \
  "$FZ/rocket-chip/vsrc/AsyncResetReg.v" "$FZ/rocket-chip/vsrc/plusarg_reader.v" \
  "$FZ/testchipip/vsrc/SimSerial.v" "$FZ/testchipip/vsrc/SimBlockDevice.v" \
  "$S5/step5_main.cpp" "$FZ/testchipip/csrc/SimSerial.cc" "$FZ/testchipip/csrc/SimBlockDevice.cc" \
  "$FZ/testchipip/csrc/blkdev.cc" > "$OUT/verilator.log" 2>&1
if [ -x "$OUT/obj_dir/sim" ]; then echo "  built $OUT/obj_dir/sim (core: $CORE)"; exit 0; fi
echo "step5: simulator build failed, see $OUT/verilator.log"; grep -E "%Error|error:" "$OUT/verilator.log" | head -10 | cut -c1-200
exit 1
