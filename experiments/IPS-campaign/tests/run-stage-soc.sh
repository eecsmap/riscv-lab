#!/usr/bin/env bash
# SoC regression across ANY set of cores, one generated harness, one set of frozen binaries.
#
# The stage-1 script compared exactly two cores. Rather than copy it per stage, this takes the cores as
# arguments: a near-copy is a second thing to keep in step, which is the mistake tcpu_permcheck exists
# to avoid in the RTL and there is no reason to make it in the harness.
#
#   run-stage-soc.sh <fresh outdir> <label>=<rtl-dir> [<label>=<rtl-dir> ...]
#
# The FIRST core given is the reference every gain is computed against.
set -u
R=/home/engineer/fpga
CAMP=$(cd "$(dirname "$0")/.." && pwd)
PREP=$R/experiments/teaching-cpu/xv6-board-prep
GEN=$R/experiments/teaching-cpu/m4-prep/sim-regression-2/gen-TeachingCpuBootConfig/TeachingCpuHarness.TeachingCpuBootConfig.v
OUT=${1:?usage: run-stage-soc.sh <outdir> <label>=<rtl> ...}; shift
[ $# -ge 2 ] || { echo "REFUSE: give at least two cores to compare"; exit 2; }
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT/logs" "$OUT/elf"
fails=0
ok() { echo "  ok   : $1"; }
no() { echo "  FAIL : $1 -- $2"; fails=$((fails+1)); }

LABELS=""
for spec in "$@"; do
  l=${spec%%=*}; d=${spec#*=}
  [ -d "$d" ] || { echo "REFUSE: $l points at $d, which is not a directory"; exit 2; }
  LABELS="$LABELS $l"
  eval "RTL_$l=\$d"
done
echo "== cores:"; for l in $LABELS; do eval "echo \"   $l -> \$RTL_$l  \$(sha256sum \$RTL_$l/tcpu_core.v | cut -c1-16)\""; done

echo "== frozen binaries (identical for every core)"
for p in boot01_marker boot02_clint boot03_ddr boot04_badaddr; do cp $PREP/deploy-bundle/$p.elf "$OUT/elf/"; done
for p in ext01_m ext02_c ext04_sv39; do cp $PREP/probes/build/$p.elf "$OUT/elf/"; done
for p in perf02_sv39 perf03_fetch perf04_where; do cp $PREP/probes/build-perf/$p.elf "$OUT/elf/"; done
bash "$CAMP/workloads/build-perf06.sh" "$OUT/b-perf06" > "$OUT/logs/perf06-build.log" 2>&1 \
  && cp "$OUT/b-perf06/perf06_iws.elf" "$OUT/elf/" || no "perf06 built" "see logs/perf06-build.log"
for t in tlb01 tlb02; do
  [ -f "$CAMP/workloads/build-$t.sh" ] || continue
  bash "$CAMP/workloads/build-$t.sh" "$OUT/b-$t" > "$OUT/logs/$t-build.log" 2>&1 \
    && cp "$OUT/b-$t"/*.elf "$OUT/elf/" || no "$t built" "see logs/$t-build.log"
done
(cd "$OUT/elf" && sha256sum *.elf) > "$OUT/elf.sha256"
echo "  $(wc -l < "$OUT/elf.sha256") frozen ELFs"

# one heavy build at a time
for l in $LABELS; do
  eval "rtl=\$RTL_$l"
  echo "== verilating against $l"
  bash "$CAMP/tests/build-sim.sh" "$GEN" "$rtl" "$OUT/sim-$l" > "$OUT/logs/build-$l.log" 2>&1
  grep -q SIM_BUILD_OK "$OUT/logs/build-$l.log" && ok "$l sim built" \
    || no "$l sim built" "$(grep -m2 -E '%Error|SIM_BUILD_FAIL' "$OUT/logs/build-$l.log" | head -2)"
done
[ $fails = 0 ] || { echo "STAGE_SOC fails=$fails (stopped: a simulator is missing)"; exit 1; }

cycles_for() {
  case "$1" in
    # Sized from the SLOWEST core, which is the baseline. perf02_sv39 walks a page table per access
    # and the board measured it at CPI 161 for 4 KiB pages; 8 M was sized from the faster cores and
    # the baseline ran out. A bound that only the fast cores fit is not a bound, it is a filter.
    perf02_sv39) echo 40000000 ;;
    perf06_iws)  echo 12000000 ;;
    perf03_fetch|perf04_where) echo 8000000 ;;
    tlb01_sfence|tlb02_canonical) echo 8000000 ;;
    *) echo 2000000 ;;
  esac
}
run() {
  local core=$1
  local prog=$2
  local d="$OUT/runs/$core-$prog"
  mkdir -p "$d"
  set -o pipefail
  timeout 1800 "$OUT/sim-$core/obj_dir/sim" +max-cycles=$(cycles_for "$prog") "$OUT/elf/$prog.elf" 2>&1 \
    | python3 "$CAMP/tests/trace_aggregate.py" --out "$d" > "$d/aggregate.txt" 2>&1
  local rc=${PIPESTATUS[0]}
  set +o pipefail
  echo "$rc" > "$d/exit"
  echo "$rc"
}

PROGS=$(cd "$OUT/elf" && ls *.elf | sed 's/\.elf$//' | tr '\n' ' ')
echo "== every frozen binary on every core"
for p in $PROGS; do
  line="  $p:"; bad=0
  for l in $LABELS; do
    rc=$(run "$l" "$p"); line="$line $l=$rc"
    [ "$rc" = 0 ] || bad=1
  done
  if [ $bad = 0 ]; then ok "${line#  }"; else no "${line#  }" "a non-zero exit (124 = timeout, a result not a pass)"; fi
done

echo "== every probe's own verdict must AGREE across cores"
for p in $PROGS; do
  # EVERY core must report a marker, and they must all be the same. An earlier version took the first
  # core's marker as the reference with `[ -z "$ref" ] && ref=$m`, which does nothing when that core
  # reported NOTHING -- so a core with no marker at all was skipped and the check said "agree". It did
  # exactly that for perf02_sv39, where the baseline had timed out and printed nothing.
  ref=""; agree=1; missing=""
  for l in $LABELS; do
    m=$(grep -oE 'TEACHING-[A-Z0-9-]+-(OK|FAIL)|M3-[A-Z0-9-]+-(OK|FAIL)' "$OUT/runs/$l-$p/console.txt" 2>/dev/null | head -1)
    if [ -z "$m" ]; then missing="$missing $l"; agree=0; continue; fi
    [ -z "$ref" ] && ref=$m
    [ "$m" = "$ref" ] || agree=0
  done
  if [ -n "$missing" ]; then no "$p verdicts agree" "no marker at all from:$missing"
  elif [ -n "$ref" ] && [ $agree = 1 ]; then ok "$p: every core reports $ref"
  else no "$p verdicts agree" "cores disagree; first='$ref'"; fi
done
echo "STAGE_SOC fails=$fails"
[ $fails = 0 ]
