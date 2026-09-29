#!/bin/bash
# PIPE-P2a: self-test of the uncached-fetch judge (ncjudge.py) on mutated COPIES of a real run's logs.
#   selftest-ncjudge.sh <run-nc out dir with fix and wide> <fresh work dir>
set -u
U=${1:?run dir}; OUT=${2:?work dir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
J=$(dirname "$(readlink -f "$0")")/ncjudge.py; mkdir -p $OUT; ok=0; n=0
fresh() { local d=$OUT/$1; for v in fix wide; do mkdir -p $d/$v; cp $U/$v/rd*-rs*.log $d/$v/; done; echo $d; }
case_() {  # case_ <name> <PASS|FAIL> <reason regex> <file> <sed script | DELETE>
  local name=$1 want=$2 rx=$3 file=$4 mut=$5 d; d=$(fresh $name); n=$((n+1))
  if [ "$mut" = DELETE ]; then rm $d/$file
  elif [ -n "$mut" ]; then cp $d/$file $d/x.orig; sed -i -E "$mut" $d/$file
    cmp -s $d/$file $d/x.orig && { echo "case $name: MUTATION CHANGED NOTHING  WRONG"; return; }; rm $d/x.orig; fi
  python3 $J $d > $d/judge.txt 2>&1; local rc=$?; local got=PASS; [ $rc = 0 ] || got=FAIL
  if [ $got = $want ] && { [ -z "$rx" ] || grep -qE "$rx" $d/judge.txt; }; then ok=$((ok+1)); echo "case $name: $got  PASS"
  else echo "case $name: want $want /$rx/, got $got (rc $rc)  WRONG"; grep FAIL $d/judge.txt | head -3 | sed 's/^/     /'; fi
}
case_ good            PASS ''                                                  fix/rd0-rs1.log ''
case_ fix-exit        FAIL 'fix rd1-rs2: exit 3'                               fix/rd1-rs2.log 's/^(NC END .* code=)0 /\13 /'
case_ fix-assert      FAIL 'fix rd0-rs3: 1 core assertions'                    fix/rd0-rs3.log '0,/^NC READ/s/^(NC READ.*)$/PIPE ASSERT spec-uncached: injected\n\1/'
case_ fix-payload     FAIL 'fix rd2-rs1: 2 payload errors'                     fix/rd2-rs1.log 's/payload_errors=0$/payload_errors=2/'
case_ fix-wide-read   FAIL 'fix rd0-rs4: 1 reads wider than a parcel'          fix/rd0-rs4.log 's/non_parcel_reads=0 /non_parcel_reads=1 /'
case_ fix-violation   FAIL 'fix rd1-rs1: 3 footprint violations'               fix/rd1-rs1.log 's/footprint_violations=0 /footprint_violations=3 /'
case_ fix-extra-read  FAIL 'fix rd2-rs2: read sequence .* differs'             fix/rd2-rs2.log '0,/^NC READ/s/^(NC READ cyc=[0-9]+ addr=)40000000 /\140000002 /'
case_ fix-log-missing FAIL 'fix: missing .*rd2-rs3.log'                        fix/rd2-rs3.log DELETE
case_ wide-silent     FAIL 'wide: caught in only 11 of 12 profiles'            wide/rd1-rs3.log 's/footprint_violations=[0-9]+ /footprint_violations=0 /'
echo "SELFTEST_NCJUDGE $ok/$n"; [ $ok = $n ]
