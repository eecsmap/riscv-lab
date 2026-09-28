#!/usr/bin/env bash
# MC-M1 T1.5: the atomic backend's SoC-level scenarios (AtomicSoc.scala: TeachingCpuV2 + V2 bridge + the
# accepted AtomicBackend at the coherence-manager hook), generated from the PRIVATE common that carries the
# wrapper's scala, scored by the accepted scorer.
#
# Coverage boundary, stated: these scenarios instantiate TeachingCpuV2 directly (AtomicZynqTop), so they
# exercise the BlackBox change (hartId parameter, observation split) and the RTL against the unchanged
# backend -- they do NOT go through TeachingHart or RD2ZynqTop. The RD2 probe runs cover those.
#
# Verilate/run/score steps are cpu-atomic-backend/scripts/atomic-run.sh's run_one, with the generator
# redirected (the original regenerates into the shared fpga-zynq tree, which MC-M1 does not touch).
#
#   atomic-soc-subset.sh <private-common-dir> <fresh outdir>
set -uo pipefail
R=/home/engineer/fpga; WS=$R/teaching-cpu-work; FZ=$WS/fpga-zynq
AB=$R/experiments/teaching-cpu/cpu-atomic-backend
M1=$R/experiments/multicore/m1
GC=${1:?private common}; OUT=${2:?outdir}
[ -f "$GC/Makefrag" ] || { echo "REFUSE: $GC is not a prepared common"; exit 2; }
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT"
SRC=$GC/src/main/scala/teaching
cd $R
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
infra=0; scorefails=0; n=0
run_one() {  # run_one <name> <Config> <want: 0 | neg:<signature regex>> <score flags...>
  local name=$1 cfg=$2 want=$3; shift 3; local flags="$*"
  local d=$OUT/$name; n=$((n+1))
  bash $M1/gen/gen.sh AtomicSocHarness $cfg "$GC" "$d/gen" > "$d.gen.out" 2>&1 || {
    mkdir -p "$d"; printf "  %-22s INFRA gen\n" "$name"; infra=$((infra+1)); tail -3 "$d.gen.out" | sed 's/^/      /'; return; }
  local V=$d/gen/AtomicSocHarness.$cfg.v
  cp "$d/gen/generated.sha256" "$d/inputs.sha256"
  verilator --cc --exe --build --no-timing -j 3 -Wno-fatal -Wno-WIDTH -Wno-STMTDLY -Wno-CASEINCOMPLETE \
    --x-assign unique --top-module AtomicSocHarness +define+PRINTF_COND='$c("Verilated::assertOn()")' +define+STOP_COND='$c("Verilated::assertOn()")' \
    -I$FZ/rocket-chip/vsrc -Mdir "$d/obj_dir" -o tb -CFLAGS "-std=c++17" \
    "$V" $FZ/rocket-chip/vsrc/AsyncResetReg.v $FZ/rocket-chip/vsrc/plusarg_reader.v $SRC/atomic_soc_main.cpp > "$d/verilator.log" 2>&1
  if [ ! -x "$d/obj_dir/tb" ]; then printf "  %-22s INFRA verilator\n" "$name"; infra=$((infra+1)); grep -E "%Error|error:" "$d/verilator.log" | head -2 | sed 's/^/      /'; return; fi
  sha256sum "$d/obj_dir/tb" >> "$d/inputs.sha256"
  timeout 900 "$d/obj_dir/tb" +max-cycles=800000 > "$d/run.log" 2>&1; local ec=$?; echo $ec > "$d/exit.txt"
  if [ $ec -eq 124 ]; then printf "  %-22s INFRA simulator timed out\n" "$name"; infra=$((infra+1)); return; fi
  python3 $AB/scripts/score.py "$d/run.log" $flags > "$d/score.txt" 2>&1; local sc=$?
  printf "  %-22s sim=%s score=%s %s\n" "$name" "$ec" "$sc" "$(head -n 1 "$d/score.txt" | cut -c1-150)"
  if [ "$want" = 0 ]; then
    [ "$ec" = 0 ] || { echo "      -> UNEXPECTED sim exit=$ec"; scorefails=$((scorefails+1)); }
    [ "$sc" = 0 ] || { scorefails=$((scorefails+1)); grep FAIL "$d/score.txt" | head -n 3 | cut -c1-160 | sed 's/^/      /'; }
  else
    local sig=${want#neg:}
    if grep -qE "$sig" "$d/score.txt" "$d/run.log"; then echo "      -> rejected by the declared check: $(grep -hm1 -E "$sig" "$d/score.txt" "$d/run.log" | cut -c1-120)"
    else echo "      -> NOT rejected by the declared check ($sig)"; scorefails=$((scorefails+1)); fi
  fi
}
echo "== the real topology through TeachingCpuV2 (not the hart wrapper): backend at the coherence-manager hook"
run_one soc-amo-race    AtomicSocAmoRaceConfig   0 --soc --min-amo 16 --min-ext 16
run_one soc-lrsc-race   AtomicSocLrscRaceConfig  0 --soc --min-kills 4 --min-scfail 4 --min-scok 2 --min-ext 5
run_one soc-partial     AtomicSocPartialConfig   0 --soc --min-amo 12 --min-ext 10
run_one soc-neg-no-kill AtomicSocNegNoKillConfig "neg:SC result scfail=0, model says 1" --soc --min-kills 4
echo "ATOMIC_SOC_SUBSET scenarios=$n infra=$infra score_fails=$scorefails"
[ $infra -eq 0 ] && [ $scorefails -eq 0 ]
