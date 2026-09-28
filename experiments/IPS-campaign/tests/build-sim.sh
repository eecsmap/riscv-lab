#!/usr/bin/env bash
# Verilate the teaching-CPU SoC harness against a NAMED cpu RTL directory.
#
# teaching-cpu-work/cpu/m3-build-sim.sh does this with `RTL=$WS/cpu/rtl` hardcoded, and that tree is a
# read-only input to this campaign. This is the same build with the RTL directory as a parameter, so
# the identical harness can be built against baseline, fetch32, TLB and cache in turn -- which is the
# whole point of a cumulative comparison.
#
#   build-sim.sh <generated.v> <cpu-rtl-dir> <fresh outdir>
set -u
cd /home/engineer/fpga
WS=/home/engineer/fpga/teaching-cpu-work; FZ=$WS/fpga-zynq
V=${1:?generated verilog}; RTL=${2:?cpu rtl dir}; OUT=${3:?outdir}
[ -f "$V" ]   || { echo "REFUSE: missing $V"; exit 2; }
[ -d "$RTL" ] || { echo "REFUSE: missing rtl dir $RTL"; exit 2; }
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
for f in tcpu_core.v tcpu_regfile.v tcpu_csr.v tcpu_muldiv.v tcpu_cdecode.v tcpu_ptw.v tcpu_defs.vh; do
  [ -f "$RTL/$f" ] || { echo "REFUSE: $RTL is missing $f"; exit 2; }
done
mkdir -p "$OUT"
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
VSRCS="$V $RTL/tcpu_core.v $RTL/tcpu_regfile.v $RTL/tcpu_csr.v \
  $FZ/rocket-chip/vsrc/AsyncResetReg.v $FZ/rocket-chip/vsrc/plusarg_reader.v \
  $FZ/testchipip/vsrc/SimSerial.v $FZ/testchipip/vsrc/SimBlockDevice.v"
CSRCS="$FZ/common/src/main/scala/teaching/cpu_boot_main.cpp $FZ/testchipip/csrc/SimSerial.cc \
  $FZ/testchipip/csrc/SimBlockDevice.cc $FZ/testchipip/csrc/blkdev.cc"
for f in $VSRCS $CSRCS; do sha256sum $f >> "$OUT/inputs.sha256"; done
{ verilator --version; echo "gcc: $(riscv64-unknown-elf-gcc --version|head -1)"; date -u +%FT%TZ
  echo "cpu rtl dir: $RTL"; sha256sum $RTL/tcpu_core.v; } > "$OUT/tools.txt"
verilator --cc --exe --build --vpi --no-timing -j 3 -Wno-fatal -Wno-WIDTH -Wno-STMTDLY -Wno-CASEINCOMPLETE \
  -Wno-UNSIGNED -Wno-DECLFILENAME --x-assign unique --top-module TeachingCpuHarness \
  +define+PRINTF_COND='$c("Verilated::assertOn()")' +define+STOP_COND='$c("Verilated::assertOn()")' \
  -I$FZ/rocket-chip/vsrc -I$RTL -Mdir "$OUT/obj_dir" -o sim \
  -CFLAGS "-std=c++17 -I$WS/install/include -I$FZ/testchipip/csrc -DVERILATOR -DTEST_HARNESS=VTeachingCpuHarness" \
  -LDFLAGS "-L$WS/install/lib -lfesvr -Wl,-rpath,$WS/install/lib" \
  $VSRCS $CSRCS > "$OUT/verilator.log" 2>&1; rc=$?
if [ -x "$OUT/obj_dir/sim" ]; then
  sha256sum "$OUT/obj_dir/sim" >> "$OUT/inputs.sha256"; echo "SIM_BUILD_OK $RTL"; exit 0
fi
echo "SIM_BUILD_FAIL rc=$rc"; grep -E "%Error|error:" "$OUT/verilator.log" | head -10 | cut -c1-200; exit 1
