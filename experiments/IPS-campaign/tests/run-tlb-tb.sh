#!/usr/bin/env bash
# Component tests for the TLB and the permission check, before either is wired into the core.
#   run-tlb-tb.sh <fresh outdir> [extra verilator args]
set -u
set -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
RTL=$(cd "$HERE/../../.." && pwd)/rtl/cpu
OUT=${1:?usage: run-tlb-tb.sh <fresh outdir>}; shift || true
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT"
set +u; source /home/engineer/fpga/experiments/chipyard-env.sh >/dev/null 2>&1; set -u
command -v verilator >/dev/null || { echo "REFUSE: verilator unavailable"; exit 2; }
{ sha256sum "$RTL/tcpu_tlb.v" "$RTL/tcpu_permcheck.v"; verilator --version; } > "$OUT/identities.txt"
cat "$OUT/identities.txt"
( cd "$OUT" && verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-DECLFILENAME -j 3 \
    --top-module tlb_tb "$@" -I"$RTL" -Mdir "$OUT/obj" -o tb \
    "$HERE/tlb-tb/tlb_tb.v" "$RTL/tcpu_tlb.v" "$RTL/tcpu_permcheck.v" ) > "$OUT/build.log" 2>&1
[ -x "$OUT/obj/tb" ] || { echo "BUILD FAILED"; grep -m5 '%Error' "$OUT/build.log"; exit 1; }
timeout 300 "$OUT/obj/tb" > "$OUT/run.txt" 2>&1
rc=$?
cat "$OUT/run.txt"
[ $rc -eq 124 ] && { echo "TLB_TB TIMED OUT (a timeout is a result, not a pass)"; exit 1; }
grep -q TLB_TB_OK "$OUT/run.txt" || { echo "TLB_TB did not report success (rc=$rc)"; exit 1; }
exit 0
