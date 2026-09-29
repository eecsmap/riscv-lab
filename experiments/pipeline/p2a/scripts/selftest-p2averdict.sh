#!/bin/bash
# PIPE-P2a: self-test of the run verdict (p2averdict.py) on mutated COPIES of a passing run's summaries (text only).
#   selftest-p2averdict.sh <passing run dir> <fresh work dir>
# Case "good" must PASS; every other case changes ONE thing (checked to have changed something) and must FAIL with
# the stated reason.
set -u
RUN=${1:?run}; OUT=${2:?work}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
V=$(dirname "$(readlink -f "$0")")/p2averdict.py; mkdir -p $OUT; ok=0; n=0
fresh() { local d=$OUT/$1; mkdir -p $d/B; cp $RUN/{A,C,D,F,G}.txt $d/; cp $RUN/B/results.txt $RUN/B/results-c.txt $d/B/; echo $d; }
case_() {  # case_ <name> <PASS|FAIL> <reason regex> <file> <sed script | DELETE>
  local name=$1 want=$2 rx=$3 file=$4 mut=$5 d; d=$(fresh $name); n=$((n+1))
  if [ "$mut" = DELETE ]; then rm $d/$file
  elif [ -n "$mut" ]; then cp $d/$file $d/$file.orig; sed -i -E "$mut" $d/$file
    cmp -s $d/$file $d/$file.orig && { echo "case $name: MUTATION CHANGED NOTHING  WRONG"; return; }; rm $d/$file.orig; fi
  python3 $V $d > $d/verdict.txt 2>&1; local rc=$?; local got=PASS; [ $rc = 0 ] || got=FAIL
  if [ $got = $want ] && { [ -z "$rx" ] || grep -qE "$rx" $d/verdict.txt; }; then ok=$((ok+1)); echo "case $name: $got  PASS"
  else echo "case $name: want $want /$rx/, got $got (rc $rc)  WRONG"; grep FAIL $d/verdict.txt | head -3 | sed 's/^/     /'; fi
}
case_ good                PASS ''                                                     A.txt ''
case_ A-m-selfcheck       FAIL 'A: min: pipeline M exit 3'                          A.txt 's/^(  min: pipeline M) exit 0/\1 exit 3/'
case_ A-c-selfcheck       FAIL 'A: C fixed: .*c02 exit 1'                           A.txt '/^  C fixed:/s/c02 exit 0 errors/c02 exit 1 errors/'
case_ A-c-reference       FAIL 'A: C rnd777: .*multicycle c01mc exit 34'            A.txt '/^  C rnd777:/s/c01mc exit 0/c01mc exit 34/'
case_ A-p1-accepts-M      FAIL 'the P1 configuration did not refuse'                   A.txt '/^  P1 configuration on m01:/s/cause=0*2 /cause=0000000000000005 /'
case_ A-noC-retired-C     FAIL 'a build without C did not refuse C code: no-C build pm-min' A.txt '/^  no-C build pm-min/s/compressed retired: 0$/compressed retired: 3/'
case_ A-noC-exit0         FAIL 'a build without C did not refuse C code: no-C build p1-min' A.txt '/^  no-C build p1-min/s/: exit [0-9]+;/: exit 0;/'
case_ B-m-diff            FAIL 'B: fixed hzm5 DIFF_FAIL'                              B/results.txt 's/^fixed hzm5 DIFF_OK/fixed hzm5 DIFF_FAIL/'
case_ B-m-missing         FAIL 'B: 219 comparisons'                                   B/results.txt '/^rnd777 p2a_md_fault /d'
case_ B-c-diff            FAIL 'B \(M\+C\): min c02 DIFF_FAIL'                         B/results-c.txt 's/^min c02 DIFF_OK/min c02 DIFF_FAIL/'
case_ B-c-missing         FAIL 'B \(M\+C\): 234 comparisons'                          B/results-c.txt '/^rnd4242 hzmc9 /d'
case_ B-c-samefail        FAIL 'B \(M\+C\): fixed p2a_c_link DIFF_OK exit=5'          B/results-c.txt 's/^(fixed p2a_c_link DIFF_OK) exit=0/\1 exit=5/'
case_ C-md-fails          FAIL 'C: p2a_md_irq N=20 min: FAIL'                         C.txt '/^  p2a_md_irq N=20 min:/s/: PASS /: FAIL(exit 1, errors 0, interrupts 1) /'
case_ C-c-not-aligned     FAIL 'C: p2a_c_irq N=30 fixed: .*not-aligned'               C.txt '/^  p2a_c_irq N=30 fixed:/s/\| aligned.*/| not-aligned/'
case_ C-c-missing         FAIL 'C: p2a_c_irq: 98 cases'                               C.txt '/^  p2a_c_irq N=40 rnd12345:/d'
case_ D-knob17-silent     FAIL 'D: NOT caught as intended: knob 17'                  D.txt '/^  knob 17 /s/CAUGHT first signal/NOT CAUGHT first signal/'
case_ D-cimm-missing      FAIL 'D: FAULT_C_IMM on m: 0 result lines'                  D.txt '/^  FAULT_C_IMM on m:/d'
case_ D-fe2-wrong-tval    FAIL 'D: parcel fault pmc-fe2: mtval 0x80000ffe, required 0x80001000' D.txt '/parcel fault pmc-fe2 /s/last_tval=0x80001000/last_tval=0x80000ffe/'
case_ D-fe1-retired       FAIL 'D: parcel fault: parcel fault m-fe1'                 D.txt '/parcel fault m-fe1 /s/COMMIT COUNT OK/COMMIT COUNT FAIL/'
case_ D-knob19-silent     FAIL 'knob 19 \(C_TVAL_FIRST\) NOT caught'                  D.txt '/parcel fault pmc-fault19 /s/last_tval=0x80000ffe/last_tval=0x80001000/'
case_ D-control-fails     FAIL 'D: control failed: control pmc-creg'                D.txt '/control pmc-creg /s/exit 0, errors 0/exit 1, errors 0/'
case_ F-c-block-missing   FAIL 'F: 3 C blocks'                                        F.txt '/^  C pmc \(min\):$/d'
case_ G-changed           FAIL 'G: CHANGED tcpu_muldiv.v'                             G.txt 's/^  unchanged (tcpu_muldiv.v) (.*)/  CHANGED \1 tag=0 now=\2/'
case_ file-missing        FAIL 'missing output: D.txt'                                D.txt DELETE
echo "SELFTEST_P2AVERDICT $ok/$n"; [ $ok = $n ]
