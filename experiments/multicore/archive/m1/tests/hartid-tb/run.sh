#!/usr/bin/env bash
# MC-M1 T1.1: mhartid reads HART_ID. Four builds of the SAME tcpu_core.v, each judged on THREE things:
# the build succeeded, the run's exit code is the one that case declares, and the marker matches.
#   omitted-default   no -G at all: the parameter's DEFAULT must be 0        exit 0, ...-OK
#   explicit-0        -GHART_ID=0                                          exit 0, ...-OK
#   nonzero-5         -GHART_ID=5, expecting 5                             exit 0, ...-OK
#   negctl-5-vs-0     -GHART_ID=5, expecting 0  (NEGATIVE CONTROL)         exit 134 ($fatal), ...-FAIL
# A timeout (124) or a build failure is never a pass and never a "rejected as expected".
#
#   run.sh <cpu-rtl-dir> <fresh outdir>
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RTL=${1:?cpu rtl dir}; OUT=${2:?fresh outdir}
[ -d "$RTL" ] || { echo "REFUSE: no rtl dir $RTL"; exit 2; }
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT"
set +u; source /home/engineer/fpga/experiments/chipyard-env.sh >/dev/null 2>&1; set -u
command -v verilator >/dev/null || { echo "REFUSE: verilator unavailable"; exit 2; }
ulimit -c 0
{ sha256sum "$RTL"/tcpu_*.v "$RTL"/tcpu_defs.vh "$HERE/hartid_tb.v" "$HERE/hartid_prog.S"; verilator --version; } > "$OUT/identities.txt"
riscv64-unknown-elf-gcc -mabi=lp64 -mcmodel=medany -march=rv64i_zicsr -nostdlib -nostartfiles -ffreestanding -O0 \
    -Wl,-Ttext=0x1000 -o "$OUT/prog.elf" "$HERE/hartid_prog.S" || { echo "PROG_BUILD_FAIL"; exit 1; }
riscv64-unknown-elf-objcopy -O binary --gap-fill 0 "$OUT/prog.elf" "$OUT/prog.bin" || exit 1
python3 - "$OUT/prog.bin" "$OUT/prog.hex" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
open(sys.argv[2], 'w').write("".join(f"{b:02x}\n" for b in data))
print(f"PROG_HEX_OK {len(data)} bytes")
PY
pass=0; fail=0
case_run() {  # case_run <label> <want-exit> <want-marker OK|FAIL> <verilator -G args...>
  local label=$1 wexit=$2 wmark=$3; shift 3; local d="$OUT/$label"
  mkdir -p "$d"; cp "$OUT/prog.hex" "$d/"
  verilator --binary --timing -Wno-fatal -Wno-WIDTH -Wno-DECLFILENAME -j 3 --top-module hartid_tb "$@" \
    -I"$RTL" -Mdir "$d/obj" -o tb "$HERE/hartid_tb.v" \
    "$RTL"/tcpu_core.v "$RTL"/tcpu_csr.v "$RTL"/tcpu_regfile.v "$RTL"/tcpu_muldiv.v "$RTL"/tcpu_cdecode.v \
    "$RTL"/tcpu_ptw.v "$RTL"/tcpu_xlate.v "$RTL"/tcpu_tlb.v "$RTL"/tcpu_icache.v "$RTL"/tcpu_ifill.v \
    "$RTL"/tcpu_cacheable.v "$RTL"/tcpu_permcheck.v > "$d/build.log" 2>&1 \
    || { echo "  FAIL : $label -- build failed: $(grep -m1 '%Error' "$d/build.log")"; fail=$((fail+1)); return; }
  (cd "$d" && timeout 120 ./obj/tb > run.txt 2>&1); local rc=$?; echo $rc > "$d/exit"
  local got; got=$(grep -oE "TEACHING-MC1-HARTID-(OK|FAIL)" "$d/run.txt" | head -1)
  local line; line=$(grep -m1 "HARTID_TB" "$d/run.txt")
  local why=""
  [ $rc = 124 ] && why="timeout (never a result)"
  [ -z "$why" ] && [ "$rc" != "$wexit" ] && why="exit $rc, this case declares $wexit"
  [ -z "$why" ] && [ "$got" != "TEACHING-MC1-HARTID-$wmark" ] && why="marker ${got:-none}, wanted ...-$wmark"
  if [ -z "$why" ]; then echo "  ok   : $label -> exit $rc, $got   ($line)"; pass=$((pass+1))
  else echo "  FAIL : $label -> $why   ($line)"; fail=$((fail+1)); fi
}
echo "== T1.1 mhartid reads HART_ID  (rtl: $RTL)"
case_run omitted-default 0   OK                       -GEXPECT=0      # no -GHART_ID: the default
case_run explicit-0      0   OK   -GHART_ID=0 -GEXPECT=0
case_run nonzero-5       0   OK   -GHART_ID=5 -GEXPECT=5
case_run negctl-5-vs-0   134 FAIL -GHART_ID=5 -GEXPECT=0
echo "HARTID_TB pass=$pass fail=$fail"
exit $([ $fail -eq 0 ] && echo 0 || echo 1)
