#!/bin/bash
# Gate self-test for p1diff.py --require-complete. Works on COPIES of a real passing pair from a finished run.
#   selftest-p1diff.sh <run dir> <work dir>
set -u; RUN=${1:?run}; W=${2:?work}; D=$(dirname "$(readlink -f "$0")")/p1diff.py
[ -e "$W" ] && { echo "REFUSE: $W exists"; exit 2; }; mkdir -p $W
base=t01_alu-min; pass=0; total=0
mk() { local n=$1; for s in m p; do for e in log commits mem exit; do cp $RUN/B/$base-$s.$e $W/$n-$s.$e; done; done; }
t() {  # t <name> <want PASS|FAIL> <mode> <reason-substring>
  local n=$1 want=$2 mode=$3 why=$4; total=$((total+1))
  out=$(python3 $D $mode $W/$n-m $W/$n-p); rc=$?
  got=FAIL; [ $rc = 0 ] && got=PASS
  if [ $got = $want ] && { [ -z "$why" ] || grep -qF -- "$why" <<<"$out"; }; then pass=$((pass+1)); echo "ok   $n ($want): $(cut -c1-150 <<<"$out")"
  else echo "FAIL $n: wanted $want${why:+ with '$why'}, got: $(cut -c1-200 <<<"$out")"; fi; }
mk good;    t good PASS --require-complete ""
# two identical timeouts: same stream, exit 2, no completion line
mk tmo; for s in m p; do echo 2 > $W/tmo-$s.exit; sed -i '/^TOHOST code=0/d' $W/tmo-$s.log; echo "TIMEOUT after 3000000 cycles" >> $W/tmo-$s.log; done
t tmo FAIL --require-complete "exit 2, a completing program must exit 0"
t tmo PASS "" ""                                   # without the gate the old judge called this a match
# both retirement streams empty (header only)
mk empty; for s in m p; do grep '^#' $W/empty-$s.commits > $W/x && mv $W/x $W/empty-$s.commits; done
t empty FAIL --require-complete "empty retirement stream"
# exit 0 on both but the completion line missing (the run stopped before the tohost store retired)
mk nodone; for s in m p; do sed -i '/^TOHOST code=0/d' $W/nodone-$s.log; done
t nodone FAIL --require-complete "no completion line"
# identical non-zero self-check failure on both
mk samefail; for s in m p; do echo 7 > $W/samefail-$s.exit; sed -i 's/^TOHOST code=0 /TOHOST code=7 /' $W/samefail-$s.log; done
t samefail FAIL --require-complete "exit 7"
# a real difference is still a difference
mk diff; awk 'NR==5 && $3 != "-" {$4 = "0x000000000000dead"} {print}' $W/diff-p.commits > $W/x && mv $W/x $W/diff-p.commits
cmp -s $W/diff-m.commits $W/diff-p.commits && { echo "SELFTEST BROKEN: the diff mutation changed nothing"; exit 3; }
t diff FAIL --require-complete "retirement stream differs"
echo "SELFTEST_P1DIFF $pass/$total"; [ $pass = $total ]
