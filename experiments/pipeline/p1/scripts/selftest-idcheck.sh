#!/bin/bash
# PIPE-P1: self-test of the build identity gate (idcheck.sh). Cheap: stubbed commands plus two --lint-only elaborations.
#   selftest-idcheck.sh <a sims dir with src/, e.g. runs/sims-4> <fresh work dir>
# Each case states the verdict the gate must give. The gate passes only if every case gets its stated verdict.
set -u
SIMS=${1:?sims dir}; OUT=${2:?work dir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p $OUT; IDOUT=$OUT
. "$(dirname "$(readlink -f "$0")")/idcheck.sh"
S=$SIMS/src; ok=0; n=0
expect() {  # expect <OK|FAIL> <label> <regex> <args...>: run one idcheck, compare the verdict
  local want=$1; shift
  local line; line=$(idcheck "$@"); echo "   $line"
  local got
  case "$line" in IDFAIL*) got=FAIL;; IDOK*) got=OK;; *) got=NONE;; esac
  n=$((n+1)); if [ $got = $want ]; then ok=$((ok+1)); echo "case $1: want $want got $got  PASS"; else echo "case $1: want $want got $got  WRONG"; fi
}
# expect runs idcheck in a subshell ($(...)); the aggregation case at the end checks ID_FAILS in the calling shell.
# ---- stubbed build commands: gate logic
# idcheck runs "timeout 900 $VL", so the stubs are small executables, not shell functions
mkdir -p $OUT/bin
mk() { printf '#!/bin/bash\n%s\n' "$2" > $OUT/bin/$1; chmod +x $OUT/bin/$1; }
mk stub_ok    'echo built; exit 0'
mk stub_tmo   "echo \"%Error: Cannot find file containing module: 'tcpu_core_pipe'\"; exit 124"
mk stub_other 'echo "%Error: foo.v:1:1: syntax error, unexpected IDENTIFIER"; exit 1'
mk stub_right "echo \"%Error: x.v:178:3: Cannot find file containing module: 'tcpu_core_pipe'\"; exit 1"
mk stub_okmsg "echo \"%Warning: x.v:178:3: Cannot find file containing module: 'tcpu_core_pipe'\"; exit 0"
mk stub_near  "echo \"%Error: x.v:198:3: Cannot find file containing module: 'tcpu_core_pipe'\"; exit 1"
RX="Cannot find file containing module: 'tcpu_core_pipe'"
VL=$OUT/bin/stub_ok;    expect FAIL build-succeeds    "$RX"
VL=$OUT/bin/stub_okmsg; expect FAIL build-succeeds-with-message "$RX"   # the expected text alone is not enough
VL=$OUT/bin/stub_tmo;   expect FAIL timeout-124       "$RX"
VL=$OUT/bin/stub_other; expect FAIL unrelated-error   "$RX"
VL=$OUT/bin/stub_right; expect OK   expected-error    "$RX"
VL=$OUT/bin/stub_near;  expect FAIL near-miss-module  "Cannot find file containing module: 'tcpu_core'"   # tcpu_core_pipe must not satisfy 'tcpu_core'
# ---- real elaborations (--lint-only, no C++ build)
VL="verilator --lint-only -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED --top-module TeachingTop"
PL="$S/pipeline/tcpu_core_pipe.v $S/rtl/tcpu_regfile.v $S/rtl/tcpu_csr.v $S/rtl/tcpu_icache.v $S/rtl/tcpu_cacheable.v"
TB="$S/tb/tcpu_top.v $S/tb/tcpu_harness.v"
# the sims-1 bug: -I at the full RTL directory lets the wrong selection find tcpu_core.v and elaborate
expect FAIL real-rtl-dir-fallback "Cannot find file containing module: 'tcpu_core'" -I$S/rtl $PL $TB
# the fixed include-only directory: the same wrong selection is refused for the stated reason
expect OK   real-inc-only         "Cannot find file containing module: 'tcpu_core'" -I$S/inc $PL $TB
# ---- aggregation: ID_FAILS counts the failures in the calling shell (as build-sims.sh uses it)
ID_FAILS=0; VL=$OUT/bin/stub_ok; idcheck agg-a "$RX" >/dev/null; VL=$OUT/bin/stub_right; idcheck agg-b "$RX" >/dev/null; VL=$OUT/bin/stub_other; idcheck agg-c "$RX" >/dev/null
n=$((n+1)); if [ $ID_FAILS = 2 ]; then ok=$((ok+1)); echo "case aggregation: ID_FAILS=$ID_FAILS (want 2)  PASS"; else echo "case aggregation: ID_FAILS=$ID_FAILS (want 2)  WRONG"; fi
echo "SELFTEST_IDCHECK $ok/$n"; [ $ok = $n ]
