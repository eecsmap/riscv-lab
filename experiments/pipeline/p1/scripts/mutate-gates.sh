#!/bin/bash
# PIPE-P1: mutation test of the runner gates themselves. Each mutant removes ONE check from a COPY of a gate script and
# reruns that gate's self-test on the copy; the mutant counts as caught only if the self-test then fails.
#   mutate-gates.sh <run dir, e.g. runs/run-3> <its de-duplicated coverage file> <sims dir, e.g. runs/sims-4> <fresh work dir>
set -u
RUN=${1:?run}; COV=${2:?coverage}; SIMS=${3:?sims}; OUT=${4:?work}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
SC=$(dirname "$(readlink -f "$0")"); mkdir -p $OUT; caught=0; n=0
mut() {  # mut <script> <selftest> <name> <exact old text> <new text> <selftest args...>
  local f=$1 st=$2 name=$3 old=$4 new=$5; shift 5; local d=$OUT/$name; mkdir $d; cp $SC/$f $SC/$st $d/
  python3 - "$d/$f" "$old" "$new" <<'PY' || { echo "mutant $name: TEXT NOT FOUND ONCE (the mutant is invalid)"; n=$((n+1)); return; }
import sys; p, o, s2 = sys.argv[1:]; s = open(p).read()
if s.count(o) != 1: sys.exit(1)
open(p, 'w').write(s.replace(o, s2))
PY
  bash $d/$st "$@" $d/w > $d/out.txt 2>&1; local rc=$?; n=$((n+1))
  local red; red=$(grep -E 'WRONG|^FAIL ' $d/out.txt | sed -E 's/^case ([^:]*):.*/\1/; s/^FAIL ([^:]*):.*/\1/' | tr '\n' ' ')
  if [ $rc != 0 ]; then caught=$((caught+1)); echo "caught   $name: $(tail -1 $d/out.txt); red: $red"; else echo "SURVIVED $name: $(tail -1 $d/out.txt)"; fi
}
# ---- identity gate
mut idcheck.sh selftest-idcheck.sh id-rc0    'if [ $rc = 0 ]; then'   'if false; then'   $SIMS
mut idcheck.sh selftest-idcheck.sh id-rc124  'elif [ $rc = 124 ]; then' 'elif false; then' $SIMS
mut idcheck.sh selftest-idcheck.sh id-regex  'elif ! grep -qE "$rx" $log; then' 'elif false; then' $SIMS
# ---- strict differential
mut p1diff.py selftest-p1diff.sh d-exit   "if ec != '0': fails.append" "if False: fails.append" $RUN
mut p1diff.py selftest-p1diff.sh d-done   "if not DONE.search(rd(pre + '.log')): fails.append" "if False: fails.append" $RUN
mut p1diff.py selftest-p1diff.sh d-empty  "            fails.append(f'{side}: empty retirement stream')" "            pass" $RUN
mut p1diff.py selftest-p1diff.sh d-strict "strict = '--require-complete' in args" "strict = False" $RUN
mut p1diff.py selftest-p1diff.sh d-stream "if cm != cp:" "if False:" $RUN
# ---- verdict
V="p1verdict.py selftest-verdict.sh"
mut $V v-exc-exact  'if st[impl] != exc[0]:' 'if False:' $RUN $COV
mut $V v-pos-pass   'elif st[impl] != "PASS":' 'elif False:' $RUN $COV
mut $V v-a-missing  'if p not in seen: bad.append' 'if False: bad.append' $RUN $COV
mut $V v-a-extra    'if p not in A_PROGRAMS: bad.append' 'if False: bad.append' $RUN $COV
mut $V v-b-count    'if len(res) != nb:' 'if False:' $RUN $COV
mut $V v-b-exit     'DIFF_OK exit=0 retired' 'DIFF_OK exit=\d+ retired' $RUN $COV
mut $V v-b-total    'if not tot or not re.search(rf"B total' 'if False and not re.search(rf"B total' $RUN $COV
mut $V v-c-pass     'if ": PASS " not in l:' 'if False:' $RUN $COV
mut $V v-c-align    'if not re.search(r"\| aligned\(N' 'if False and not re.search(r"\| aligned\(N' $RUN $COV
mut $V v-c-na       'if prog != "p1_irq_cancel":' 'if False:' $RUN $COV
mut $V v-c-count    'if got != 3 * k:' 'if False:' $RUN $COV
mut $V v-d-caught   'elif not r[0].startswith("CAUGHT"):' 'elif False:' $RUN $COV
mut $V v-d-missing  'if not r: bad.append(f"D: knob {k}: no result")' 'if not r: pass' $RUN $COV
mut $V v-d-ctl      'if not l.endswith(": exit 0, errors 0"):' 'if False:' $RUN $COV
mut $V v-e-caught   'if "-> caught: " not in l:' 'if False:' $RUN $COV
mut $V v-f-count    'if len(blocks) != F_BLOCKS or len(rois)' 'if False and len(rois)' $RUN $COV
mut $V v-g-changed  'for l in ch: bad.append' 'for l in []: bad.append' $RUN $COV
mut $V v-cov-zero   'elif int(vals[k]) == 0:' 'elif False:' $RUN $COV
mut $V v-cov-header 'if not m: bad.append("coverage: header' 'if False: bad.append("coverage: header' $RUN $COV
mut $V v-exit       'sys.exit(1 if bad else 0)' 'sys.exit(0)' $RUN $COV
echo "GATE_MUTANTS caught $caught/$n"; [ $caught = $n ]
