#!/usr/bin/env bash
# PIPE-P4a: the traced two-hart pipeline RD2 simulator (RD2PipeDualBootConfig, as generated) with the P3b association
# checker bound into the generated RD2ZynqTop ONCE PER HART. The checker source is used unchanged apart from two
# mechanical substitutions per copy: the hierarchical core path (harts.cpu.core / harts_1.cpu.core) and the line
# prefix (ASSOC H0 / ASSOC H1). Each hart's awaitingRetire register (FIRRTL _T_<n>) is found by construction:
# the register set under `if (W)` where W = harts[_1]_io_physObs_respFire & ..., and it must be a term of that
# hart's busyAll_<i>. Otherwise as build-rd2-pipe-sim.sh (SOURCES.pipe only, include-only dir, m3_main NHARTS=2).
#   build-assoc-dual.sh <generated RD2PipeDualBootConfig .v> <rtl/cpu dir> <fresh outdir> [sed expression applied to a COPY of the Verilog]
set -u
cd /home/engineer/fpga
WS=/home/engineer/fpga/teaching-cpu-work; FZ=$WS/fpga-zynq; HERE=$(cd "$(dirname "$0")" && pwd)
CHK=/home/engineer/fpga/worktrees/pipe-dual/experiments/pipeline/p2b/soc/assoc/p2b_assoc_chk.sv
V0=${1:?verilog}; RTL=${2:?rtl}; OUT=${3:?outdir}; MUT=${4:-}
[ -s "$V0" ] && [ -s "$CHK" ] || { echo "REFUSE: missing input"; exit 2; }; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT/rtl" "$OUT/inc"; V=$V0
if [ -n "$MUT" ]; then V=$OUT/mutated.v; sed -E "$MUT" "$V0" > "$V"; diff "$V0" "$V" > "$OUT/mutation.diff"
  [ -s "$OUT/mutation.diff" ] || { echo "REFUSE: the mutation changed nothing"; exit 2; }; fi
awk '/^module RD2ZynqTop/,/^endmodule/' "$V" > "$OUT/zt.v"
: > "$OUT/bind.sv"
for i in 0 1; do pre=harts_; [ $i = 1 ] && pre=harts_1_; core=harts.cpu.core; [ $i = 1 ] && core=harts_1.cpu.core
  w=$(grep -oE "assign (_T_[0-9]+) = ${pre}io_physObs_respFire & _T_[0-9]+;" "$OUT/zt.v" | awk '{print $2}')
  [ $(echo "$w" | wc -w) = 1 ] || { echo "REFUSE: hart $i: the response-set wire is not unique: '$w'"; exit 2; }
  r=$(grep -A1 -E "^\s*if \($w\) begin" "$OUT/zt.v" | grep -oE "^\s*(_T_[0-9]+) <= 1'h1;" | awk '{print $1}' | sort -u)
  [ $(echo "$r" | wc -w) = 1 ] || { echo "REFUSE: hart $i: the awaitingRetire register is not unique: '$r'"; exit 2; }
  grep -qE "assign busyAll_$i = .*\b$r\b" "$OUT/zt.v" || { echo "REFUSE: hart $i: $r is not a term of busyAll_$i"; exit 2; }
  sed -e "s/module p2b_assoc_chk (/module p2b_assoc_chk_h$i (/" -e "s/harts\.cpu\.core/$core/g" -e "s/\"ASSOC /\"ASSOC H$i /g" "$CHK" > "$OUT/p2b_assoc_chk_h$i.sv"
  cat >> "$OUT/bind.sv" <<BIND
// hart $i: awaitingRetire = $r (set under $w, a term of busyAll_$i)
bind RD2ZynqTop p2b_assoc_chk_h$i assoc_h$i (.clock(clock), .reset(reset), .aw_soc($r), .isFetch(${pre}io_obs_isFetch),
  .reqFire(${pre}io_physObs_reqFire), .respFire(${pre}io_physObs_respFire), .commitValid(${pre}io_obs_commitValid),
  .trapValid(${pre}io_obs_trapValid), .trapInterrupt(${pre}io_obs_trapInterrupt), .commitPc(${pre}io_obs_commitPc),
  .trapEpc(${pre}io_obs_trapEpc));
BIND
done
cat "$OUT/bind.sv"
SRCS=""; MAN=$RTL/pipeline/SOURCES.pipe
while read -r kind path; do case "$kind" in ''|\#*) continue;; esac
  case "$kind" in include) cp "$RTL/$path" "$OUT/inc/";; top|module) cp "$RTL/$path" "$OUT/rtl/"; SRCS="$SRCS $OUT/rtl/$(basename $path)";; esac; done < "$MAN"
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
VSRCS="$V $SRCS $OUT/p2b_assoc_chk_h0.sv $OUT/p2b_assoc_chk_h1.sv $OUT/bind.sv $FZ/rocket-chip/vsrc/AsyncResetReg.v $FZ/rocket-chip/vsrc/plusarg_reader.v $FZ/testchipip/vsrc/SimSerial.v $FZ/testchipip/vsrc/SimBlockDevice.v"
CSRCS="/home/engineer/fpga/experiments/multicore/m3/tests/m3_main.cpp /home/engineer/fpga/experiments/teaching-cpu/reset-drain/rd2/src/rd2_sim_serial.cc $FZ/testchipip/csrc/SimBlockDevice.cc $FZ/testchipip/csrc/blkdev.cc"
for f in $VSRCS $CSRCS $OUT/inc/*; do sha256sum $f >> "$OUT/inputs.sha256"; done
verilator --cc --exe --build --vpi --no-timing -O3 --x-assign fast --x-initial fast -j 4 \
  -Wno-fatal -Wno-WIDTH -Wno-STMTDLY -Wno-CASEINCOMPLETE -Wno-UNSIGNED -Wno-DECLFILENAME --x-assign unique --top-module RD2Harness \
  +define+PRINTF_COND='$c("Verilated::assertOn()")' +define+STOP_COND='$c("Verilated::assertOn()")' \
  -I$FZ/rocket-chip/vsrc -I$OUT/inc -Mdir "$OUT/obj_dir" -o sim \
  -CFLAGS "-std=c++17 -O2 -I$WS/install/include -I$FZ/testchipip/csrc -DVERILATOR -DM2B_NHARTS=2 -DTEST_HARNESS=VRD2Harness -DHARNESS_TYPE=VRD2Harness -DHARNESS_HEADER='\"VRD2Harness.h\"'" \
  -LDFLAGS "-L$WS/install/lib -lfesvr -Wl,-rpath,$WS/install/lib" $VSRCS $CSRCS > "$OUT/verilator.log" 2>&1; rc=$?
if [ -x "$OUT/obj_dir/sim" ]; then rm -f "$OUT"/obj_dir/*.o "$OUT"/obj_dir/*.d; sha256sum "$OUT/obj_dir/sim" >> "$OUT/inputs.sha256"; echo "ASSOC_DUAL_BUILD_OK $(sha256sum $OUT/obj_dir/sim | cut -c1-16)"; exit 0; fi
echo "ASSOC_DUAL_BUILD_FAIL rc=$rc"; grep -E "%Error" "$OUT/verilator.log" | head -5 | cut -c1-200; exit 1
