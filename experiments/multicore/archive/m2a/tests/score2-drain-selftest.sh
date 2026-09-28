#!/usr/bin/env bash
# The multi-hart drain rules (CONTRACT C7.1) against a REAL accepted drain log mutated one rule at a time.
# Each mutant must be rejected for its stated reason; the unmutated log must pass.
#   score2-drain-selftest.sh <good d11 run.log> <outdir>
set -u; HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); S=$HERE/score2.py; LOG=${1:?good log}; W=${2:?outdir}; mkdir -p "$W"
F="--drain --min-amo 4 --min-drained 2"
pass=0; fail=0
python3 $S $LOG $F > $W/good.out 2>&1 && { echo "ok    good: $(head -1 $W/good.out | cut -c1-80)"; pass=$((pass+1)); } || { echo "FAIL  good log rejected: $(grep -m1 FAIL $W/good.out)"; fail=$((fail+1)); }
rej() { local n=$1 why=$2; shift 2; if python3 $S "$@" $F > $W/$n.out 2>&1; then echo "FAIL  $n: ACCEPTED a mutant"; fail=$((fail+1)); elif grep -q -- "$why" $W/$n.out; then echo "ok    $n: $(grep -m1 -- "$why" $W/$n.out | cut -c3-130)"; pass=$((pass+1)); else echo "FAIL  $n: wrong reason: $(grep -m2 FAIL $W/$n.out | tr '\n' ' ' | cut -c1-200)"; fail=$((fail+1)); fi; }
mut() { local n=$1; python3 - $LOG $W/$n.log $n <<'PY'
import sys, re
src, dst, kind = sys.argv[1], sys.argv[2], sys.argv[3]
L = open(src).read().splitlines(); out = []; done = False
rel = {}; done_c = {}; assert_c = {}
for x in L:
    m = re.match(r'AT\s+(\d+)\s+(\S+)\s+hart=\s*(\d+)', x)
    if m and m.group(2) == 'HOLD_RELEASE': rel[int(m.group(3))] = int(m.group(1))
    if m and m.group(2) == 'DRAIN_DONE': done_c[int(m.group(3))] = int(m.group(1))
    if m and m.group(2) == 'HOLD_ASSERT': assert_c[int(m.group(3))] = int(m.group(1))
early = min(done_c.values()) + 1          # a release right after the FIRST hart's drain, before the other's
for x in L:
    m = re.match(r'AT\s+(\d+)\s+(\S+)(.*)', x)
    c = int(m.group(1)) if m else -1; tag = m.group(2) if m else ''
    if kind == 'early-release' and tag == 'HOLD_RELEASE' and 'hart=1' in x: x = re.sub(r'^AT\s+\d+', 'AT %10d' % early, x)
    if kind == 'no-applying-all' and tag == 'APPLYING_ALL': continue
    if kind == 'no-restart-safe' and tag == 'RESTART_SAFE': continue
    if kind == 'discard-missing' and tag == 'DRAIN_DISCARD' and 'hart=0' in x: continue
    if kind == 'answered-in-hold' and tag == 'DRAIN_DISCARD' and 'hart=0' in x:
        t = re.search(r'txid=\s*(\d+)', x).group(1); x = 'AT %10d CPU_RESP hart=0 txid=%s data=0x0 err=0 scfail=0' % (c, t)
    if kind == 'new-req-in-hold' and tag == 'A_ACC' and 'hart=  0' in x and assert_c[0] < c < rel[0] and not done:
        out.append('AT %10d CPU_REQ hart=0 txid=        99 addr=0x80000100 write=0 size=3 amo= 0 lrsc=0 data=0x0 mask=0x00 legal=1' % (assert_c[0] + 1)); done = True
    if kind == 'done-before-d' and tag == 'DRAIN_DONE' and 'hart=0' in x: x = re.sub(r'^AT\s+\d+', 'AT %10d' % (assert_c[0] + 1), x)
    out.append(x)
if kind in ('early-release', 'done-before-d', 'new-req-in-hold'):
    def key(l):
        m = re.match(r'AT\s+(\d+)', l); return int(m.group(1)) if m else 10**9
    out.sort(key=key)
open(dst, 'w').write('\n'.join(out) + '\n')
PY
}
mut early-release;     rej early-release   'before hart 0 finished draining' $W/early-release.log
mut no-applying-all;   rej no-applying-all 'no APPLYING_ALL' $W/no-applying-all.log
mut no-restart-safe;   rej no-restart-safe 'no RESTART_SAFE' $W/no-restart-safe.log
mut discard-missing;   rej discard-missing 'was not discarded by the drain\|never received its response' $W/discard-missing.log
mut answered-in-hold;  rej answered-in-hold 'delivered while the hart is held' $W/answered-in-hold.log
mut new-req-in-hold;   rej new-req-in-hold 'issued during the hold was accepted\|issued a request while held' $W/new-req-in-hold.log
mut done-before-d;     rej done-before-d   'after its DRAIN_DONE\|the drain did not wait' $W/done-before-d.log
echo "DRAIN_SELFTEST pass=$pass fail=$fail ($W)"; [ $fail = 0 ]
