#!/usr/bin/env bash
# Build one test program, simulate it against the core in $CORE, and judge the log.
#
#   run-test.sh [--expect PASS|FAIL] [--grep REGEX]... [-P NAME=VALUE]... <step> <test.S> <march> <tag>
#
# --expect FAIL is for mutants: the run must end in RESULT FAIL *and* every --grep pattern must appear in the
# log, so a mutant that is caught for the wrong reason, or not caught at all, is itself a failure.
set -u
EXPECT=PASS; GREPS=(); PARAMS=(); POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --expect) EXPECT=$2; shift 2 ;;
    --grep)   GREPS+=("$2"); shift 2 ;;
    -P)       PARAMS+=("-Ptb_step.$2"); shift 2 ;;
    *)        POS+=("$1"); shift ;;
  esac
done
[ ${#POS[@]} -eq 4 ] || { echo "usage: run-test.sh [--expect PASS|FAIL] [--grep RE]... [-P NAME=VALUE]... <step> <test.S> <march> <tag>"; exit 2; }
STEP=${POS[0]}; SRC=${POS[1]}; MARCH=${POS[2]}; TAG=${POS[3]}
: "${ROOT:?}" "${CORE:?}" "${OUT:?}" "${CC:?}" "${OBJCOPY:?}" "${NM:?}"
IVERILOG=${IVERILOG:-iverilog}; VVP=${VVP:-vvp}
name=$(basename "$SRC" .S); dir=$OUT/$STEP; mkdir -p "$dir"
elf=$dir/$name.elf; hex=$dir/$name.hex; th=$dir/$name.tohost; sim=$dir/$name.$TAG.vvp; log=$dir/$name.$TAG.log
core_srcs=$(ls "$CORE"/*.v 2>/dev/null) || { echo "run-test: no .v files in CORE=$CORE"; exit 2; }

$CC -march=$MARCH -mabi=lp64 -nostdlib -nostartfiles -static -Wl,--no-relax -Wl,--no-warn-rwx-segments -I"$ROOT/teaching/$STEP" -I"$ROOT/tests/cpu/tests2" \
    -T "$ROOT/software/probes/link.ld" -o "$elf" "$SRC" || exit 2
python3 "$ROOT/teaching/tools/elf2hex.py" "$OBJCOPY" "$NM" "$elf" "$hex" "$th" >/dev/null || exit 2
$IVERILOG -g2005 -I "$ROOT/rtl/cpu" -I "$CORE" ${PARAMS[@]+"${PARAMS[@]}"} -o "$sim" \
    "$ROOT/teaching/tb/tb_step.v" "$ROOT/tests/cpu/tb/tcpu_harness.v" $core_srcs || { echo "run-test: compile failed ($TAG)"; exit 2; }
$VVP -n "$sim" +hex="$hex" +tohost=$(cat "$th") ${MAXCYCLES:+ +maxcycles=$MAXCYCLES} ${VCD:+ +vcd=$dir/$name.$TAG.vcd} > "$log" 2>&1
result=$(grep -oE '^RESULT (PASS|FAIL)' "$log" | tail -1 | cut -d' ' -f2)
summary=$(grep -E '^(SUMMARY|TOHOST|TIMEOUT)' "$log" | tr '\n' ' ')
ok=1
[ "$result" = "$EXPECT" ] || ok=0
for g in ${GREPS[@]+"${GREPS[@]}"}; do grep -qE "$g" "$log" || { ok=0; echo "  missing in log: $g"; }; done
if [ $ok = 1 ]; then printf '  ok    %-10s %-16s %-8s %s\n' "$STEP" "$name" "$TAG" "$summary"; exit 0; fi
printf '  FAIL  %-10s %-16s %-8s expected %s, got %s -- %s\n' "$STEP" "$name" "$TAG" "$EXPECT" "${result:-none}" "$log"
grep -E 'PROTO ERROR|OBS ERROR|TIMEOUT|TRAP' "$log" | head -5 | sed 's/^/        /'
exit 1
