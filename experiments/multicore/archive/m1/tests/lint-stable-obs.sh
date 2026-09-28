#!/usr/bin/env bash
# MC-M1 T1.3: nothing outside the hart wrapper may read the multicycle core's implementation state.
#
# A grep, deliberately (codex-mc-m0-review-fixes D7: no compile-test framework for this). The SoC-layer
# scala -- everything in soc/scala/teaching except the two files that ARE the wrapper -- must not mention
# `.impl.`, `dbg_state`, `dbg_redirect` or `obs.state`. The negative control plants one reference in a
# throwaway copy and requires the lint to catch it, so a lint that matches nothing is seen to be a lint
# that matches nothing.
#
#   lint-stable-obs.sh <soc/scala/teaching dir>
set -u
D=${1:?scala dir}
[ -d "$D" ] || { echo "REFUSE: no dir $D"; exit 2; }
PAT='\.impl\.|dbg_state|dbg_redirect|obs\.state\b'
lint() {  # lint <dir> -> prints hits, returns count
  grep -nE "$PAT" "$1"/*.scala 2>/dev/null | grep -vE "^[^:]*(TeachingCpuBlackBox|TeachingHart)\.scala:" | grep -vE '^[^:]*:[0-9]+:\s*//'
}
echo "== T1.3 stable observation interface  (dir: $D)"
hits=$(lint "$D"); n=$(printf '%s' "$hits" | grep -c .)
if [ "$n" = 0 ]; then echo "  ok   : no SoC-layer reference to impl.state / dbg_state / dbg_redirect / obs.state"
else echo "  FAIL : $n reference(s):"; printf '%s\n' "$hits" | sed 's/^/      /'; fi
# negative control, on a copy
T=$(mktemp -d); cp "$D"/*.scala "$T/"
printf '\n// planted for the lint negative control\nobject MC1LintCanary { def peek(x: TeachingCpuImplObs) = x.state }\n' >> "$T/RD2Soc.scala"
sed -i 's/x\.state/x.state; val y = 0 \/\/ dbg_state/' "$T/RD2Soc.scala"
m=$(lint "$T" | grep -c .); rm -rf "$T"
if [ "$m" -ge 1 ]; then echo "  ok   : negative control: a planted reference is caught ($m hit)"
else echo "  FAIL : negative control: the planted reference was NOT caught -- the lint is vacuous"; n=$((n+1)); fi
echo "LINT_STABLE_OBS fails=$n"
[ "$n" = 0 ]
