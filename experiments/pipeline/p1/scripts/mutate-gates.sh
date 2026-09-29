#!/bin/bash
# PIPE-P1: mutation test of the runner gates themselves. Each mutant removes ONE check from a COPY of a gate script and
# reruns that gate's self-test on the copy; the mutant counts as caught only if the self-test then fails.
#   mutate-gates.sh <run dir, e.g. runs/run-3> <its de-duplicated coverage file> <sims dir, e.g. runs/sims-4> <fresh work dir>
#   WBRUN=<p2a walker run dir> adds the walker-wrapper judge's mutants; P2RUN=<passing p2a run dir> the P2a verdict's
set -u
RUN=${1:?run}; COV=${2:?coverage}; SIMS=${3:?sims}; OUT=${4:?work}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
SC=$(dirname "$(readlink -f "$0")"); mkdir -p $OUT; caught=0; n=0
mut() {  # mut <script> <selftest> <name> <exact old text> <new text> <selftest args...>
  local f=$1 st=$2 name=$3 old=$4 new=$5; shift 5; local d=$OUT/$name; mkdir $d; cp $SC/$f $SC/$st $d/
  f=$(basename $f)
  python3 - "$d/$f" "$old" "$new" <<'PY' || { echo "mutant $name: TEXT NOT FOUND ONCE (the mutant is invalid)"; n=$((n+1)); return; }
import sys; p, o, s2 = sys.argv[1:]; s = open(p).read()
if s.count(o) != 1: sys.exit(1)
open(p, 'w').write(s.replace(o, s2))
PY
  bash $d/$(basename $st) "$@" $d/w > $d/out.txt 2>&1; local rc=$?; n=$((n+1))
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
mut $V v-h-variant  'if not [l for l in h if l.startswith' 'if False and [l for l in h if l.startswith' $RUN $COV
mut $V v-h-judge    'if "FW_JUDGE PASS" not in h:' 'if False:' $RUN $COV
mut $V v-exit       'sys.exit(1 if bad else 0)' 'sys.exit(0)' $RUN $COV
# ---- flush-window judge (section H), on the run's own bench logs
F="../flushwin/fwjudge.py ../flushwin/selftest-fwjudge.sh"
mut $F f-clean     'if fail_runs: bad.append(f"{fail_runs} failing runs' 'if False: bad.append(f"{fail_runs} failing runs' $RUN/H
mut $F f-window    'if cov[w] == 0: bad.append' 'if False: bad.append' $RUN/H
mut $F f-ref       'if ref is not None and sums != {ref}:' 'if False:' $RUN/H
mut $F f-codes     'if set(codes) != {"0"}:' 'if False:' $RUN/H
mut $F f-missing   'bad.append(f"missing {f}"); continue' 'continue' $RUN/H
mut $F f-total     'bad.append(f"rd{rd}-rs{rs}: no FW TOTAL line"); continue' 'pass' $RUN/H
mut $F f-notcaught 'if fail_runs == 0: bad.append(f"NOT CAUGHT' 'if False: bad.append(f"NOT CAUGHT' $RUN/H
mut $F f-other     'if other_props: bad.append' 'if False: bad.append' $RUN/H
mut $F f-lacks     'if lacking: bad.append' 'if False: bad.append' $RUN/H
mut $F f-exit      'sys.exit(1 if bad_all else 0)' 'sys.exit(0)' $RUN/H
# ---- walker-wrapper judge (P2a), only when a walker run is given as the fifth argument
if [ -n "${WBRUN:-}" ]; then
G="../../p2a/walker/wbjudge.py ../../p2a/walker/selftest-wbjudge.sh"
mut $G b-clean   'if fail_runs: bad.append(f"{fail_runs} failing runs")' 'if False: bad.append(f"{fail_runs} failing runs")' $WBRUN
mut $G b-class   'if cov[k] == 0: bad.append' 'if False: bad.append' $WBRUN
mut $G b-ref     'if not r or r.group(1) != REF:' 'if False:' $WBRUN
mut $G b-missing 'bad.append(f"missing {f}"); continue' 'continue' $WBRUN
mut $G b-total   'bad.append(f"gm{gm}-rd{rd}-rs{rs}: no WB TOTAL line"); continue' 'continue' $WBRUN
mut $G b-shared-count   'if len([l for l in sh if l.startswith("unchanged ")]) != 3 or' 'if False or' $WBRUN
mut $G b-shared-changed 'or any("CHANGED" in l for l in sh):' 'or False:' $WBRUN
mut $G b-caught  'if fail_runs == 0: bad.append("NOT CAUGHT")' 'if False: bad.append("NOT CAUGHT")' $WBRUN
mut $G b-profile 'if prop is not None and profile_fail == 0:' 'if False:' $WBRUN
mut $G b-first   'if other: bad.append' 'if False: bad.append' $WBRUN
mut $G b-exit    'sys.exit(1 if bad_all else 0)' 'sys.exit(0)' $WBRUN
fi
# ---- the P2a run verdict, only when a passing P2a run is given (P2RUN)
if [ -n "${P2RUN:-}" ]; then
Q="../../p2a/scripts/p2averdict.py ../../p2a/scripts/selftest-p2averdict.sh"
mut $Q q-a-m      'if not re.search(r"pipeline M exit 0 errors 0' 'if False and re.search(r"pipeline M exit 0 errors 0' $P2RUN
mut $Q q-a-c      'if not re.search(r"pipeline M\+C m01c' 'if False and re.search(r"pipeline M\+C m01c' $P2RUN
mut $Q q-a-noc    'if not ok: bad.append("A: a build without C' 'if False: bad.append("A: a build without C' $P2RUN
mut $Q q-a-p1     'if not m or m.group(1) == "0" or m.group(2) != m.group(3):' 'if False:' $P2RUN
mut $Q q-b-count  'if len(res) != nb:' 'if False:' $P2RUN
mut $Q q-b-line   'if not re.match(r"\S+ \S+ DIFF_OK exit=0 retired=[1-9]\d* dreq=\d+$", x): bad.append("B: " + x)' 'pass' $P2RUN
mut $Q q-bc-count 'if len(resc) != nbc:' 'if False:' $P2RUN
mut $Q q-bc-line  'if not re.match(r"\S+ \S+ DIFF_OK exit=0 retired=[1-9]\d* dreq=\d+$", x): bad.append("B (M+C): " + x)' 'pass' $P2RUN
mut $Q q-c-count  'if len(mine) != len(pos) * C_PROF:' 'if False:' $P2RUN
mut $Q q-c-line   'if not re.search(r": PASS k=' 'if False and re.search(r": PASS k=' $P2RUN
mut $Q q-d-caught 'elif not l[0].split(": ", 1)[1].startswith("CAUGHT first signal:"):' 'elif False:' $P2RUN
mut $Q q-d-lines  'if len(l) != 1: bad.append(f"D: {name}: {len(l)} result lines")' 'if False: pass' $P2RUN
mut $Q q-d-tval   'elif tval is not None and m.group(1) != tval:' 'elif False:' $P2RUN
mut $Q q-d-parcel 'if not m: bad.append("D: parcel fault: " + l[0].strip())' 'if False: pass' $P2RUN
mut $Q q-d-k19    'elif tval is None and m.group(1) == "0x80001000":' 'elif False:' $P2RUN
mut $Q q-d-ctl    'if not x.endswith(": exit 0, errors 0"): bad.append("D: control failed: "' 'if False: bad.append("D: control failed: "' $P2RUN
mut $Q q-f-c      'if len(cblocks) != F_BLOCKS:' 'if False:' $P2RUN
mut $Q q-g        'if "CHANGED" in x: bad.append("G: "' 'if False: bad.append("G: "' $P2RUN
mut $Q q-missing  'except OSError: bad.append("missing output: " + name); return []' 'except OSError: return []' $P2RUN
mut $Q q-exit     'sys.exit(1 if bad else 0)' 'sys.exit(0)' $P2RUN
fi
echo "GATE_MUTANTS caught $caught/$n"; [ $caught = $n ]
