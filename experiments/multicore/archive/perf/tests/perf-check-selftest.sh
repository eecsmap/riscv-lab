#!/bin/bash
# MC-PERF judge self-test: the positive record must PASS; each mutation must FAIL for its own reason.
#   perf-check-selftest.sh <passing run dir> <work dir> [judge args...]
set -u; SRC=${1:?passing run dir}; W=${2:?work dir}; shift 2; J=$(dirname "$0")/perf_check.py; ARGS="$*"
rm -rf "$W"; mkdir -p "$W"; pass=0; total=0
t() { # t <name> <expected-substring-in-FAIL-reason> <sed script applied to console.txt> [file]
  local name=$1 want=$2 sed_=$3 file=${4:-run/console.txt}; total=$((total+1)); cp -r "$SRC" "$W/$name"
  sed -i -E "$sed_" "$W/$name/$file"; out=$(python3 "$J" "$W/$name" $ARGS 2>&1); rc=$?
  # the expected reason must appear in a "  FAIL:" REASON line, not merely anywhere in the output (the work dir's own name
  # contains words like "checksum" and "inconsistent", which would otherwise satisfy the check vacuously)
  reasons=$(grep -E '^  FAIL:' <<<"$out")
  if [ $rc -ne 0 ] && grep -qF -- "$want" <<<"$reasons"; then pass=$((pass+1)); echo "ok   $name -> $(grep -m1 -F -- "$want" <<<"$reasons" | cut -c1-110)"; else echo "FAIL $name rc=$rc: $(tail -2 <<<"$out" | tr '\n' ' ' | cut -c1-160)"; fi; }
total=$((total+1)); if python3 "$J" "$SRC" $ARGS > "$W/positive.txt" 2>&1; then pass=$((pass+1)); echo "ok   positive: $(grep -E '^PASS' "$W/positive.txt")"; else echo "FAIL positive"; cat "$W/positive.txt"; fi
t ok0            'ok=0'                       's/(PERF-COMPUTE .*) ok=1/\1 ok=0/'
t children3      'children=3'                 's/(PERF-COMPUTE .*) children=4/\1 children=3/'
t child-missing  'child lines'                '/^PERF-COMPUTE-CHILD2 /d'
t child-dup      'child lines'                's/^(PERF-COMPUTE-CHILD1 .*)$/\1\n\1/'
t child-MISSING  'result missing'             's/^(PERF-ARRAY-CHILD3 checksum=)[0-9a-f]+/\1MISSING/'
t checksum-wrong 'checksum'                   's/^(PERF-COMPUTE-CHILD0 checksum=)([0-9a-f])/\1f/'
t checksum-wrong2 'checksum'                  's/^(PERF-ARRAY-CHILD0 checksum=[0-9a-f]{14})ff$/\100/; t; s/^(PERF-ARRAY-CHILD0 checksum=[0-9a-f]{14})[0-9a-f]{2}$/\1ff/'
t dmtime-short   'too short'                  's/(PERF-ARRAY .*) mt0=([0-9]+) mt1=([0-9]+) dmtime=[0-9]+/\1 mt0=\3 mt1=\3 dmtime=0/'
t dmtime-inconsistent 'inconsistent'          's/(PERF-COMPUTE .*) dmtime=([0-9]+)/\1 dmtime=999999999/'
t mtime-backwards 'went backwards'            's/(PERF-COMPUTE .*) mt0=([0-9]+) mt1=([0-9]+) dmtime=([0-9]+)/\1 mt0=\3 mt1=\2 dmtime=\4/'
t ticks-exceed   'time bases disagree'        's/(PERF-COMPUTE .*) ticks=[0-9]+/\1 ticks=999999/'
t readcost-huge  'not negligible'             's/(PERF-COMPUTE .*) readcost=[0-9]+/\1 readcost=5000000/'
t run-order      'not one monotonic'          's/(PERF-ARRAY .*) mt0=([0-9]+) mt1=([0-9]+) dmtime=([0-9]+)/\1 mt0=1 mt1=2 dmtime=1/'
t mtt-nonmono    'not monotonic'              's/^(MTIME-READS [0-9]+ [0-9]+) ([0-9]+)/\1 1/'
t mtt-child-out  'shared time base'           's/^(MTIME-SHARED p0=[0-9]+) child=[0-9]+/\1 child=1/'
t mtt-ticks      'exceed the mtime delta'     's/^(MTIME-SHARED .*) ticks=[0-9]+/\1 ticks=999999/'
t mtt-spin       'spin checksum'              's/^(MTIME-SHARED .*) x=[0-9a-f]/\1 x=0/'
t mtt-missing    'no mtimetest'               '/^\$ mtimetest/,/^MTIME-DONE/d'
t size-wrong     'expected'                   's/PERF-COMPUTE size=[0-9]+/PERF-COMPUTE size=7/'
t no-done        'PERF-DONE'                  '0,/^PERF-DONE ok=1/s//PERF-DONE ok=X/'
t runner-rc      'runner exit'                's/XV6_RC=0/XV6_RC=1/' verdict.txt
t stop-record    'deliberately'               's/# stop: deliberate-stop-after-all-commands/# stop: no-shell-prompt/' run/stages.txt
echo "SELFTEST $pass/$total"; [ $pass -eq $total ]
