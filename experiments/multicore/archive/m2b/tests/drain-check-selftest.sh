#!/usr/bin/env bash
# The drain rules of dual_check.py against MUTATED copies of the real passing dual06 run: each mutation removes
# or corrupts one piece of drain/memory evidence and the judge must reject it for that reason.
#   drain-check-selftest.sh <passing dual06 run dir> <workdir>
set -u; T=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); SRC=${1:?run dir}; W=${2:?workdir}
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
mkdir -p $W; pass=0; fail=0; F="--prog dual06_drain --drain"
mk() { rm -rf $W/$1; cp -r $SRC $W/$1; }
ok()  { local n=$1; if python3 $T/dual_check.py $W/$n $F > $W/$n.out 2>&1; then echo "ok    $n: accepted"; pass=$((pass+1)); else echo "FAIL  $n: should accept: $(grep -m2 '  FAIL' $W/$n.out | tr '\n' ' ')"; fail=$((fail+1)); fi; }
rej() { local n=$1 why=$2; if python3 $T/dual_check.py $W/$n $F > $W/$n.out 2>&1; then echo "FAIL  $n: ACCEPTED a mutant"; fail=$((fail+1)); elif grep -q -- "$why" $W/$n.out; then echo "ok    $n: rejected: $(grep -m1 -- "$why" $W/$n.out | cut -c3-140)"; pass=$((pass+1)); else echo "FAIL  $n: wrong reason: $(grep -m2 '  FAIL' $W/$n.out | tr '\n' ' ' | cut -c1-220)"; fail=$((fail+1)); fi; }
# python helper for the structured mutations (cycle-aware)
mut() { local n=$1 kind=$2; python3 - $W/$n/events.txt $kind <<'PY'
import re, sys
p, kind = sys.argv[1], sys.argv[2]
L = open(p).read().split('\n')
def cyc(l):
    m = re.match(r'\S+\s+(\d+)', l); return int(m.group(1)) if m else -1
inj = next(cyc(l) for l in L if ' INJECT ' in l)
def find(pat, after=inj): return next(i for i, l in enumerate(L) if re.search(pat, l) and cyc(l) >= after)
def setcyc(i, c): L[i] = re.sub(r'^(\S+)\s+\d+', lambda m: f'{m.group(1)} {c}', L[i])
if kind == 'no-apply': del L[find(r' RESET_APPLY ')]
elif kind == 'no-safe': del L[find(r' CPU_RESTART_SAFE ')]
elif kind == 'early-apply':
    dd0 = cyc(L[find(r' DRAIN_DONE hart=0')]); setcyc(find(r' RESET_APPLY '), dd0 - 3)
elif kind == 'early-release':
    ra = cyc(L[find(r' RESET_APPLY ')]); setcyc(find(r' HOLD_RELEASE hart=1'), ra - 1)
elif kind == 'early-drain-done':
    # hart 0's write was still OFFERED (pendingA) at the hold: its AXI completion comes several cycles later;
    # a DRAIN_DONE one cycle after the hold claims the drain finished before that write reached memory
    setcyc(find(r' DRAIN_DONE hart=0'), cyc(L[find(r' HOLD_ASSERT hart=0')]) + 1)
elif kind in ('lost-write', 'wrong-data', 'wrong-addr'):
    # the 12th CPU scratch write of hart 0 (region 0x80020000..): its AW, the following W and the matching B
    aws = [i for i, l in enumerate(L) if ' AW ' in l and re.search(r'addr=0x8002[0-3]', l)]
    i = aws[11]; aw_id = re.search(r'id=\s*(\d+)', L[i]).group(1)
    j = next(k for k in range(i + 1, len(L)) if ' W ' in L[k] and 'last=1' in L[k])
    b = next(k for k in range(i + 1, len(L)) if re.search(r' B id=\s*' + aw_id + r'\b', L[k]))
    if kind == 'lost-write':
        for k in sorted([i, j, b], reverse=True): del L[k]
    elif kind == 'wrong-data': L[j] = re.sub(r'data=0x[0-9a-f]+', 'data=0xdeadbeefdeadbeef', L[j])
    else: L[i] = re.sub(r'addr=0x[0-9a-f]+', 'addr=0x8002f000', L[i])
elif kind == 'lost-inflight':
    # hart 1's in-flight write at the hold: the last hart-1 REQ before HOLD_ASSERT; drop its AXI triple
    ha = cyc(L[find(r' HOLD_ASSERT hart=1')])
    req = [l for l in L if ' REQ hart=1 ' in l and 'write=1' in l and cyc(l) <= ha][-1]
    addr = int(re.search(r'addr=0x([0-9a-f]+)', req).group(1), 16) & ~7
    i = next(k for k, l in enumerate(L) if ' AW ' in l and cyc(l) > cyc(req) and int(re.search(r'addr=0x([0-9a-f]+)', l).group(1), 16) == addr)
    aw_id = re.search(r'id=\s*(\d+)', L[i]).group(1)
    j = next(k for k in range(i + 1, len(L)) if ' W ' in L[k] and 'last=1' in L[k]); b = next(k for k in range(i + 1, len(L)) if re.search(r' B id=\s*' + aw_id + r'\b', L[k]))
    for k in sorted([i, j, b], reverse=True): del L[k]
elif kind == 'stale-resp':
    # a response after the release that carries a pre-hold request's (epoch, seq)
    ha = cyc(L[find(r' HOLD_ASSERT hart=0')]); hr = find(r' HOLD_RELEASE hart=0')
    req = [l for l in L if ' REQ hart=0 ' in l and cyc(l) < ha][-3]
    seq = re.search(r'seq=\s*(\d+)', req).group(1); ep = re.search(r'epoch=\s*(\d+)', req).group(1)
    L.insert(hr + 1, f'EV {cyc(L[hr]) + 2} RESP hart=0 seq={seq} rdata=0x0 error=0 epoch={ep}')
elif kind == 'duplicate-write':
    aws = [i for i, l in enumerate(L) if ' AW ' in l and re.search(r'addr=0x8002[0-3]', l)]
    i = aws[20]; j = next(k for k in range(i + 1, len(L)) if ' W ' in L[k] and 'last=1' in L[k]); b = next(k for k in range(i + 1, len(L)) if ' B ' in L[k])
    L[b:b] = [L[i], L[j], L[b]]
open(p, 'w').write('\n'.join(L))
PY
}
mk base;                                        ok  base
mk m01; mut m01 no-apply;                       rej m01 '0 RESET_APPLY events after the injection'
mk m02; mut m02 no-safe;                        rej m02 '0 CPU_RESTART_SAFE events after the injection'
mk m03; mut m03 early-apply;                    rej m03 'RESET_APPLY at .* before hart 0 finished draining'
mk m04; mut m04 early-release;                  rej m04 'hart 1 released at .* not after the aligned apply'
mk m05; mut m05 early-drain-done;               rej m05 'before hart 0 DRAIN_DONE at .* (in flight at the hold)\|DRAIN_DONE at .* before the in-flight write completed'
mk m06; mut m06 lost-write;                     rej m06 'never reached AXI with that address/lanes/data'
mk m07; mut m07 wrong-data;                     rej m07 'never reached AXI with that address/lanes/data'
mk m08; mut m08 wrong-addr;                     rej m08 'never reached AXI with that address/lanes/data'
mk m09; mut m09 lost-inflight;                  rej m09 'write (1, 1, [0-9]*) .*never reached AXI .* (in flight at the hold)\|in-flight write .* never reached memory'
mk m10; mut m10 stale-resp;                     rej m10 'stale response delivered\|answered twice'
mk m11; mut m11 duplicate-write;                rej m11 'match no CPU request'
mk m12; sed -i -E 's/(survived=0x)[0-9a-f]+/\10000000000000010/' $W/m12/console-clean.txt; rej m12 'read back 16 surviving pattern words'
mk m13; sed -i -E 's/(M2B-DRAIN-OK epoch=0x)[0-9a-f]+/\10000000000000000/' $W/m13/console-clean.txt; rej m13 'reporting run is epoch 0'
mk m14; sed -i '/HOLD_ASSERT hart=1/d' $W/m14/events.txt; rej m14 'hart 1 has 0 HOLD_ASSERT'
mk m15; sed -i -E 's/(HARTS .*epoch0=)2/\11/' $W/m15/console.txt; rej m15 'final epochs \[1, 2\]'
echo "DRAIN_CHECK_SELFTEST pass=$pass fail=$fail ($W)"; [ $fail = 0 ]
