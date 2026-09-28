#!/usr/bin/env bash
#   run-icache-tb.sh <fresh outdir> [extra verilator args]
set -u
set -o pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
RTL=$(cd "$HERE/../../.." && pwd)/rtl/cpu
OUT=${1:?usage: run-icache-tb.sh <fresh outdir>}; shift || true
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT"
set +u; source /home/engineer/fpga/experiments/chipyard-env.sh >/dev/null 2>&1; set -u
command -v verilator >/dev/null || { echo "REFUSE: verilator unavailable"; exit 2; }
{ sha256sum "$RTL/tcpu_icache.v" "$RTL/tcpu_cacheable.v"; verilator --version; } > "$OUT/identities.txt"
( cd "$OUT" && verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-DECLFILENAME -j 3 \
    --top-module icache_tb "$@" -I"$RTL" -Mdir "$OUT/obj" -o tb \
    "$HERE/icache-tb/icache_tb.v" "$RTL/tcpu_icache.v" "$RTL/tcpu_cacheable.v" ) > "$OUT/build.log" 2>&1
[ -x "$OUT/obj/tb" ] || { echo "BUILD FAILED"; grep -m5 '%Error' "$OUT/build.log"; exit 1; }
timeout 300 "$OUT/obj/tb" > "$OUT/run.txt" 2>&1; rc=$?
cat "$OUT/run.txt"
[ $rc -eq 124 ] && { echo "ICACHE_TB TIMED OUT (a timeout is a result, not a pass)"; exit 1; }
[ $rc -ne 0 ] && { echo "ICACHE_TB exited $rc; a non-zero status is a failure whatever the output says"; exit 1; }
grep -q ICACHE_TB_OK "$OUT/run.txt" || { echo "ICACHE_TB did not report success (rc=$rc)"; exit 1; }
exit 0
