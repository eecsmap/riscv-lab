#!/usr/bin/env bash
# Stage 1 port-level regression, reviewer-rerunnable from this tree.
#
# Three cores, one command: the accepted baseline, this branch's fetch32, and a mutant carrying the
# ACTUAL first-version defect. The mutant must FAIL, and must fail having reached the translated path --
# a test that cannot catch the defect it was written for is worth nothing.
#
#   run-stage1-port.sh <fresh outdir>
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
CAMP=$(cd "$HERE/.." && pwd)
FIX=$(cd "$CAMP/../.." && pwd)/rtl/cpu                       # this worktree: ips-fetch32
ACC=/home/engineer/fpga/worktrees/ips-baseline/rtl/cpu       # the verified accepted configuration
MUT=$CAMP/rtl-mutant
OUT=${1:?usage: run-stage1-port.sh <fresh outdir>}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
set +u; source /home/engineer/fpga/experiments/chipyard-env.sh >/dev/null 2>&1; set -u
command -v verilator >/dev/null || { echo "REFUSE: verilator is not available"; exit 2; }
echo "  accepted : $ACC"
echo "  fetch32  : $FIX"
echo "  mutant   : $MUT"
mkdir -p "$OUT"
{ verilator --version; echo "accepted $(sha256sum $ACC/tcpu_core.v | cut -c1-16)"
  echo "fetch32  $(sha256sum $FIX/tcpu_core.v | cut -c1-16)"
  echo "mutant   $(sha256sum $MUT/tcpu_core.v | cut -c1-16)"; } > "$OUT/identities.txt"
cat "$OUT/identities.txt"
bash "$HERE/port-tb/run-port-tb.sh" "$ACC" "$FIX" "$MUT" "$OUT"
