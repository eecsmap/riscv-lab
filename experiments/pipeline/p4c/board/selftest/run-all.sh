#!/bin/bash
# PIPE-P4c: every offline self-test of the P4c board tooling (no board access). Exit 0 iff all pass.
H=$(cd "$(dirname "$0")" && pwd); bad=0
for t in "python3 $H/test-console-stop.py" "bash $H/test-freq-judge.sh" "bash $H/test-hart-check.sh" "bash $H/test-launcher.sh" "python3 $H/test-launch-test.py"; do
  out=$(timeout 900 $t 2>&1); r=$?; echo "$(tail -n 1 <<<"$out")  <- $t"; [ $r = 0 ] || { bad=$((bad+1)); echo "$out" | grep -v "^ok" | sed 's/^/    /'; }; done
echo "P4C_SELFTESTS $([ $bad = 0 ] && echo PASS || echo "FAIL $bad")"; [ $bad = 0 ]
