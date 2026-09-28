#!/usr/bin/env bash
# The new d13-d17 scenarios against the OLD backend (AtomicBackend.scala as committed in d9c4008, everything
# else current): the eight two-reservation cases must FAIL with the exact undercount message and the two d17
# cases (one reservation) must pass -- that is the reproduction of the review's finding, before the fix.
#   kill-repro-old.sh <outdir>
set -u; HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); M2=$(dirname "$HERE"); OUT=${1:?outdir}
W=/home/engineer/fpga/worktrees/mc-dual-backend; OLD=$M2/gen/common-old
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
rm -rf $OLD; mkdir -p $OLD; (cd $M2/gen/common-dual && tar --exclude=./build -cf - .) | (cd $OLD && tar -xf -); mkdir -p $OLD/build
git -C $W show d9c4008:soc/scala/teaching/AtomicBackend.scala > $OLD/src/main/scala/teaching/AtomicBackend.scala
mkdir -p $OUT; { echo "AtomicBackend.scala from d9c4008: $(sha256sum $OLD/src/main/scala/teaching/AtomicBackend.scala | cut -c1-16)"; echo "current (fixed):            $(sha256sum $W/soc/scala/teaching/AtomicBackend.scala | cut -c1-16)"; git -C $W diff d9c4008 -- soc/scala/teaching/AtomicBackend.scala | grep -E "^[-+]" | grep -vE "^(\+\+\+|---)" | grep -E "nKill|killIntent" ; } > $OUT/old-vs-new.txt
GC=$OLD bash $HERE/dual-all.sh $OUT/kill kill > $OUT/kill.log 2>&1
rc=0; expect_fail="d13-ext-kills-both d14-partial-kills-both d15-clear-both d16-twobeat-both d13-ext-kills-both-swap d14-partial-kills-both-swap d15-clear-both-swap d16-twobeat-both-swap"
for n in $expect_fail; do
  if grep -q "the backend counted kills=1, the model counted 2 cleared reservation" $OUT/kill/$n/score.txt 2>/dev/null; then echo "  $n: OLD BACKEND UNDERCOUNTS (reproduced): $(grep -m1 'counted kills' $OUT/kill/$n/score.txt | cut -c3-110)"
  else echo "  $n: NOT reproduced: $(cat $OUT/kill/$n/verdict.txt 2>/dev/null | cut -c1-120)"; rc=1; fi; done
for n in d17-same-hart-two-reasons d17-same-hart-two-reasons-swap; do
  if grep -q "score=0" $OUT/kill/$n/verdict.txt 2>/dev/null; then echo "  $n: old backend correct on one reservation (count 1), as expected"
  else echo "  $n: unexpected on the old backend: $(cat $OUT/kill/$n/verdict.txt | cut -c1-120)"; rc=1; fi; done
echo "KILL_REPRO_OLD rc=$rc (0 = the undercount is reproduced on all eight two-reservation cases)"; exit $rc
