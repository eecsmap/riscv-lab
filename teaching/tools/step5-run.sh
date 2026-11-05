#!/usr/bin/env bash
# Run one program on the step-5 system simulator and judge it.
#   step5-run.sh <sim> <out-dir> <name> <source.S|.c>... [-- check-m3 options]
# The program is linked with tests/cpu/m3tests/htif.S (the console) and software/probes/link.ld (loaded at
# 0x8000_0000). @SYM@ in a check option is replaced by that symbol's address in the ELF (--sync-epc=0x@bad_load@).
# Without check options only the exit code is judged. Prints one ok/FAIL line plus what the program printed.
set -u
SIM=${1:?sim}; OUT=${2:?out dir}; NAME=${3:?name}; shift 3
SRCS=(); while [ $# -gt 0 ] && [ "$1" != "--" ]; do SRCS+=("$1"); shift; done; [ $# -gt 0 ] && shift
HERE=$(cd "$(dirname "$0")/.." && pwd); ROOT=$(cd "$HERE/.." && pwd); M3=$ROOT/tests/cpu/m3tests
CC=${CC:-riscv64-linux-gnu-gcc}; NM=${NM:-riscv64-linux-gnu-nm}
mkdir -p "$OUT"; elf=$OUT/$NAME.elf; log=$OUT/$NAME.log
$CC -march=rv64i_zicsr -mabi=lp64 -mcmodel=medany -O2 -ffreestanding -nostdlib -nostartfiles -static -fno-pie \
    -Wl,--no-relax -Wl,--no-warn-rwx-segments -I"$M3" -I"$HERE/step5" -T "$ROOT/software/probes/link.ld" \
    -o "$elf" "${SRCS[@]}" "$M3/htif.S" || exit 2
sym() { $NM "$elf" | awk -v s="$1" '$3 == s { print $1 }' | head -1; }
# </dev/null: run from a terminal, timeout puts the simulator in a background process group; if it then touches
# the terminal (fesvr reads stdin for console input) the kernel stops it, and the timer stops with it -- a silent hang
timeout "${WALL:-300}" "$SIM" +max-cycles="${MAXCYC:-600000}" "$elf" < /dev/null > "$log" 2>&1; ec=$?; echo $ec > "$OUT/$NAME.exit"
# the console bytes arrive on the simulator's stdout interleaved with the event lines: a character sits in front
# of the next line's tag ("hEV 1400 ..."), and a newline from the program shows up as an empty line
awk '{ if ($0 == "") printf "\n"; else if (match($0, /(EV|EVA|EVH|RD2) +[0-9]+ |AXI ar=|CYCLES total=/)) printf "%s", substr($0, 1, RSTART - 1) }' \
    "$log" > "$OUT/$NAME.console"
opts=(); for o in "$@"; do while [[ $o =~ @([A-Za-z_][A-Za-z0-9_]*)@ ]]; do
  a=$(sym "${BASH_REMATCH[1]}"); o=${o//@${BASH_REMATCH[1]}@/${a:-NO_SUCH_SYMBOL}}; done; opts+=("$o"); done
ok=1; why=
if [ $ec -ne 0 ]; then ok=0; why="simulator exit $ec: $(grep -m1 -E '\*\*\* FAILED|Assertion' "$log" | cut -c1-120)"; fi
if [ $ok = 1 ] && [ ${#opts[@]} -gt 0 ]; then
  python3 "$HERE/step5/check/check-m3.py" "$log" boot "${opts[@]}" > "$OUT/$NAME.check" 2>&1 || { ok=0; why="check: $(grep -m1 FAIL "$OUT/$NAME.check")"; }
  python3 "$HERE/step5/check/check-axi.py" "$log" > "$OUT/$NAME.axi" 2>&1 || { [ $ok = 1 ] && why="axi: $(grep -m1 FAIL "$OUT/$NAME.axi")"; ok=0; }
fi
cyc=$(grep -oE 'CYCLES total=[0-9]+' "$log" | cut -d= -f2)
if [ $ok = 1 ]; then printf '  ok    step5      %-16s cycles=%s console: %s\n' "$NAME" "${cyc:-?}" "$(head -c 70 "$OUT/$NAME.console" | tr '\n' ' ')"; exit 0; fi
printf '  FAIL  step5      %-16s %s -- %s\n' "$NAME" "$why" "$log"
printf '        console: %s\n' "$(head -c 200 "$OUT/$NAME.console" | tr '\n' ' ')"
grep -m3 -E '^\s+FAIL' "$OUT/$NAME.check" 2>/dev/null | sed 's/^ */        /'
python3 "$HERE/tools/step5-explain.py" "$log"
grep -qs "失败了先看哪里" "$HERE/step5/README.md" && echo "        symptom table: teaching/step5/README.md, section 失败了先看哪里"
exit 1
