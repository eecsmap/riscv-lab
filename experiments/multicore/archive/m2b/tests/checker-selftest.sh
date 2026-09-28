#!/usr/bin/env bash
# MC-M1 closeout item 5: the checkers, mutated. A comparator that has never been seen to reject is not a
# comparator. Synthetic BEFORE/AFTER run directories are built from scratch (real marker text, real
# console shape), the baseline must PASS, and each mutation must be REJECTED for the reason it plants.
#
#   checker-selftest.sh
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
set +u; source /home/engineer/fpga/experiments/chipyard-env.sh >/dev/null 2>&1; set -u
pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   : $1"; }
no() { fail=$((fail+1)); echo "  FAIL : $1 -- $2"; }
W=$(mktemp -d /home/engineer/fpga/.scratch/checker-selftest-XXXXXX)

# a tiny real ELF64 for the identity checks: entry 0x1000, one PT_LOAD with a known payload
mk_elf() {  # mk_elf <path> <entry-hex> <payload-text>
  riscv64-unknown-elf-gcc -mabi=lp64 -march=rv64i -nostdlib -nostartfiles -ffreestanding -O0 -Wl,-Ttext=$2 -Wl,-e,_start \
    -o "$1" -x assembler - <<EOF
.globl _start
.globl tohost
_start: nop; nop; j _start
.section .data
tohost: .dword 0
.ascii "$3"
EOF
}
# synthetic run: <dir> <label> <prog> <marker-text> <cycles> [trace]
mk_run() {
  local d=$1/runs/$2-$3; mkdir -p "$d"
  { echo "RD2               1 DRAIN_DONE epoch=    0"; echo "$4"; echo "Completed after $5 cycles"; echo "CYCLES total=$5 host_done_at=$5 drained=1"; } > "$d/console.txt"
  echo 0 > "$d/exit"
  [ "${6:-}" = trace ] && printf 'COMMIT pc=0x10040 insn=0x00000517\nCOMMIT pc=0x10044 insn=0xfc050513\nTRAP cause=0x7 epc=0x10048\n' > "$d/commits.txt"
}
mk_side() {  # mk_side <dir> <label> <elfdir> [trace]
  mkdir -p "$1/sim"; printf 'aaaa%060d  tcpu_core.v\nbbbb%060d  RD2Harness.X.v\n' 0 0 > "$1/sim/inputs.sha256"
  mk_run "$1" "$2" boot01_marker TEACHING-CPU-M3-OK 6386 ${4:-}
  mk_run "$1" "$2" boot12_amo    M3-AMO-OK          49519 ${4:-}
  (cd "$3" && sha256sum *) > "$1/elf.sha256"; python3 "$HERE/elf_ident.py" "$3"/* > "$1/elf-load.sha256"
}
fresh() { local t=${1:-}; rm -rf "$W/B" "$W/A"; mk_side "$W/B" before "$W/elf" "$t"; mk_side "$W/A" after "$W/elf" "$t"; }
cmp() { python3 "$HERE/compare-probes.py" "$W/B" "$W/A" --expect "boot01_marker boot12_amo" "$@" 2>&1; }
expect_reject() {  # expect_reject <label> <reason substring> <compare args...>
  local label=$1 why=$2; shift 2; local out; out=$(cmp "$@"); local rc=$?
  if [ $rc != 0 ] && grep -q "REJECT: .*$why" <<<"$out"; then ok "$label -> rejected: $(grep -m1 "REJECT: .*$why" <<<"$out" | sed 's/^ *//' | cut -c1-90)"
  else no "$label" "rc=$rc; wanted a REJECT mentioning '$why'; got: $(grep -m1 REJECT <<<"$out" | cut -c1-80)"; fi
}
mkdir -p "$W/elf"; mk_elf "$W/elf/boot01_marker.elf" 0x1000 payloadA; mk_elf "$W/elf/boot12_amo.elf" 0x1000 payloadB

echo "== 0. baseline: identical, healthy sides PASS (trace and untraced)"
fresh trace; out=$(cmp --trace); [ $? = 0 ] && ok "baseline trace: $(grep COMPARE <<<"$out")" || no "baseline trace" "$(grep -m1 REJECT <<<"$out")"
fresh;       out=$(cmp);         [ $? = 0 ] && ok "baseline untraced: $(grep COMPARE <<<"$out")" || no "baseline untraced" "$(grep -m1 REJECT <<<"$out")"

echo "== 1. both sides fail identically (non-zero exit) -- equality must NOT rescue them"
fresh trace; echo 1 > "$W/B/runs/before-boot12_amo/exit"; echo 1 > "$W/A/runs/after-boot12_amo/exit"
expect_reject "same non-zero exit on both sides" "exit=1 (0 required)" --trace
echo "== 2. a program missing on one side; every program missing"
fresh trace; rm -rf "$W/A/runs/after-boot12_amo";      expect_reject "missing program" "missing programs \['boot12_amo'\]" --trace
fresh trace; rm -rf "$W/A/runs"/*; mkdir -p "$W/A/runs"; expect_reject "all programs missing" "missing programs" --trace
echo "== 3. an extra program nobody expected"
fresh trace; mk_run "$W/A" after ext01_m TEACHING-EXT-M-OK 7021 trace; expect_reject "extra program" "extra programs \['ext01_m'\]" --trace
echo "== 4. trace mode without trace evidence must not degrade to untraced"
fresh trace; rm -f "$W/A/runs/after-boot01_marker/commits.txt"; expect_reject "trace evidence removed" "without COMMIT/TRAP evidence" --trace
echo "== 5. a FAIL marker appended after the success marker"
fresh trace; sed -i 's/^M3-AMO-OK$/M3-AMO-OK\nTEACHING-EXT-A-FAIL/' "$W/A/runs/after-boot12_amo/console.txt"; expect_reject "FAIL after OK" "failure marker present: TEACHING-EXT-A-FAIL" --trace
echo "== 6. the wrong success marker (another program's)"
fresh trace; sed -i 's/^M3-AMO-OK$/M3-SV39-OK/' "$W/A/runs/after-boot12_amo/console.txt"; expect_reject "wrong marker" "expected marker M3-AMO-OK absent" --trace
echo "== 7. no completion cycle count"
fresh trace; sed -i '/Completed after/d' "$W/A/runs/after-boot01_marker/console.txt"; expect_reject "cycles removed" "no completion cycle count" --trace
echo "== 8. ELF identity: same whole-file hash list but a different load entry; then different content"
fresh trace; mkdir -p "$W/elf2"; mk_elf "$W/elf2/boot01_marker.elf" 0x2000 payloadA; cp "$W/elf/boot12_amo.elf" "$W/elf2/"
python3 "$HERE/elf_ident.py" "$W/elf2"/* > "$W/A/elf-load.sha256"; expect_reject "entry moved (load identity)" "load-semantic identity.*differ" --trace
fresh trace; mkdir -p "$W/elf3"; mk_elf "$W/elf3/boot01_marker.elf" 0x1000 payloadZ; cp "$W/elf/boot12_amo.elf" "$W/elf3/"
python3 "$HERE/elf_ident.py" "$W/elf3"/* > "$W/A/elf-load.sha256"; (cd "$W/elf3" && sha256sum *) > "$W/A/elf.sha256"
expect_reject "content changed (whole-file and load identity)" "programs (whole-file sha256): differ" --trace
echo "== 9. elf_ident itself: entry, content and a symbol each change the digest; metadata does not"
d0=$(python3 "$HERE/elf_ident.py" "$W/elf/boot01_marker.elf" | cut -c1-16); d1=$(python3 "$HERE/elf_ident.py" "$W/elf2/boot01_marker.elf" | cut -c1-16); d2=$(python3 "$HERE/elf_ident.py" "$W/elf3/boot01_marker.elf" | cut -c1-16)
[ "$d0" != "$d1" ] && [ "$d0" != "$d2" ] && ok "elf_ident: entry change -> $d1, content change -> $d2, from $d0" || no "elf_ident insensitive" "$d0 $d1 $d2"
# metadata insensitivity is tested on a REAL frozen probe (linked by the campaign's script, so its PT_LOAD
# starts at .text); the tiny synthetic ELF above is linked without a script and its first PT_LOAD begins
# at file offset 0, i.e. it LOADS its own headers, so any header edit is -- correctly -- a load change
REAL=/home/engineer/fpga/experiments/multicore/m1/runs/closeout2-elf/elf/boot12_amo.elf   # M1's frozen set, reused by the M2a regression
if [ -f "$REAL" ]; then
  cp "$REAL" "$W/meta.elf"; dr=$(python3 "$HERE/elf_ident.py" "$REAL" | cut -c1-16)
  riscv64-unknown-elf-objcopy --add-section .note.mc1=/dev/null "$W/meta.elf" 2>/dev/null; riscv64-unknown-elf-strip --strip-debug "$W/meta.elf" 2>/dev/null
  d3=$(python3 "$HERE/elf_ident.py" "$W/meta.elf" | cut -c1-16); f3=$(sha256sum "$W/meta.elf" | cut -c1-16); fr=$(sha256sum "$REAL" | cut -c1-16)
  [ "$dr" = "$d3" ] && [ "$fr" != "$f3" ] && ok "elf_ident: on a real probe, strip/add-note changes the whole-file sha ($fr -> $f3) but not the load identity ($d3)" || no "elf_ident metadata-sensitive on a real probe" "$dr vs $d3 (file $fr vs $f3)"
else echo "  SKIP : metadata insensitivity needs the frozen set at $REAL"; fi
echo "== 10. the runner-side judge (probe_console.py) on the same evidence"
fresh trace; python3 "$HERE/probe_console.py" "$W/B/runs/before-boot12_amo" >/dev/null && ok "probe_console: healthy run ok" || no "probe_console healthy" ""
echo 124 > "$W/B/runs/before-boot12_amo/exit"; out=$(python3 "$HERE/probe_console.py" "$W/B/runs/before-boot12_amo"); [ $? != 0 ] && grep -q "exit=124 (0 required)" <<<"$out" && ok "probe_console: timeout exit rejected" || no "probe_console timeout" "$out"
rm -rf "$W"
echo "CHECKER_SELFTEST pass=$pass fail=$fail"
exit $([ $fail -eq 0 ] && echo 0 || echo 1)
