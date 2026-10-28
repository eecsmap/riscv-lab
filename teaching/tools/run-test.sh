#!/usr/bin/env bash
# Build one test program, simulate it against the core in $CORE, and judge the log.
#
#   run-test.sh [--expect PASS|FAIL] [--grep RE]... [--nogrep RE]... [--crt file.S]... [--cflag X]... [--plus ARG]...
#               [-P NAME=VALUE]... <step> <test.S> <march> <tag>
#   --watch SYM: pass +watch=<address of SYM>, the bench then prints WATCH counts for it
#   --nogrep: the pattern must NOT appear; --cflag: extra compiler flag (-DJALR_F3=3); --plus: a testbench plusarg (expect_trap=7)
#
# --expect FAIL is for mutants: the run must end in RESULT FAIL *and* every --grep pattern must appear in the
# log, so a mutant that is caught for the wrong reason, or not caught at all, is itself a failure.
set -u
EXPECT=PASS; GREPS=(); NOGREPS=(); PARAMS=(); POS=(); CRT=(); CFLAGS_X=(); PLUS=(); WATCH=
while [ $# -gt 0 ]; do
  case "$1" in
    --expect) EXPECT=$2; shift 2 ;;
    --grep)   GREPS+=("$2"); shift 2 ;;
    --crt)    CRT+=("$2"); shift 2 ;;
    --nogrep) NOGREPS+=("$2"); shift 2 ;;
    --cflag)  CFLAGS_X+=("$2"); shift 2 ;;
    --plus)   PLUS+=("+$2"); shift 2 ;;
    --watch)  WATCH=$2; shift 2 ;;
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
core_srcs=$(ls "$CORE"/*.v 2>/dev/null) || { echo "run-test: no .v files in CORE=$CORE"; echo "  your core goes there: run 'make step1-init' first, or point CORE= at a directory of core sources (CORE=../rtl/cpu is the reference)"; exit 2; }

$CC -march=$MARCH -mabi=lp64 -fno-pie -nostdlib -nostartfiles -static -Wl,--no-relax -Wl,--no-warn-rwx-segments ${CFLAGS_X[@]+"${CFLAGS_X[@]}"} -I"$ROOT/teaching/include" -I"$ROOT/teaching/$STEP" -I"$ROOT/tests/cpu/tests2" \
    -T "$ROOT/software/probes/link.ld" -o "$elf" "$SRC" ${CRT[@]+"${CRT[@]}"} || exit 2
python3 "$ROOT/teaching/tools/elf2hex.py" "$OBJCOPY" "$NM" "$elf" "$hex" "$th" >/dev/null || exit 2
if [ -n "$WATCH" ]; then   # --watch SYMBOL: count bus transactions aimed at that address
  waddr=$($NM "$elf" | awk -v s="$WATCH" '$3 == s { print $1 }')
  [ -n "$waddr" ] || { echo "run-test: no symbol $WATCH in $elf"; exit 2; }
  PLUS+=("+watch=${waddr: -8}")
fi
$IVERILOG -g2005 -I "$ROOT/rtl/cpu" -I "$CORE" ${PARAMS[@]+"${PARAMS[@]}"} -o "$sim" \
    "$ROOT/teaching/tb/tb_step.v" "$ROOT/tests/cpu/tb/tcpu_harness.v" $core_srcs || { echo "run-test: compile failed ($TAG)"; exit 2; }
$VVP -n "$sim" +hex="$hex" +tohost=$(cat "$th") ${PLUS[@]+"${PLUS[@]}"} ${MAXCYCLES:+ +maxcycles=$MAXCYCLES} ${VCD:+ +vcd=$dir/$name.$TAG.vcd} > "$log" 2>&1
result=$(grep -oE '^RESULT (PASS|FAIL)' "$log" | tail -1 | cut -d' ' -f2)
summary=$(grep -E '^(SUMMARY|TOHOST|TIMEOUT)' "$log" | tr '\n' ' ')
ok=1
[ "$result" = "$EXPECT" ] || ok=0
# @SYM@ in a pattern is replaced by the 8-hex-digit address of SYM in this ELF, so a log line can be checked
# against a label in the test program (fire_pc=@target_insn@)
subst() { local g=$1 sym a; while [[ $g =~ @([A-Za-z_][A-Za-z0-9_]*)@ ]]; do sym=${BASH_REMATCH[1]};
  a=$($NM "$elf" | awk -v s="$sym" '$3 == s { print substr($1, length($1) - 7) }'); [ -n "$a" ] || a=NO_SUCH_SYMBOL_$sym;
  g=${g//@$sym@/$a}; done; printf '%s' "$g"; }
for g in ${GREPS[@]+"${GREPS[@]}"}; do g=$(subst "$g"); grep -qE "$g" "$log" || { ok=0; echo "  missing in log: $g"; }; done
for g in ${NOGREPS[@]+"${NOGREPS[@]}"}; do g=$(subst "$g"); grep -qE "$g" "$log" && { ok=0; echo "  forbidden in log: $g"; }; done
if [ $ok = 1 ]; then printf '  ok    %-10s %-16s %-8s %s\n' "$STEP" "$name" "$TAG" "$summary"; exit 0; fi
if [ "$result" = "$EXPECT" ]; then why="result $result as expected, but a required log condition failed"; 
else why="expected $EXPECT, got ${result:-none}"; fi
printf '  FAIL  %-10s %-16s %-8s %s -- %s\n' "$STEP" "$name" "$TAG" "$why" "$log"
grep -E '^(PROTO ERROR|OBS ERROR|TIMEOUT|TRAP STORM|HALT|TOHOST)' "$log" | head -5 | sed 's/^/        /'
exit 1
