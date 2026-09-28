#!/usr/bin/env bash
# m3_check.py against mutated copies of a real passing dual run: each mutation removes one piece of evidence
# and the judge must reject it for that reason.   m3-check-selftest.sh <passing outdir> <workdir>
set -u; T=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); SRC=${1:?outdir}; W=${2:?workdir}; mkdir -p $W; pass=0; fail=0
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
mk() { rm -rf $W/$1; mkdir -p $W/$1; cp -r $SRC/run $W/$1/run; cp $SRC/runner.log $W/$1/; }
ok()  { local n=$1; if python3 $T/m3_check.py $W/$n > $W/$n.out 2>&1; then echo "ok    $n: accepted"; pass=$((pass+1)); else echo "FAIL  $n: should accept: $(grep -m2 '  FAIL' $W/$n.out | tr '\n' ' ' | cut -c1-200)"; fail=$((fail+1)); fi; }
rej() { local n=$1 why=$2; if python3 $T/m3_check.py $W/$n > $W/$n.out 2>&1; then echo "FAIL  $n: ACCEPTED a mutant"; fail=$((fail+1)); elif grep -q -- "$why" $W/$n.out; then echo "ok    $n: rejected: $(grep -m1 -- "$why" $W/$n.out | cut -c3-140)"; pass=$((pass+1)); else echo "FAIL  $n: wrong reason: $(grep -m2 '  FAIL' $W/$n.out | tr '\n' ' ' | cut -c1-200)"; fail=$((fail+1)); fi; }
C=run/console.txt
mk base;                                                                                   ok  base
mk m01; sed -i -E 's/(HARTS_USER user0=[0-9]+ range0=[0-9]+ user1=)[0-9]+/\10/' $W/m01/$C;  rej m01 'hart 1 never committed a user-mode instruction'
mk m02; sed -i -E 's/(HARTS_USER user0=[0-9]+ range0=[0-9]+ user1=[0-9]+ range1=)[0-9]+/\10/' $W/m02/$C; rej m02 'hart 1 never committed inside the scheduler'
mk m03; sed -i -E 's/(HARTS_USER user0=[0-9]+ range0=[0-9]+ user1=)[0-9]+/\1500/' $W/m03/$C; rej m03 'user-mode instructions < 100000'
mk m04; sed -i -E 's/ u1=[0-9]+/ u1=777/' $W/m04/run/run.log;                              rej m04 'did not grow across PROGRESS samples'
mk m05; sed -i '/M3-PAR-CHILD1 /d' $W/m05/$C;                                              rej m05 'child reports 1/0'
mk m06; python3 - $W/m06/$C <<'PY'
import sys,re; p=sys.argv[1]; s=open(p).read()
# the parent's DONE line moved AFTER the next prompt: a prompt appeared while a child task was still open
i=s.find('M3-PAR-DONE children=2 ok=1\n'); line='M3-PAR-DONE children=2 ok=1\n'; s=s.replace(line,'',1); j=s.find('$ ', i); s=s[:j]+'$ m3migrate\n'+line+s[j+len('$ m3migrate\n'):] if s[j:].startswith('$ m3migrate') else s
open(p,'w').write(s)
PY
                                                                                            rej m06 'reported before both children\|no prompt segment whose echoed line\|carries no matching output'
mk m07; sed -i -E 's/M3-MIGRATE-DONE harts=0x3/M3-MIGRATE-DONE harts=0x1/' $W/m07/$C;      rej m07 'ran on harts 0x1 only'
mk m14; sed -i -E 's/pinned_ok=1/pinned_ok=0/' $W/m14/$C;                                  rej m14 'controlled migration .* was not observed'
mk m08; sed -i '0,/B0-COMPUTE-CHECKSUM/{s/\(B0-COMPUTE-CHECKSUM[^\n]*\)/\1\n\1/}' $W/m08/$C; rej m08 'printed 2 times'
mk m09; sed -i 's/^\$ forktest$/$ forktest\n$ forktest/' $W/m09/$C;                        rej m09 'typed 1x but echoed 2x'
mk m10; printf 'panic: test\n' >> $W/m10/$C;                                               rej m10 'kernel panic'
mk m11; sed -i -E 's/M3-PAR-CHILD0 checksum=[0-9a-f]+/M3-PAR-CHILD0 checksum=0000000000000000/' $W/m11/$C; rej m11 'checksums .* wrong\|carries no matching output'
mk m12; sed -i '/HARTS_USER/d' $W/m12/$C;                                                  rej m12 'no HARTS_USER line'
mk m13; sed -i -E 's/^ok\tfor/TIMEOUT\tfor/' $W/m13/run/stages.txt 2>/dev/null; sed -i -E '0,/^ok\t/s/^ok\t/TIMEOUT\t/' $W/m13/run/stages.txt; rej m13 'stage(s) not ok'
# M4 review: the disk trace must exist and be closed
mk m15; python3 - $W/m15/run/run.log $W/m15/$C <<'PY'
import sys, re
for p in sys.argv[1:]:
    s = open(p).read(); i = s.rfind('BDEV_DONE')
    if i >= 0: j = s.rfind('\n', 0, i); k = s.find('\n', i); s = s[:j+1] + s[k+1:]; open(p, 'w').write(s)
PY
                                                                                            rej m15 'ends with a request still open\|requests but .* completions'
mk m16; sed -i -E '/RBOOT +[0-9]+ +(BDEV_OP|BDEV_DONE)/d' $W/m16/run/run.log $W/m16/$C;   rej m16 'no BDEV_OP/BDEV_DONE events at all'
echo "M3_CHECK_SELFTEST pass=$pass fail=$fail ($W)"; [ $fail = 0 ]
