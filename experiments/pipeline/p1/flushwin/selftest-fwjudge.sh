#!/bin/bash
# PIPE-P1: self-test of the flush-window judge (fwjudge.py) on mutated COPIES of a real run's bench logs (text only).
#   selftest-fwjudge.sh <run-fw out dir, e.g. runs/run-5/H> <fresh work dir>
# Case "good" must PASS. Every other case changes ONE thing (checked to have changed something) and must FAIL with
# the stated reason. Cases are SYMLINKS to the thinned base below; sed -i and rm replace or remove the link, never the
# file it points to. The run's own files are only read.
set -u
H=${1:?H dir}; OUT=${2:?work dir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
J=$(dirname "$(readlink -f "$0")")/fwjudge.py; mkdir -p $OUT; ok=0; n=0
EXP="fix=clean fixnc=clean k13=caught:fill-after-flush k14=caught:fetch-owner"
# A thinned base copy, made once: within each run only the FIRST core assertion of each name is kept (the knob-14
# logs repeat one every cycle and are ~1 GB). The judge uses per-run SETS of names, so this is lossless for it; that is
# checked right here by judging both and requiring identical verdict lines before any case runs.
BASE=$OUT/base; mkdir -p $BASE; cp $H/ref.txt $BASE/
for v in fix fixnc k13 k14; do mkdir -p $BASE/$v; for f in $H/$v/rd*-rs*.log; do
  awk '/^FW RUN /{delete seen; print; next} /^PIPE ASSERT /{if ($3 in seen) next; seen[$3]=1} {print}' $f > $BASE/$v/$(basename $f)
done; done
python3 $J $H $EXP | tail -n +2 > $OUT/judge-original.txt; python3 $J $BASE $EXP | tail -n +2 > $OUT/judge-thinned.txt
if cmp -s $OUT/judge-original.txt $OUT/judge-thinned.txt; then echo "thinned base judged identically to the original logs ($(du -sh $H | cut -f1) -> $(du -sh $BASE | cut -f1))"
else echo "SELFTEST BROKEN: the thinned logs are judged differently"; diff $OUT/judge-original.txt $OUT/judge-thinned.txt | head; exit 3; fi
fresh() { local d=$OUT/$1; mkdir -p $d; cp $BASE/ref.txt $d/; for v in fix fixnc k13 k14; do mkdir -p $d/$v; ln -s $(readlink -f $BASE/$v)/rd*-rs*.log $d/$v/; done; echo $d; }
sums() { (cd $1 && md5sum $2 2>&1); }          # the files a case mutates (a deleted file reads differently too)
case_() {  # case_ <name> <PASS|FAIL> <reason regex> <files (glob inside the copy)> <sed script | DELETE>
  local name=$1 want=$2 rx=$3 files=$4 mut=$5 d; d=$(fresh $name); n=$((n+1))
  if [ -n "$mut" ]; then
    local before; before=$(sums $d "$files")
    if [ "$mut" = DELETE ]; then (cd $d && rm $files); else (cd $d && sed -i -E "$mut" $files); fi
    [ "$before" = "$(sums $d "$files")" ] && { echo "case $name: MUTATION CHANGED NOTHING  WRONG"; rm -rf $d; return; }
  fi
  python3 $J $d $EXP > $d/judge.txt 2>&1; local rc=$?
  local got=PASS; [ $rc = 0 ] || got=FAIL
  if [ $got = $want ] && { [ -z "$rx" ] || grep -qE "$rx" $d/judge.txt; }; then ok=$((ok+1)); echo "case $name: $got  PASS"
  else echo "case $name: want $want /$rx/, got $got (rc $rc)  WRONG"; grep -E 'FAIL' $d/judge.txt | head -3 | sed 's/^/     /'; fi
  rm -rf $d                                       # the copy (mutated logs can be large)
}
case_ good               PASS ''                                         fix/rd0-rs1.log ''
case_ fix-bench-error    FAIL 'fix \(clean\): FAIL'                      fix/rd0-rs1.log '0,/^FW RUN /s/^(FW RUN .*)$/FW ERROR pt=0 rd=0 rs=1 cyc=9 fill-after-flush: injected\n\1/'
case_ fix-core-assert    FAIL 'fix \(clean\): FAIL'                      fix/rd1-rs2.log '0,/^FW RUN /s/^(FW RUN .*)$/PIPE ASSERT fetch-owner: injected\n\1/'
case_ fix-window-missing FAIL "FAIL fix: window 'final' never covered"             'fix/rd*-rs*.log' 's/ final=[0-9]+\/[0-9]+\/[0-9]+ / final=0\/0\/0 /'
case_ fix-checksum       FAIL 'differ from the reference'                fix/rd2-rs3.log '0,/^FW RUN /s/ sum=[0-9a-f]{16} / sum=00000000deadbeef /'
case_ fix-exit-code      FAIL 'non-zero exit codes'                      fix/rd0-rs5.log '0,/^FW RUN /s/ code=0 / code=3 /'
case_ fix-log-missing    FAIL 'missing .*fix/rd2-rs5.log'                fix/rd2-rs5.log DELETE
case_ fix-no-total       FAIL 'rd1-rs1: no FW TOTAL line'                fix/rd1-rs1.log '/^FW TOTAL/d'
case_ ref-differs        FAIL 'differ from the reference'                ref.txt 's/ sum=[0-9a-f]{16} / sum=0000000000000001 /'
case_ nc-window-missing  FAIL "FAIL fixnc: window 'alloc' never covered"     'fixnc/rd*-rs*.log' 's/ alloc=[0-9]+\/[0-9]+\/[0-9]+ / alloc=0\/0\/0 /'
case_ k13-not-caught     FAIL 'FAIL k13: NOT CAUGHT'                         'k13/rd*-rs*.log' '/^(FW ERROR|PIPE ASSERT)/d'
case_ k13-other-property FAIL "FAIL k13: other properties fail too: \\['payload'\\]"        'k13/rd*-rs*.log' '0,/ fill-after-flush: /s/ fill-after-flush: / payload: /'
case_ k13-no-core-assert FAIL 'FAIL k13: [0-9]+ failing runs lack fill-after-flush'             'k13/rd*-rs*.log' '/^PIPE ASSERT/d'
case_ k14-no-bench-error FAIL 'FAIL k14: [0-9]+ failing runs lack fetch-owner'                  'k14/rd*-rs*.log' '/^FW ERROR/d'
rm -rf $BASE
echo "SELFTEST_FWJUDGE $ok/$n"; [ $ok = $n ]
