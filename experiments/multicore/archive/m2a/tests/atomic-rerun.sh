#!/usr/bin/env bash
# MC-M2a: the ORIGINAL CPU-A atomic scenarios (experiments/teaching-cpu/cpu-atomic-backend/scripts/atomic-run.sh,
# 27 entries + the scorer self-test) rerun against the mc-dual-backend scala from the PRIVATE common, judged by
# the ORIGINAL CPU-A score.py (read from its accepted location, not copied or edited). Same scenario names, same
# flags, same signatures as the accepted run; the only differences are the generator entry (gen.sh, private
# common, no shared-tree writes) and the output root.   atomic-rerun.sh <outroot>
set -uo pipefail
R=/home/engineer/fpga; FZ=$R/teaching-cpu-work/fpga-zynq; A=$R/experiments/teaching-cpu/cpu-atomic-backend/scripts
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); M2=$(dirname "$HERE"); GC=$M2/gen/common-dual; SRC=$GC/src/main/scala/teaching
OUT=$(readlink -f -m "${1:?outroot}"); [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p "$OUT"
cd $R
(cd $SRC && sha256sum PhysPortV2.scala AtomicBackend.scala RD2BridgeV2.scala AtomicTest.scala DualAtomicTest.scala AtomicHub.scala AtomicSoc.scala RD1Bridge.scala PhysPort.scala unittest_main.cpp atomic_soc_main.cpp) > $OUT/inputs.sha256
sha256sum $A/score.py $A/score-selftest.sh >> $OUT/inputs.sha256
{ verilator --version 2>/dev/null; date -u +%FT%TZ; } > $OUT/tools.txt
set +u; source $R/experiments/chipyard-env.sh >/dev/null; set -u
infra=0; scorefails=0; n=0
run_one() {
  local name=$1 cfg=$2 top=$3 proj=$4 main=$5 want=$6; shift 6; local flags="$*"
  local d=$OUT/$name; n=$((n+1))
  TOPPROJ=$proj bash $M2/gen/gen.sh $top $cfg $GC $d/gen > $d.gen.out 2>&1; local genrc=$?
  local V=$d/gen/$top.$cfg.v
  if [ $genrc -ne 0 ] || [ ! -s $V ]; then printf "  %-22s INFRA gen exit=%s\n" "$name" "$genrc"; infra=$((infra+1)); tail -3 $d.gen.out | cut -c1-200 | sed 's/^/      /'; return; fi
  cp $d/gen/generated.sha256 $d/inputs.sha256
  local cond='!reset'; [ $top = AtomicSocHarness ] && cond='$c("Verilated::assertOn()")'
  verilator --cc --exe --build --no-timing -j 4 -Wno-fatal -Wno-WIDTH -Wno-STMTDLY -Wno-CASEINCOMPLETE \
    --x-assign unique --top-module $top +define+PRINTF_COND="$cond" +define+STOP_COND="$cond" \
    -I$FZ/rocket-chip/vsrc -Mdir $d/obj_dir -o tb -CFLAGS "-std=c++17" \
    $V $FZ/rocket-chip/vsrc/AsyncResetReg.v $FZ/rocket-chip/vsrc/plusarg_reader.v $SRC/$main > $d/verilator.log 2>&1
  if [ ! -x $d/obj_dir/tb ]; then printf "  %-22s INFRA verilator\n" "$name"; infra=$((infra+1)); grep -E "%Error|error:" $d/verilator.log | head -2 | sed 's/^/      /'; return; fi
  sha256sum $d/obj_dir/tb >> $d/inputs.sha256
  timeout 900 $d/obj_dir/tb +max-cycles=800000 > $d/run.log 2>&1; local ec=$?; echo $ec > $d/exit.txt
  if [ $ec -eq 124 ]; then printf "  %-22s INFRA simulator timed out\n" "$name"; infra=$((infra+1)); return; fi
  python3 $A/score.py $d/run.log $flags > $d/score.txt 2>&1; local sc=$?
  printf "  %-22s sim=%s score=%s %s\n" "$name" "$ec" "$sc" "$(head -n 1 $d/score.txt | cut -c1-150)"
  if [ "$want" = 0 ]; then
    if [ "$ec" != 0 ]; then echo "      -> UNEXPECTED sim exit=$ec"; scorefails=$((scorefails+1)); fi
    if [ "$sc" != 0 ]; then scorefails=$((scorefails+1)); grep FAIL $d/score.txt | head -n 3 | cut -c1-160 | sed 's/^/      /'; fi
  else
    local sig=${want#neg:}
    if grep -qE "$sig" $d/score.txt $d/run.log; then echo "      -> rejected by the declared check: $(grep -hm1 -E "$sig" $d/score.txt $d/run.log | cut -c1-120)"
    else echo "      -> NOT rejected by the declared check ($sig)"; scorefails=$((scorefails+1)); fi
    grep -q FINISHED $d/run.log || echo "      (note: no FINISHED -- the run aborted; the detection above is by signature only)"
  fi
}
U="TestHarness freechips.rocketchip.unittest unittest_main.cpp"
S="AtomicSocHarness teaching atomic_soc_main.cpp"
echo "== unit harness: positives (sim exit 0, a clean pairing/replay score) =="
run_one amo-basic      AtomicAmoBasicConfig    $U 0 --min-amo 28
run_one amo-race       AtomicAmoRaceConfig     $U 0 --min-amo 16 --min-ext 16
run_one amo-partial    AtomicAmoPartialConfig  $U 0 --min-amo 12 --min-ext 10 --min-scok 1
run_one lrsc-basic     AtomicLrscBasicConfig   $U 0 --min-scok 5 --min-scfail 6
run_one lrsc-race      AtomicLrscRaceConfig    $U 0 --min-kills 4 --min-scfail 4 --min-scok 2 --min-ext 5
run_one errors         AtomicErrorsConfig      $U 0 --expect-refuse 1 --expect-wrefuse 2 --min-scfail 1 --min-illegal 9
run_one progress       AtomicProgressConfig    $U 0 --min-scok 20 --min-ext 30
run_one drain-getd     AtomicDrainGetConfig    $U 0 --drain
run_one drain-putd     AtomicDrainPutConfig    $U 0 --drain
run_one drain-resp     AtomicDrainRespConfig   $U 0 --drain
echo "== unit harness: return backpressure, delayers on both sides of the crossbar, D stalls =="
run_one bp-amo         AtomicBpAmoConfig       $U 0 --min-amo 16 --min-ext 16
run_one bp-lrsc        AtomicBpLrscConfig      $U 0 --min-kills 4 --min-scfail 4 --min-scok 2 --min-ext 5
run_one bp-lrsc-basic  AtomicBpLrscBasicConfig $U 0 --min-scok 5 --min-scfail 6
run_one bp-errors      AtomicBpErrorsConfig    $U 0 --expect-refuse 1 --expect-wrefuse 2 --min-illegal 9
run_one bp-drain       AtomicBpDrainConfig     $U 0 --drain
echo "== unit harness: negatives (detected only by the declared signature) =="
run_one neg-readerr-writes AtomicNegReadErrConfig  $U "neg:AMO Put issued after its Get returned an error" --expect-refuse 1
run_one neg-no-kill        AtomicNegNoKillConfig   $U "neg:SC result scfail=0, model says 1" --min-kills 4
run_one neg-wrong-source   AtomicNegWrongSrcConfig $U "neg:announced CPU range|mark pushed while one is pending" --min-scok 5
run_one neg-sc-early       AtomicNegScEarlyConfig  $U "neg:without a TileLink transaction|scfail 0 < required|model says 1" --min-scfail 4
# request semantics: the bridge is internally consistent, only the CPU's request disagrees
run_one neg-amo-map        AtomicNegAmoMapConfig     $U "neg:amo code 2\) and must map to TL opcode 2, the accepted A is opcode 3" --min-amo 28
run_one neg-amo-operand    AtomicNegAmoOperandConfig $U "neg:operand 0x[0-9a-f]+ was shipped as 0x[0-9a-f]+" --min-amo 28
echo "== the real topology: backend at the coherence-manager hook (before TLBroadcast), memory bus, TLToAXI4, SimAXIMem =="
# --soc: no scripted manager (SimAXIMem answers), so there is no MGR_* trace and no error regions inside DRAM;
# accesses outside DRAM are answered by the BootROM (reads, contents unknown to the model) or the error slave
run_one soc-amo-race   AtomicSocAmoRaceConfig  $S 0 --soc --min-amo 16 --min-ext 16
run_one soc-lrsc-race  AtomicSocLrscRaceConfig $S 0 --soc --min-kills 4 --min-scfail 4 --min-scok 2 --min-ext 5
run_one soc-partial    AtomicSocPartialConfig  $S 0 --soc --min-amo 12 --min-ext 10
run_one soc-errors     AtomicSocErrorsConfig   $S 0 --soc --min-scok 3 --min-illegal 9
run_one soc-neg-no-kill AtomicSocNegNoKillConfig $S "neg:SC result scfail=0, model says 1" --soc --min-kills 4
run_one soc-neg-amo-map AtomicSocNegAmoMapConfig $S "neg:amo code 2\) and must map to TL opcode 2, the accepted A is opcode 3" --soc --min-amo 16
echo "== the scorer against mutated logs =="
bash $A/score-selftest.sh $OUT/amo-basic/run.log $OUT/selftest --min-amo 28 | sed 's/^/  /'; [ ${PIPESTATUS[0]} = 0 ] || scorefails=$((scorefails+1))
echo "ATOMIC_RERUN_DONE scenarios=$n infra=$infra score_fails=$scorefails"; [ $infra -eq 0 ] && [ $scorefails -eq 0 ]
