#!/usr/bin/env bash
# MC-M1 T1.4-T1.8: the bare-metal probe set on an RD2 integration simulator built from a NAMED generated
# Verilog and a NAMED cpu RTL directory. Run it once with the BEFORE generator output and once with the
# AFTER (TeachingHart) output, same RTL, and compare-probes.sh diffs the two.
#
# Every run records: exit code, the probe's own verdict marker, the harness's "Completed after N cycles",
# the probe's console (for the ROI counters, gen_stage_metrics.py reads runs/<label>-<prog>/console.txt),
# and -- when the configuration traces -- the full COMMIT/TRAP sequence, cycle-stripped and with cycles.
#
#   rd2-probes.sh <generated.v> <cpu-rtl-dir> <label> <fresh outdir> [trace]
#   ELFDIR=<frozen set from freeze-elfs.sh>   reuse the same bytes on both sides instead of building here
#   ONLY="prog ..."                             restrict the set (the tracing configuration prints per event)
#
# The verdict per run comes from probe_console.py -- the same module the comparator uses -- so what the
# runner prints and what the comparison judges cannot drift apart (closeout item 1).
set -u
cd /home/engineer/fpga
R=/home/engineer/fpga; WS=$R/teaching-cpu-work; FZ=$WS/fpga-zynq; TC=$R/experiments/teaching-cpu
PREP=$TC/xv6-board-prep
CAMP=$R/worktrees/mc-dual-backend/experiments/IPS-campaign
V=${1:?generated verilog}; RTL=${2:?cpu rtl dir}; LABEL=${3:?label}; OUT=${4:?outdir}; TRACE=${5:-}
[ -s "$V" ] || { echo "REFUSE: missing $V"; exit 2; }
[ -d "$RTL" ] || { echo "REFUSE: missing rtl $RTL"; exit 2; }
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT/logs" "$OUT/elf" "$OUT/runs"
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
fails=0; infra=0
ok() { echo "  ok   : $1"; }
no() { echo "  FAIL : $1 -- $2"; fails=$((fails+1)); }

echo "== simulator: $LABEL"
echo "   generated: $V ($(sha256sum "$V" | cut -c1-16))"
echo "   rtl:       $RTL ($(sha256sum "$RTL/tcpu_core.v" | cut -c1-16))"
s=$(date +%s)
bash "$CAMP/tests/build-xv6-sim.sh" "$V" "$RTL" "$OUT/sim" > "$OUT/logs/build.log" 2>&1
e=$(date +%s)
grep -q XV6_SIM_BUILD_OK "$OUT/logs/build.log" || { echo "INFRA: simulator build failed ($((e-s)) s)"; grep -m3 -E '%Error|FAIL' "$OUT/logs/build.log"; exit 1; }
echo "   built in $((e-s)) s: $(grep obj_dir/sim "$OUT/sim/inputs.sha256" | cut -c1-16)"
SIM=$OUT/sim/obj_dir/sim

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -n "${ELFDIR:-}" ]; then
  echo "== programs: the FROZEN set $ELFDIR (same bytes for every run that names it)"
  [ -s "$ELFDIR/elf.sha256" ] && [ -s "$ELFDIR/elf-load.sha256" ] || { echo "REFUSE: $ELFDIR is not a frozen set (elf.sha256 / elf-load.sha256)"; exit 2; }
  cp "$ELFDIR"/elf/* "$OUT/elf/"
  (cd "$OUT/elf" && sha256sum *) | diff -q - "$ELFDIR/elf.sha256" >/dev/null || { echo "REFUSE: copied programs do not match $ELFDIR/elf.sha256"; exit 2; }
fi
if [ -z "${ELFDIR:-}" ]; then
echo "== programs (frozen binaries where the campaign froze them; the rest built here and hashed)"
for p in boot01_marker boot02_clint boot03_ddr boot04_badaddr; do cp "$PREP/deploy-bundle/$p.elf" "$OUT/elf/"; done
for p in ext01_m ext02_c ext03_a ext04_sv39; do cp "$PREP/probes/build/$p.elf" "$OUT/elf/"; done
for p in perf02_sv39 perf03_fetch perf04_where; do cp "$PREP/probes/build-perf/$p.elf" "$OUT/elf/"; done
bash "$CAMP/workloads/build-perf06.sh" "$OUT/b-perf06" > "$OUT/logs/perf06-build.log" 2>&1 \
  && cp "$OUT/b-perf06/perf06_iws.elf" "$OUT/elf/" || { echo "INFRA: perf06 build"; infra=$((infra+1)); }
for t in tlb01 tlb02 cache01; do
  bash "$CAMP/workloads/build-$t.sh" "$OUT/b-$t" > "$OUT/logs/$t-build.log" 2>&1 \
    && cp "$OUT/b-$t"/*.elf "$OUT/elf/" || { echo "INFRA: $t build"; infra=$((infra+1)); }
done
GCC=riscv64-unknown-elf-gcc
CF="-mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -I$WS/cpu/m3tests"
$GCC -march=rv64imc_zicsr $CF -T $TC/m2-prep/tests/link.ld -o "$OUT/elf/boot11_sv39.elf" \
  $TC/cpu-sv39/tests/boot11_sv39.S $WS/cpu/m3tests/htif.S 2> "$OUT/logs/boot11-build.log" || { echo "INFRA: boot11 build"; infra=$((infra+1)); }
$GCC -march=rv64iac_zicsr $CF -T $TC/m2-prep/tests/link.ld -o "$OUT/elf/boot12_amo.elf" \
  $TC/cpu-a/tests/boot12_amo.S $WS/cpu/m3tests/htif.S 2> "$OUT/logs/boot12-build.log" || { echo "INFRA: boot12 build"; infra=$((infra+1)); }
cp $R/xv6-on-rocket-pynq-z1/riscv-test/hello.riscv "$OUT/elf/hello.riscv"
[ $infra = 0 ] || { echo "PROBES infra=$infra (builds)"; exit 1; }
fi
# ONLY="a b c" restricts the set: the tracing configuration prints a line per event, which the long perf
# probes would turn into gigabytes, so those run on the trace-free configuration only
if [ -n "${ONLY:-}" ]; then
  for f in "$OUT"/elf/*; do p=$(basename "${f%.*}"); grep -qw "$p" <<<"$ONLY" || rm -f "$f"; done
  echo "   restricted to: $ONLY"
fi
(cd "$OUT/elf" && sha256sum *) > "$OUT/elf.sha256"
python3 "$HERE/elf_ident.py" "$OUT"/elf/* > "$OUT/elf-load.sha256"
echo "   $(wc -l < "$OUT/elf.sha256") programs"

# simulated-cycle budgets: the campaign's, sized from the slowest core, with headroom; ext03_a is the one
# the campaign could not complete in its (V1, no-atomic) harness -- here the atomic path exists, so it is
# run, generously, and reported as whatever it does
cycles_for() { case "$1" in
  perf02_sv39) echo 60000000 ;; perf06_iws) echo 18000000 ;; perf03_fetch|perf04_where) echo 12000000 ;;
  tlb01_sfence|tlb02_canonical) echo 12000000 ;; cache01_smc) echo 6000000 ;; ext03_a) echo 40000000 ;;
  boot12_amo|boot11_sv39|ext01_m|ext02_c|ext04_sv39) echo 6000000 ;; *) echo 4000000 ;; esac; }
WALL=${WALL:-1800}
echo "== runs (wall cap ${WALL}s each, cycle budget per program)"
printf '   %-16s %4s %6s %-28s %s\n' program exit wall verdict cycles
for elf in $(cd "$OUT/elf" && ls *.elf *.riscv 2>/dev/null); do
  prog=${elf%.*}; d="$OUT/runs/$LABEL-$prog"; mkdir -p "$d"
  s=$(date +%s)
  if [ -n "$TRACE" ]; then
    set -o pipefail
    timeout "$WALL" "$SIM" +max-cycles=$(cycles_for "$prog") "$OUT/elf/$elf" 2>&1 \
      | tee >(grep -oE 'EV +[0-9]+ +(COMMIT|TRAP) .*$' | sed -E 's/^EV +([0-9]+) +/\1 /' > "$d/commits-cyc.txt") \
      | python3 "$CAMP/tests/trace_aggregate.py" --out "$d" > "$d/aggregate.txt" 2>&1
    rc=${PIPESTATUS[0]}; set +o pipefail
    sed -E 's/^[0-9]+ //' "$d/commits-cyc.txt" > "$d/commits.txt"
  else
    set -o pipefail
    timeout "$WALL" "$SIM" +max-cycles=$(cycles_for "$prog") "$OUT/elf/$elf" 2>&1 \
      | python3 "$CAMP/tests/trace_aggregate.py" --out "$d" > "$d/aggregate.txt" 2>&1
    rc=${PIPESTATUS[0]}; set +o pipefail
  fi
  e=$(date +%s); echo "$rc" > "$d/exit"
  line=$(python3 "$HERE/probe_console.py" "$d"); pc=$?
  marker=$(grep -oE 'marker=[^ ]+' <<<"$line" | cut -d= -f2); cyc=$(grep -oE 'cycles=[^ ]+' <<<"$line" | cut -d= -f2)
  printf '   %-16s %4s %6s %-28s %s\n' "$prog" "$rc" "$((e-s))s" "$marker" "$cyc"
  echo "$line wall=$((e-s))" >> "$OUT/summary.txt"
done
echo "== verdicts"
for elf in $(cd "$OUT/elf" && ls *.elf *.riscv 2>/dev/null); do
  prog=${elf%.*}; d="$OUT/runs/$LABEL-$prog"
  line=$(python3 "$HERE/probe_console.py" "$d"); pc=$?
  reason=${line#*reason=}
  if [ -n "$TRACE" ] && [ ! -s "$d/commits.txt" ]; then pc=1; reason="$reason; tracing run has no COMMIT/TRAP evidence"; fi
  if [ $pc = 0 ]; then ok "$prog: $(grep -oE 'marker=[^ ]+' <<<"$line" | cut -d= -f2) $(grep -oE 'cycles=[^ ]+' <<<"$line") $([ -n "$TRACE" ] && grep -oE 'commits=[^ ]+' <<<"$line")"
  else no "$prog" "$reason (124 = wall timeout; the cycle budget ends with a non-zero exit too)"; fi
done
echo "PROBES label=$LABEL fails=$fails"
[ $fails = 0 ]
