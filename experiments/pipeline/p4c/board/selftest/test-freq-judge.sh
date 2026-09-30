#!/bin/bash
# Self-test of freq_judge.py (P4c): a good pair passes; each defect is refused for its own reason.
J=${1:-$(dirname "$0")/../freq_judge.py}; T=$(mktemp -d); bad=0
mk() { printf 'RC=0\nT0=%s\nT1=%s\nFREQ-SPIN cycles=0x%x mtime_delta=0x%s hart1_id=0x%s\nTEACHING-FREQ-SPIN-OK\n' "$2" "$3" "$4" "$5" "$6" > "$1"; }
case_() { local name=$1 want=$2 pat=$3; shift 3; local d=$T/$name; mkdir -p $d
  mk $d/freq_spin_short.1.out 10.00 11.50 40000008 "$(printf %x 400000)" 0000000000000001
  mk $d/freq_spin_long.1.out  20.00 41.50 840000008 "$(printf %x 8400000)" 0000000000000001
  if [ "$1" != true ]; then "$@" $d/freq_spin_long.1.out; fi
  out=$(python3 "$J" "$d" 2>&1); rc=$?
  if [ $rc = $want ] && grep -q -- "$pat" <<<"$out"; then echo "ok   $name rc=$rc"; else echo "FAIL $name rc=$rc (want $want, '$pat'): $out"; bad=$((bad+1)); fi; }
case_ good 0 "median 40.0000 MHz" true
case_ no-hart1 1 "hart1_id=0x0, not 1" sed -i 's/hart1_id=0x0000000000000001/hart1_id=0x0000000000000000/' 
case_ bad-ratio 1 "not 100 +- 1 %" sed -i 's/mtime_delta=0x[0-9a-f]*/mtime_delta=0xfffffffffffffffc/'
case_ old-format 1 "FAIL pair 1" sed -i 's/ hart1_id=0x[0-9a-f]*//'
echo "SELFTEST $([ $bad = 0 ] && echo PASS || echo "FAIL $bad")"; [ $bad = 0 ]
