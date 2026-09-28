#!/usr/bin/env bash
# Run ONE program on ONE simulator into a fresh directory: console (trace-free, via trace_aggregate), the
# trace head/tail and counts, per-event COMMIT/TRAP lines per hart (tracing configurations), the HARTS line,
# exit code, wall time. Cycle budget and wall cap are arguments, never defaults.
#   run-dual.sh <sim> <elf> <outdir> <max-cycles> <wall-s> [plusargs...]
set -u; SIM=${1:?sim}; ELF=${2:?elf}; D=${3:?outdir}; MAXCYC=${4:?max-cycles}; WALL=${5:?wall}; shift 5
[ -x "$SIM" ] || { echo "REFUSE: no simulator $SIM"; exit 2; }; [ -s "$ELF" ] || { echo "REFUSE: no elf $ELF"; exit 2; }
[ -e "$D" ] && { echo "REFUSE: $D exists"; exit 2; }; mkdir -p "$D"
CAMP=/home/engineer/fpga/worktrees/mc-dual-backend/experiments/IPS-campaign/tests
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
{ echo "sim=$SIM"; echo "elf=$ELF ($(sha256sum $ELF | cut -c1-16))"; echo "max_cycles=$MAXCYC wall=$WALL plusargs=$*"; echo "start=$(date -u +%FT%TZ)"; } > "$D/cmd.txt"
s=$(date +%s)
set -o pipefail
timeout "$WALL" "$SIM" +max-cycles=$MAXCYC "$@" "$ELF" 2>&1 \
  | tee >(grep -oE '(EV|EVA|RD2|RD2H|RD2HOST|RBOOT|EVH) +[0-9]+ +[A-Z_]+.*$' > "$D/events.txt") \
  | python3 "$CAMP/trace_aggregate.py" --out "$D" > "$D/aggregate.txt" 2>&1
rc=${PIPESTATUS[0]}; set +o pipefail
e=$(date +%s); echo "$rc" > "$D/exit"; echo "wall_s=$((e-s))" >> "$D/cmd.txt"
# per-hart commit/trap streams (tracing configurations only); the full events file stays for the checker
grep -E '^EV +[0-9]+ +(COMMIT|TRAP) ' "$D/events.txt" | sed -E 's/^EV +([0-9]+) +/\1 /' > "$D/commits-cyc.txt"
grep -E '^(HARTS|AXI|CYCLES|RD2HOST FINAL|Completed after|\*\*\* FAILED)' "$D/console.txt" > "$D/final.txt"
# the program's own text: HTIF characters land wherever they fall in the stream, often as a prefix of a trace
# line (RD2 / RBOOT / AT / host lines are not EV lines, so trace_aggregate kept them whole). Recover it the way
# the M1 judge does: a line with a trace token keeps only what precedes the token; a line without one is text.
python3 - "$D/console.txt" "$D/console-clean.txt" <<'PY'
import re, sys
tok = re.compile(r'(RD2HOST|RD2H|RD2|RBOOT|AT|EVH|EVA|EV|HARTS n=|AXI ar=|CYCLES total=|Completed after|\*\*\* FAILED|TRACE_AGGREGATED)\b')
out = []
for ln in open(sys.argv[1], errors='replace').read().split('\n'):
    m = tok.search(ln)
    if m is None: out.append(ln + '\n')
    elif m.start() > 0: out.append(ln[:m.start()])
open(sys.argv[2], 'w').write(''.join(out))
PY
echo "RUN exit=$rc wall=$((e-s))s $(grep -oE 'Completed after [0-9]+ cycles|\*\*\* FAILED \*\*\*.*' "$D/console.txt" | head -1) $(grep -oE 'M2B-[A-Z]+-(OK|FAIL)[^A-Z]{0,80}' "$D/console-clean.txt" | head -1)" | tee "$D/verdict.txt"
exit $rc
