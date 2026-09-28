#!/usr/bin/env bash
# MC-M2a: generate, verilate, run and score one unit-harness configuration (TestHarness top, the same
# unittest main the accepted CPU-A stage used), from the PRIVATE common. Every artefact's identity is
# recorded; the cycle budget is COMPUTED from the declared latencies, never a fixed number.
#
#   dual-run.sh <private-common> <outdir> <name> <Config> <ntx> <lat> <astall> <mgrd> <resp> <delayq01> [score2 flags...]
#
# Budget: per completed transaction the worst case is an AMO -- three downstream trips (Get, Put and the
# synthesised response) each bounded by latency + a-stall + manager d-stall + delayer + handshake slack --
# plus the CPU-side response stall. MAXCYC = ntx * bound * 1.5, and the UnitTest's own timeout is set the
# same way at elaboration (DualParams.timeout), so a hang is a result, not a wait.
set -uo pipefail
R=/home/engineer/fpga; WS=$R/teaching-cpu-work; FZ=$WS/fpga-zynq
M2=$R/experiments/multicore/m2a; HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
GC=${1:?private common}; OUT=${2:?outdir}; NAME=${3:?name}; CFG=${4:?config}
NTX=${5:?ntx}; LAT=${6:?lat}; AST=${7:?astall}; MGD=${8:?mgrd}; RESP=${9:?resp}; DQ=${10:?delayq01}; shift 10; FLAGS="$*"
[ -f "$GC/Makefrag" ] || { echo "REFUSE: $GC is not a prepared common"; exit 2; }
D=$OUT/$NAME; [ -e "$D" ] && { echo "REFUSE: $D exists"; exit 2; }
mkdir -p "$D"
set +u; source $R/experiments/chipyard-env.sh >/dev/null; set -u
SRC=$GC/src/main/scala/teaching
bound=$(( 3 * (LAT + AST + MGD + DQ * 12 + 8) + RESP + 6 ))
MAXCYC=$(( NTX * bound * 3 / 2 ))
echo "name=$NAME config=$CFG ntx=$NTX bound=$bound maxcyc=$MAXCYC" > "$D/budget.txt"
s=$(date +%s)
TOPPROJ=freechips.rocketchip.unittest bash $M2/gen/gen.sh TestHarness "$CFG" "$GC" "$D/gen" > "$D/gen.out" 2>&1 || { echo "INFRA gen: $(tail -2 "$D/gen.out" | tr '\n' ' ' | cut -c1-200)"; echo "RUN name=$NAME verdict=INFRA-GEN" > "$D/verdict.txt"; exit 1; }
V=$D/gen/TestHarness.$CFG.v
cp "$D/gen/generated.sha256" "$D/inputs.sha256"; (cd "$SRC" && sha256sum AtomicBackend.scala RD2BridgeV2.scala DualAtomicTest.scala AtomicTest.scala PhysPortV2.scala) >> "$D/inputs.sha256"
verilator --cc --exe --build --no-timing -j 4 -Wno-fatal -Wno-WIDTH -Wno-STMTDLY -Wno-CASEINCOMPLETE \
  --x-assign unique --top-module TestHarness +define+PRINTF_COND='!reset' +define+STOP_COND='!reset' \
  -I$FZ/rocket-chip/vsrc -Mdir "$D/obj_dir" -o tb -CFLAGS "-std=c++17 -O1" \
  "$V" $FZ/rocket-chip/vsrc/AsyncResetReg.v $FZ/rocket-chip/vsrc/plusarg_reader.v $SRC/unittest_main.cpp > "$D/verilator.log" 2>&1
[ -x "$D/obj_dir/tb" ] || { echo "INFRA verilator: $(grep -m1 -E '%Error' "$D/verilator.log" | cut -c1-160)"; echo "RUN name=$NAME verdict=INFRA-VERILATE" > "$D/verdict.txt"; exit 1; }
sha256sum "$D/obj_dir/tb" >> "$D/inputs.sha256"
b=$(date +%s)
timeout ${WALL:-3600} "$D/obj_dir/tb" +max-cycles=$MAXCYC > "$D/run.log" 2>&1; ec=$?; echo $ec > "$D/exit.txt"
e=$(date +%s)
if [ $ec -eq 124 ]; then echo "RUN name=$NAME verdict=TIMEOUT wall=${WALL:-3600}s" | tee "$D/verdict.txt"; exit 1; fi
python3 $HERE/score2.py "$D/run.log" --summary-json "$D/score.json" $FLAGS > "$D/score.txt" 2>&1; sc=$?
cyc=$(grep -oE 'UNITTEST [A-Z]+ after [0-9]+ cycles' "$D/run.log" | head -1)
echo "RUN name=$NAME sim_exit=$ec score=$sc build=$((b-s))s run=$((e-b))s $cyc $(head -1 "$D/score.txt" | cut -c1-200)" | tee "$D/verdict.txt"
[ $ec = 0 ] && [ $sc = 0 ]
