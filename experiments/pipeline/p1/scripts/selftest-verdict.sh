#!/bin/bash
# PIPE-P1: self-test of the run verdict (p1verdict.py) on mutated COPIES of a real run's summaries. Cheap: text only.
#   selftest-verdict.sh <run dir, e.g. runs/run-3> <de-duplicated coverage file for it> <fresh work dir>
# Case "good" must PASS. Every other case changes ONE thing (the mutation is checked to have changed the file) and must
# FAIL with the stated reason. The run's own files are never written.
set -u
RUN=${1:?run dir}; COV=${2:?coverage}; OUT=${3:?work dir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
SC=$(dirname "$(readlink -f "$0")"); mkdir -p $OUT; ok=0; n=0
fresh() {  # a pristine copy of the summaries only
  local d=$OUT/$1; mkdir -p $d/B; cp $RUN/{A,B,C,D,E,F,G,H}.txt $d/; cp $RUN/B/results.txt $d/B/; cp $COV $d/coverage.txt; echo $d; }
case_() {  # case_ <name> <PASS|FAIL> <reason regex> <file> <mutation: sed script, or DELETE>
  local name=$1 want=$2 rx=$3 file=$4 mut=$5 d; d=$(fresh $name); n=$((n+1))
  if [ "$mut" = DELETE ]; then rm $d/$file
  elif [ -n "$mut" ]; then cp $d/$file $d/$file.orig; sed -i -E "$mut" $d/$file
    cmp -s $d/$file $d/$file.orig && { echo "case $name: MUTATION CHANGED NOTHING  WRONG"; return; }; rm $d/$file.orig; fi
  python3 $SC/p1verdict.py $d > $d/verdict.txt 2>&1; local rc=$?
  local got=PASS; [ $rc = 0 ] || got=FAIL
  if [ $got = $want ] && { [ -z "$rx" ] || grep -qE "$rx" $d/verdict.txt; }; then ok=$((ok+1)); echo "case $name: $got  PASS"
  else echo "case $name: want $want /$rx/, got $got (rc $rc)  WRONG"; grep FAIL $d/verdict.txt | head -3 | sed 's/^/     /'; fi
}
case_ good                PASS ''                                                    A.txt ''
case_ A-positive-fails    FAIL 'A: t01_alu p: FAIL'                                  A.txt '/t01_alu /s/p: PASS/p: FAIL(exit 1, want 0)/'
case_ A-errors-suffix     FAIL 'A: t03_ldst p: PASS \+2 errors'                      A.txt '/t03_ldst /s/p: PASS/p: PASS +2 errors/'
case_ A-exception-other   FAIL "A: c06_targets m: 'FAIL\(exit 4"                     A.txt '/c06_targets/s/exit 3,/exit 4,/'
case_ A-exception-passes  FAIL "A: c06_targets m: 'PASS'"                            A.txt '/c06_targets/s/m: FAIL\(exit 3, want 0\)/m: PASS/'
case_ A-missing-program   FAIL 'A: t05_roi: no result'                               A.txt '/  t05_roi /d'
case_ A-extra-program     FAIL 'A: x99: not in the test plan'                        A.txt '$a\  x99                     m: PASS                          p: PASS'
case_ A-file-missing      FAIL 'missing output: .*/A.txt'                            A.txt DELETE
case_ B-diff-fail         FAIL 'B: min hz7 DIFF_FAIL'                                B/results.txt 's/^min hz7 DIFF_OK/min hz7 DIFF_FAIL/'
case_ B-same-nonzero-exit FAIL 'B: fixed t03_ldst DIFF_OK exit=7'                    B/results.txt 's/^(fixed t03_ldst DIFF_OK) exit=0/\1 exit=7/'
case_ B-missing-result    FAIL 'B: 294 comparisons recorded'                         B/results.txt '/^rnd777 p1_csr /d'
case_ B-total-line        FAIL "B: total line"                                       B.txt 's/0 DIFF_FAIL/1 DIFF_FAIL/'
case_ C-selfcheck-fails   FAIL 'C: p1_irq_hold N=30 fixed: FAIL'                     C.txt '/p1_irq_hold N=30 fixed:/s/: PASS /: FAIL(exit 1, errors 0, interrupts 1) /'
case_ C-alignment-differs FAIL "C: p1_irq_warm N=40 min: .*BUT"                      C.txt "/p1_irq_warm N=40 min:/s/\| aligned\(N'=([0-9]+)\): DIFF_OK/| aligned(N'=\1) BUT DIFF_FAIL/"
case_ C-na-not-cancel     FAIL 'only the cancel program may take no interrupt'       C.txt '/p1_irq_basic N=20 min:/s/\| aligned.*/| n\/a (no interrupt taken on the pipeline: independent checks only)/'
case_ C-missing-case      FAIL 'C: p1_irq_fault: 23 cases'                           C.txt '/p1_irq_fault N=14 min:/d'
case_ D-knob-not-caught   FAIL 'D: knob 5 NOT caught'                                D.txt '/knob 5 on/s/CAUGHT first signal/WRONG first signal/'
case_ D-knob-missing      FAIL 'D: knob 12: no result'                               D.txt '/  knob 12 on/d'
case_ D-control-fails     FAIL 'D: control failed: control knob 10'                  D.txt '/control knob 10 /s/exit 0, errors 0/exit 1, errors 0/'
case_ E-monitor-silent    FAIL 'E: p-mon-withdraw'                                   E.txt '/p-mon-withdraw/s/-> caught: .*/NOT CAUGHT (PROTO ERROR)/'
case_ F-roi-missing       FAIL 'F: 4 blocks / 19 ROI lines'                          F.txt '0,/    ROI3 /{/    ROI3 /d}'
case_ G-source-changed    FAIL 'G: CHANGED tcpu_csr.v'                               G.txt 's/^  unchanged (tcpu_csr.v) (.*)/  CHANGED \1 tag=0 now=\2/'
case_ H-variant-fails     FAIL 'H: k14 \(caught:fetch-owner\) did not pass'      H.txt 's/^  k14 \(caught:fetch-owner\): PASS;/  k14 (caught:fetch-owner): FAIL;/'
case_ H-judge-fails       FAIL 'H: the flush-window judge did not pass'            H.txt 's/^FW_JUDGE PASS/FW_JUDGE FAIL/'
case_ H-file-missing      FAIL 'missing output: .*/H.txt'                           H.txt DELETE
case_ cov-counter-zero    FAIL 'coverage: irq_cancelled = 0'                         coverage.txt 's/irq_cancelled = [0-9]+/irq_cancelled = 0/'
case_ cov-double-count    FAIL 'coverage: header is not the de-duplicated format'    coverage.txt '1s/.*/== pipeline coverage summed over 739 runs (A, B, C)/'
echo "SELFTEST_VERDICT $ok/$n"; [ $ok = $n ]
