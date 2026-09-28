#!/usr/bin/env bash
# Port-level regression. Every case states what it expects; the script exits non-zero if any expectation
# is unmet.
#
# The previous version ended each run in `tb | tee | grep | sed`, so the exit status was sed's and a
# failing bench returned success. Nothing here is piped into a filter: the bench's output goes to a file
# and the file is examined.
#
#   run-port-tb.sh <accepted-rtl> <fixed-rtl> <mutant-rtl> <outdir>
set -u
set -o pipefail
ACC=${1:?accepted rtl dir}; FIX=${2:?fixed rtl dir}; MUT=${3:?mutant rtl dir}; OUT=${4:?outdir}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT"
fails=0
ok()  { echo "  ok   : $1"; }
no()  { echo "  FAIL : $1 -- $2"; fails=$((fails+1)); }

build_and_run() {   # build_and_run <tag> <rtl> <extra verilator args...>
  local tag=$1 rtl=$2; shift 2
  local d="$OUT/$tag"
  rm -rf "$d"; mkdir -p "$d"
  cp "$OUT/prog.hex" "$d/" || return 90
  ( cd "$d" && verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-UNSIGNED -Wno-DECLFILENAME \
      -Wno-BLKANDNBLK --top-module opt01_port_tb "$@" -j 3 -I"$rtl" -Mdir "$d/obj" -o tb \
      "$HERE/opt01_port_tb.v" "$rtl/tcpu_core.v" "$rtl/tcpu_regfile.v" "$rtl/tcpu_csr.v" \
      "$rtl/tcpu_muldiv.v" "$rtl/tcpu_cdecode.v" "$rtl/tcpu_ptw.v" ) > "$d/build.log" 2>&1
  local brc=$?
  [ $brc -ne 0 ] && { echo "    (build failed, rc=$brc)"; grep -m3 '%Error' "$d/build.log"; return 91; }
  ( cd "$d" && timeout 900 "$d/obj/tb" ) > "$d/run.txt" 2>&1
  local rrc=$?
  [ $rrc -eq 124 ] && { echo "    (bench timed out)"; return 92; }
  return 0
}

field() { grep -oE "$2=[0-9]+" "$OUT/$1/run.txt" | head -1 | cut -d= -f2; }
marker() { grep -oE 'TEACHING-OPT01-PORT-(OK|FAIL)' "$OUT/$1/run.txt" | head -1; }

echo "== assembling the program"
bash "$HERE/build-prog.sh" "$OUT" > "$OUT/prog-build.log" 2>&1 || { echo "  program build FAILED"; exit 2; }
grep -q PROG_HEX_OK "$OUT/prog-build.log" || { echo "  program build produced no image"; exit 2; }
ok "program assembled"

echo "== 1. the accepted core: correct, and issues no wide request"
build_and_run ACCEPTED "$ACC" || no "accepted core ran" "harness error"
[ "$(marker ACCEPTED)" = "TEACHING-OPT01-PORT-OK" ] && ok "accepted core passes" \
  || no "accepted core passes" "$(marker ACCEPTED)"
[ "$(field ACCEPTED wide)" = "0" ] && ok "  and never issues a 4-byte request" \
  || no "  and never issues a 4-byte request" "wide=$(field ACCEPTED wide)"

echo "== 2. the fixed core: correct, and exercises the TRANSLATED wide path"
build_and_run FIXED "$FIX" || no "fixed core ran" "harness error"
[ "$(marker FIXED)" = "TEACHING-OPT01-PORT-OK" ] && ok "fixed core passes" \
  || no "fixed core passes" "$(marker FIXED)"
[ "$(field FIXED sv39_wide)" -gt 0 ] 2>/dev/null && ok "  and issues wide requests under translation" \
  || no "  and issues wide requests under translation" "sv39_wide=$(field FIXED sv39_wide)"
[ "$(field FIXED violations)" = "0" ] && ok "  with no protocol violations" \
  || no "  with no protocol violations" "violations=$(field FIXED violations)"

echo "== 3. THE targeted regression: the original defect must be caught"
build_and_run MUTANT "$MUT" || no "mutant core ran" "harness error"
[ "$(marker MUTANT)" = "TEACHING-OPT01-PORT-FAIL" ] \
  && ok "the mutant (post-walk issue left at 2 bytes, consumption still wide) FAILS" \
  || no "the mutant FAILS" "it passed: this test cannot catch the defect it was written for"
[ "$(field MUTANT sv39_wide)" -gt 0 ] 2>/dev/null \
  && ok "  and it failed having actually reached the translated path" \
  || no "  and it failed having actually reached the translated path" "sv39_wide=0, so it failed early"

echo "== 4. the monitor catches a payload change on the ACCEPTING cycle"
build_and_run EDGE_STRONG "$FIX" -GEDGE_INJECT=1 || no "edge-inject ran" "harness error"
[ "$(field EDGE_STRONG violations)" -gt 0 ] 2>/dev/null \
  && ok "with injection, the monitor reports violations" \
  || no "with injection, the monitor reports violations" "violations=$(field EDGE_STRONG violations)"
build_and_run EDGE_WEAK "$FIX" -GEDGE_INJECT=1 -GMON_SKIP_ACCEPT=1 || no "weak monitor ran" "harness error"
[ "$(field EDGE_WEAK violations)" = "0" ] \
  && ok "  and the earlier valid&&!ready monitor sees NOTHING -- so case 4 is not vacuous" \
  || no "  the weak monitor also reported violations" "violations=$(field EDGE_WEAK violations)"

echo "== 5. the monitor catches a withdrawn request"
build_and_run WITHDRAW "$FIX" -GCORE_REQ_WITHDRAW=1 || no "withdrawal ran" "harness error"
[ "$(field WITHDRAW withdrawals)" -gt 0 ] 2>/dev/null \
  && ok "the core's own REQ_WITHDRAW fault is detected" \
  || no "the core's own REQ_WITHDRAW fault is detected" "withdrawals=$(field WITHDRAW withdrawals)"
[ "$(marker WITHDRAW)" = "TEACHING-OPT01-PORT-FAIL" ] && ok "  and the run is failed, not merely noted" \
  || no "  and the run is failed, not merely noted" "$(marker WITHDRAW)"

echo "PORT_TB_REGRESSION fails=$fails"
exit $([ $fails -eq 0 ] && echo 0 || echo 1)
