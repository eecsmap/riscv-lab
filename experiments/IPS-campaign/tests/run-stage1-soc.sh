#!/usr/bin/env bash
# Stage 1 SoC regression: the SAME frozen binaries on the baseline core and on fetch32.
#
# The comparison is only worth anything if the two runs differ in exactly one thing. So: one generated
# harness, one set of ELFs with recorded hashes, two CPU RTL directories, and every architectural
# result compared between them.
#
#   run-stage1-soc.sh <fresh outdir>
set -u
R=/home/engineer/fpga
CAMP=$(cd "$(dirname "$0")/.." && pwd)
FIX=$(cd "$CAMP/../.." && pwd)/rtl/cpu
ACC=$R/worktrees/ips-baseline/rtl/cpu
PREP=$R/experiments/teaching-cpu/xv6-board-prep
GEN=$R/experiments/teaching-cpu/m4-prep/sim-regression-2/gen-TeachingCpuBootConfig/TeachingCpuHarness.TeachingCpuBootConfig.v
OUT=${1:?usage: run-stage1-soc.sh <fresh outdir>}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT/logs" "$OUT/elf"
fails=0
ok() { echo "  ok   : $1"; }
no() { echo "  FAIL : $1 -- $2"; fails=$((fails+1)); }

echo "== frozen binaries (identical for both cores)"
for p in boot01_marker boot02_clint boot03_ddr boot04_badaddr; do cp $PREP/deploy-bundle/$p.elf $OUT/elf/; done
for p in ext01_m ext02_c ext03_a ext04_sv39; do cp $PREP/probes/build/$p.elf $OUT/elf/; done
for p in perf03_fetch perf04_where; do cp $PREP/probes/build-perf/$p.elf $OUT/elf/; done
bash "$CAMP/workloads/build-perf06.sh" "$OUT/perf06" > "$OUT/logs/perf06-build.log" 2>&1 \
  && cp "$OUT/perf06/perf06_iws.elf" "$OUT/elf/" \
  || { no "perf06 built" "see logs/perf06-build.log"; }
(cd "$OUT/elf" && sha256sum *.elf) > "$OUT/elf.sha256"
echo "  $(wc -l < "$OUT/elf.sha256") frozen ELFs, hashes in elf.sha256"

# One heavy build at a time, as the campaign rules require.
for v in ACC FIX; do
  d=$([ $v = ACC ] && echo baseline || echo fetch32)
  rtl=$([ $v = ACC ] && echo "$ACC" || echo "$FIX")
  echo "== verilating the harness against the $d core"
  bash "$CAMP/tests/build-sim.sh" "$GEN" "$rtl" "$OUT/sim-$d" > "$OUT/logs/build-$d.log" 2>&1
  if grep -q SIM_BUILD_OK "$OUT/logs/build-$d.log"; then ok "$d sim built"
  else no "$d sim built" "$(grep -m2 -E '%Error|SIM_BUILD_FAIL' "$OUT/logs/build-$d.log" | head -2)"; fi
done
[ $fails = 0 ] || { echo "STAGE1_SOC fails=$fails (stopped: no simulator to run)"; exit 1; }

# Per-probe cycle bounds, sized from what the work actually is rather than from one generous number.
# The harness emits a Chisel printf per REQ/RESP/COMMIT and per AXI beat, and it cannot be switched off
# in this build, so an oversized bound does not merely waste time -- the first attempt produced a 300 MB
# log in thirteen minutes and was still running. Attempt 1 is retained; this is a deliberate change,
# not a repeat.
cycles_for() {
  case "$1" in
    perf06_iws)  echo 12000000 ;;   # (70001 + 65729) retired at baseline CPI ~40, plus startup
    perf03_fetch|perf04_where) echo 6000000 ;;
    *)           echo 2000000 ;;    # the four boot gates complete in under 10k
  esac
}

run() {  # run <core> <prog> ; echoes the exit code. Output is AGGREGATED, not stored raw.
  # Separate statements, NOT `local core=$1 prog=$2 d=".../$core-$prog"`: the whole command line is
  # word-expanded before `local` runs, so $core is still unset when it is referenced and `set -u`
  # aborts. Attempt 2 died on exactly that, in every run, before any simulation happened.
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

echo "== the startup gates that this SIM configuration runs, on BOTH cores, same binaries"
# ext03_a is NOT in this list. Attempt 1 showed it running past 11.1 million cycles without finishing on
# the BASELINE core -- unmodified, accepted RTL -- with a trap every ~28 committed instructions. The
# established M3 sim regression only ever ran boot01-04; ext01-04 were built for HARDWARE, where all
# eight pass. So this is a property of atomics in this SoC configuration, not a fetch32 regression, and
# it is measured below rather than asserted.
for p in boot01_marker boot02_clint boot03_ddr boot04_badaddr ext01_m ext02_c ext04_sv39; do
  a=$(run baseline $p); f=$(run fetch32 $p)
  if [ "$a" = 0 ] && [ "$f" = 0 ]; then ok "$p: baseline 0, fetch32 0"
  else no "$p" "baseline exit=$a fetch32 exit=$f (a timeout is 124 and is a result, not a pass)"; fi
done

echo "== ext03_a: measured on both cores, and recorded rather than required"
a=$(run baseline ext03_a); f=$(run fetch32 ext03_a)
ca=$(python3 -c "import json;print(json.load(open('$OUT/runs/baseline-ext03_a/trace-counts.json'))['last_cycle'])" 2>/dev/null || echo "?")
cf=$(python3 -c "import json;print(json.load(open('$OUT/runs/fetch32-ext03_a/trace-counts.json'))['last_cycle'])" 2>/dev/null || echo "?")
echo "  baseline exit=$a last_cycle=$ca"
echo "  fetch32  exit=$f last_cycle=$cf"
if [ "$a" = "$f" ]; then ok "ext03_a behaves the SAME on both cores (exit $a) -- not a fetch32 regression"
else no "ext03_a differs between cores" "baseline exit=$a, fetch32 exit=$f: this WOULD be a fetch32 regression"; fi

echo "== the measurement probes, on both cores"
for p in perf03_fetch perf04_where perf06_iws; do
  [ -f "$OUT/elf/$p.elf" ] || { no "$p present" "not built"; continue; }
  a=$(run baseline $p); f=$(run fetch32 $p)
  [ "$a" = 0 ] && ok "$p on baseline: exit 0" || no "$p on baseline" "exit=$a"
  [ "$f" = 0 ] && ok "$p on fetch32:  exit 0" || no "$p on fetch32" "exit=$f"
done

echo "== architectural equivalence: every probe's own verdict and marker"
for p in boot01_marker boot02_clint boot03_ddr boot04_badaddr ext01_m ext02_c ext03_a ext04_sv39; do
  ma=$(grep -oE 'TEACHING-[A-Z0-9-]+-(OK|FAIL)|M3-[A-Z0-9-]+-(OK|FAIL)' "$OUT/runs/baseline-$p/console.txt" 2>/dev/null | head -1)
  mf=$(grep -oE 'TEACHING-[A-Z0-9-]+-(OK|FAIL)|M3-[A-Z0-9-]+-(OK|FAIL)' "$OUT/runs/fetch32-$p/console.txt" 2>/dev/null | head -1)
  if [ -n "$ma" ] && [ "$ma" = "$mf" ]; then ok "$p: both report $ma"
  else no "$p markers agree" "baseline='$ma' fetch32='$mf'"; fi
done

echo "== the counters, side by side (this is DATA, not a pass/fail)"
python3 - "$OUT" <<'PY'
import glob, os, re, sys, json
out = sys.argv[1]
rows = {}
for f in sorted(glob.glob(os.path.join(out, "runs", "*-perf*", "console.txt"))):
    core, prog = os.path.basename(os.path.dirname(f)).split("-", 1)
    for k, v in re.findall(r"^([A-Z0-9][A-Z0-9-]*)=([0-9a-fA-F]{16})\s*$", open(f, errors="replace").read(), re.M):
        rows.setdefault((prog, k), {})[core] = int(v, 16)
print(f"  {'probe':13}{'value':26}{'baseline':>12}{'fetch32':>12}{'ratio':>9}")
data = {}
for (prog, k), v in sorted(rows.items()):
    b, x = v.get("baseline"), v.get("fetch32")
    r = f"{b/x:.3f}" if (b and x) else "-"
    print(f"  {prog:13}{k:26}{b if b else '-':>12}{x if x else '-':>12}{r:>9}")
    data[f"{prog}/{k}"] = dict(baseline=b, fetch32=x)
json.dump(data, open(os.path.join(out, "counters.json"), "w"), indent=2)
PY
echo "STAGE1_SOC fails=$fails"
[ $fails = 0 ]
