#!/bin/bash
# PIPE-P2a: self-test of the walker-wrapper judge (wbjudge.py) on mutated COPIES of a real run's logs (text only).
#   selftest-wbjudge.sh <run-wb out dir with variants fix w1 w2 w3 w4> <fresh work dir>
set -u
WB=${1:?run dir}; OUT=${2:?work dir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
J=$(dirname "$(readlink -f "$0")")/wbjudge.py; mkdir -p $OUT; ok=0; n=0
EXP="fix=clean w1=caught:withdraw w2=caught:done-after-kill w3=caught:spec-uncached w4=caught:killed-delivered"
fresh() { local d=$OUT/$1; mkdir -p $d; cp $WB/shared.txt $d/; for v in fix w1 w2 w3 w4; do mkdir -p $d/$v; cp $WB/$v/gm*-rd*-rs*.log $d/$v/; done; echo $d; }
case_() {  # case_ <name> <PASS|FAIL> <reason regex> <files> <sed script | DELETE>
  local name=$1 want=$2 rx=$3 files=$4 mut=$5 d; d=$(fresh $name); n=$((n+1))
  if [ -n "$mut" ]; then
    local before; before=$(cd $d && md5sum $files 2>&1)
    if [ "$mut" = DELETE ]; then (cd $d && rm $files); else (cd $d && sed -i -E "$mut" $files); fi
    [ "$before" = "$(cd $d && md5sum $files 2>&1)" ] && { echo "case $name: MUTATION CHANGED NOTHING  WRONG"; rm -rf $d; return; }
  fi
  python3 $J $d $EXP > $d/judge.txt 2>&1; local rc=$?; local got=PASS; [ $rc = 0 ] || got=FAIL
  if [ $got = $want ] && { [ -z "$rx" ] || grep -qE "$rx" $d/judge.txt; }; then ok=$((ok+1)); echo "case $name: $got  PASS"
  else echo "case $name: want $want /$rx/, got $got (rc $rc)  WRONG"; grep FAIL $d/judge.txt | head -3 | sed 's/^/     /'; fi
  rm -rf $d
}
case_ good               PASS ''                                          fix/gm0-rd0-rs1.log ''
case_ fix-error          FAIL 'FAIL fix: [0-9]+ failing runs'             fix/gm0-rd0-rs1.log '0,/^WB COVER/s/^(WB COVER.*)$/WB ERROR s=1 rd=0 rs=1 t=3 cyc=4 withdraw: injected\n\1/'
case_ class-missing      FAIL "FAIL fix: abort class 'unforwarded' never hit" 'fix/gm*-rd*-rs*.log' 's/ unforwarded=[0-9]+ / unforwarded=0 /'
case_ ref-differs        FAIL 'FAIL fix: gm1-rd2-rs4: reference walks differ' fix/gm1-rd2-rs4.log 's/s2 pa=00000080200123/s2 pa=00000080200124/'
case_ log-missing        FAIL 'FAIL fix: missing .*gm1-rd0-rs3.log'       fix/gm1-rd0-rs3.log DELETE
case_ no-total           FAIL 'FAIL fix: gm0-rd1-rs1: no WB TOTAL line'   fix/gm0-rd1-rs1.log '/^WB TOTAL/d'
case_ shared-changed     FAIL 'shared walker sources not all unchanged'   shared.txt 's/^unchanged tcpu_ptw.v/CHANGED tcpu_ptw.v/'
case_ shared-missing     FAIL 'shared walker sources not all unchanged'   shared.txt '/^unchanged tcpu_ptw.v/d'
case_ shared-extra      FAIL 'shared walker sources not all unchanged'   shared.txt '$a\CHANGED tcpu_extra.v tag=0 now=1'
case_ w1-not-caught      FAIL 'FAIL w1: NOT CAUGHT'                       'w1/gm*-rd*-rs*.log' '/^WB ERROR/d'
case_ w1-profile-silent  FAIL 'FAIL w1: gm0-rd2-rs2: no failing run'      w1/gm0-rd2-rs2.log '/^WB ERROR/d'
case_ w3-other-first     FAIL 'FAIL w3: runs whose first failure is not spec-uncached' w3/gm0-rd0-rs1.log '0,/ spec-uncached: /s/ spec-uncached: / payload: /'
echo "SELFTEST_WBJUDGE $ok/$n"; [ $ok = $n ]
