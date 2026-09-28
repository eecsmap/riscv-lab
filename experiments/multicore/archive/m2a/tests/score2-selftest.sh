#!/usr/bin/env bash
# score2.py mutation self-test: a minimal two-hart log that the oracle must ACCEPT, then one mutation per rule
# that it must REJECT for the stated reason (the reason string is matched, not just the exit code). Any
# mutation the oracle accepts, or rejects for a different reason, fails this script. Run before every use.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); S=$HERE/score2.py; W=${1:-$(mktemp -d /home/engineer/fpga/.scratch/score2-selftest.XXXX)}; mkdir -p "$W"
cat > $W/base.log <<'L'
AT 1 CPU_SOURCE hart=0 lo=0 hi=1 clients=2 harts=2
AT 1 CPU_SOURCE hart=1 lo=1 hi=2 clients=2 harts=2
AT 10 CPU_REQ hart=0 txid=1 addr=0x80000100 write=1 size=3 amo=0 lrsc=0 data=0x5 mask=0xff legal=1
AT 12 A_ACC src=0 cpu=1 hart=0 op=1 param=0 addr=0x80000100 size=3 data=0x5 mask=0xff kind=0
AT 14 MGR_WRITE dram addr=0x80000100 data=0x5 mask=0xff new=0x5
AT 16 D_OUT src=0 data=0x0 err=0 kind=0
AT 18 CPU_RESP hart=0 txid=1 data=0x0 err=0 scfail=0
AT 20 CPU_REQ hart=0 txid=2 addr=0x80000100 write=0 size=3 amo=0 lrsc=1 data=0x0 mask=0xff legal=1
AT 22 A_ACC src=0 cpu=1 hart=0 op=4 param=0 addr=0x80000100 size=3 data=0x0 mask=0xff kind=1
AT 26 D_OUT src=0 data=0x5 err=0 kind=1
AT 28 CPU_RESP hart=0 txid=2 data=0x5 err=0 scfail=0
AT 30 CPU_REQ hart=1 txid=1 addr=0x80000100 write=1 size=3 amo=0 lrsc=0 data=0x7 mask=0xff legal=1
AT 32 A_ACC src=1 cpu=1 hart=1 op=1 param=0 addr=0x80000100 size=3 data=0x7 mask=0xff kind=0
AT 34 MGR_WRITE dram addr=0x80000100 data=0x7 mask=0xff new=0x7
AT 36 D_OUT src=1 data=0x0 err=0 kind=0
AT 38 CPU_RESP hart=1 txid=1 data=0x0 err=0 scfail=0
AT 40 CPU_REQ hart=0 txid=3 addr=0x80000100 write=1 size=3 amo=0 lrsc=2 data=0x9 mask=0xff legal=1
AT 42 A_ACC src=0 cpu=1 hart=0 op=1 param=0 addr=0x80000100 size=3 data=0x9 mask=0xff kind=2
AT 44 D_OUT src=0 data=0x0 err=0 kind=2 scfail=1
AT 46 CPU_RESP hart=0 txid=3 data=0x0 err=0 scfail=1
AT 50 CPU_REQ hart=1 txid=2 addr=0x80000108 write=0 size=3 amo=0 lrsc=1 data=0x0 mask=0xff legal=1
AT 52 A_ACC src=1 cpu=1 hart=1 op=4 param=0 addr=0x80000108 size=3 data=0x0 mask=0xff kind=1
AT 56 D_OUT src=1 data=0x0 err=0 kind=1
AT 58 CPU_RESP hart=1 txid=2 data=0x0 err=0 scfail=0
AT 60 CPU_REQ hart=1 txid=3 addr=0x80000108 write=1 size=3 amo=0 lrsc=2 data=0x3 mask=0xff legal=1
AT 62 A_ACC src=1 cpu=1 hart=1 op=1 param=0 addr=0x80000108 size=3 data=0x3 mask=0xff kind=2
AT 64 MGR_WRITE dram addr=0x80000108 data=0x3 mask=0xff new=0x3
AT 66 D_OUT src=1 data=0x0 err=0 kind=2
AT 68 CPU_RESP hart=1 txid=3 data=0x0 err=0 scfail=0
AT 70 CPU_REQ hart=0 txid=4 addr=0x80000100 write=1 size=3 amo=2 lrsc=0 data=0x2 mask=0xff legal=1
AT 72 A_ACC src=0 cpu=1 hart=0 op=2 param=4 addr=0x80000100 size=3 data=0x2 mask=0xff kind=3
AT 72 AMO_START hart=0
AT 74 AMO_GET addr=0x80000100
AT 76 MGR_D dram src=0 get=1 addr=0x80000100 data=0x7 err=0
AT 78 AMO_PUT addr=0x80000100 data=0x9
AT 80 MGR_WRITE dram addr=0x80000100 data=0x9 mask=0xff new=0x9
AT 82 MGR_D dram src=0 get=0 addr=0x80000100 data=0x0 err=0
AT 84 D_OUT src=0 data=0x7 err=0 kind=3
AT 86 CPU_RESP hart=0 txid=4 data=0x7 err=0 scfail=0
AT 90 EXT_A ext0 op=1 addr=0x80000200 size=3 data=0x11 mask=0xff
AT 92 A_ACC src=4 cpu=0 hart=255 op=1 param=0 addr=0x80000200 size=3 data=0x11 mask=0xff kind=0
AT 94 MGR_WRITE dram addr=0x80000200 data=0x11 mask=0xff new=0x11
AT 96 D_OUT src=4 data=0x0 err=0 kind=0
AT 100 CPU_REQ hart=0 txid=5 addr=0x80000100 write=0 size=3 amo=0 lrsc=0 data=0x0 mask=0xff legal=1
AT 102 A_ACC src=0 cpu=1 hart=0 op=4 param=0 addr=0x80000100 size=3 data=0x0 mask=0xff kind=0
AT 106 D_OUT src=0 data=0x9 err=0 kind=0
AT 108 CPU_RESP hart=0 txid=5 data=0x9 err=0 scfail=0
AT 120 FINISHED cpuResp=8 cpuResp0=5 cpuResp1=3 amo=1 scOk=1 scFail=1 kills=1 bridgeIllegal=0 tlErr=0
L
pass=0; fail=0
ok()   { local n=$1; shift; if python3 $S "$@" > $W/$n.out 2>&1; then echo "ok    $n: accepted -- $(head -1 $W/$n.out | cut -c1-90)"; pass=$((pass+1)); else echo "FAIL  $n: should accept: $(grep FAIL $W/$n.out | head -2)"; fail=$((fail+1)); fi; }
rej()  { local n=$1 why=$2; shift 2; if python3 $S "$@" > $W/$n.out 2>&1; then echo "FAIL  $n: ACCEPTED a mutant"; fail=$((fail+1)); elif grep -q -- "$why" $W/$n.out; then echo "ok    $n: rejected: $(grep -m1 -- "$why" $W/$n.out | cut -c3-120)"; pass=$((pass+1)); else echo "FAIL  $n: rejected for the wrong reason: $(grep -m2 FAIL $W/$n.out | tr '\n' ' ' | cut -c1-200)"; fail=$((fail+1)); fi; }
mut() { local n=$1; shift; sed "$@" $W/base.log > $W/$n.log; }
ok   base $W/base.log --min-kills 1 --min-scfail 1 --min-scok 1 --min-amo 1 --min-ext 1 --min-scok1 1 --min-scfail0 1
mut m01 's/^AT 26 D_OUT src=0/AT 26 D_OUT src=1/';                         rej m01 'misrouted response' $W/m01.log
mut m02 -e 's/^AT 44 D_OUT src=0 data=0x0 err=0 kind=2 scfail=1/AT 44 D_OUT src=0 data=0x0 err=0 kind=2/' -e 's/^AT 46 CPU_RESP hart=0 txid=3 data=0x0 err=0 scfail=1/AT 46 CPU_RESP hart=0 txid=3 data=0x0 err=0 scfail=0/'
                                                                            rej m02 'SC result scfail=0, model says 1' $W/m02.log
mut m03 's/kills=1/kills=0/';                                               rej m03 'kills=0, the model counted 1 cleared reservation' $W/m03.log
mut m04 's/^AT 78 AMO_PUT addr=0x80000100 data=0x9/AT 78 AMO_PUT addr=0x80000100 data=0x8/'; rej m04 'AMO wrote 0x0000000000000008, model says 0x0000000000000009' $W/m04.log
mut m05 's/^AT 28 CPU_RESP hart=0 txid=2/AT 28 CPU_RESP hart=1 txid=2/';   rej m05 'hart 1 CPU_RESP txid=2 with no request open' $W/m05.log
mut m06 '/^AT 76 MGR_D/a AT 77 A_ACC src=4 cpu=0 hart=255 op=1 param=0 addr=0x80000200 size=3 data=0x11 mask=0xff kind=0'; rej m06 "between an AMO's Get and its Put" $W/m06.log
mut m07 '/^AT 1 CPU_SOURCE hart=1/d';                                       rej m07 'no CPU_SOURCE announcement for hart 1' $W/m07.log
mut m08 's/^AT 22 A_ACC src=0 cpu=1 hart=0/AT 22 A_ACC src=0 cpu=1 hart=1/'; rej m08 'attributed source 0 to hart 1, the announced table says hart 0' $W/m08.log
mut m09 '/^AT 108 CPU_RESP/d';                                              rej m09 'hart 0 txid=5 never received its response' $W/m09.log
mut m10 '/^AT 120 FINISHED/d';                                              rej m10 'no FINISHED event' $W/m10.log
mut m11 -e '/^AT 92 A_ACC src=4/d' -e '/^AT 94 MGR_WRITE dram addr=0x80000200/d' -e '/^AT 96 D_OUT src=4/d'; rej m11 'external A beat(s) were offered but never accepted' $W/m11.log
mut m12 -e 's/^AT 32 A_ACC/AT 24 A_ACC/' -e 's/^AT 30 CPU_REQ/AT 23 CPU_REQ/' ; sort -s -k2,2n $W/m12.log -o $W/m12.log; rej m12 'serialisation broken' $W/m12.log
mut m13 '/^AT 34 MGR_WRITE/d';                                              rej m13 'memory writes differ from the model: manager 4 model 5' $W/m13.log
mut m14 '/^AT 60 CPU_REQ/i AT 59 VIOLATION tl A withdrawn hart=1';          rej m14 'VIOLATION tl A withdrawn hart=1' $W/m14.log
: > $W/m15.log;                                                             rej m15 'no FINISHED event' $W/m15.log
                                                                            rej m16 'cpu_tx 8 < required 100' $W/base.log --min-tx 100
mut m17 -e 's/^AT 106 D_OUT/AT 109 D_OUT/' -e 's/^AT 108 CPU_RESP/AT 107 CPU_RESP/'; sort -s -k2,2n $W/m17.log -o $W/m17.log; rej m17 'before its transaction completed' $W/m17.log
mut m18 -e 's/^AT 100 CPU_REQ hart=0 txid=5 addr=0x80000100 write=0 size=3 amo=0 lrsc=0 data=0x0 mask=0xff legal=1/AT 100 CPU_REQ hart=0 txid=5 addr=0x80000101 write=0 size=3 amo=0 lrsc=0 data=0x0 mask=0xff legal=0/' -e '/^AT 102 A_ACC/d' -e '/^AT 106 D_OUT/d'; rej m18 'illegal request txid=5 answered without error' $W/m18.log
mut m19 's/cpuResp0=5/cpuResp0=4/';                                         rej m19 'driver counted cpuResp0=4, the model saw 5' $W/m19.log
mut m20 's/^AT 26 D_OUT src=0 data=0x5/AT 26 D_OUT src=0 data=0x6/';       rej m20 'D data 0x0000000000000006, model says 0x0000000000000005' $W/m20.log
                                                                            rej m21 'hart 0: no hold/drain events in a drain run' $W/base.log --drain
mut m22 's/^AT 62 A_ACC src=1 cpu=1 hart=1 op=1 param=0 addr=0x80000108 size=3 data=0x3 mask=0xff kind=2/AT 62 A_ACC src=1 cpu=1 hart=1 op=1 param=0 addr=0x80000108 size=3 data=0x3 mask=0xff kind=0/'; rej m22 'hart 1 txid=3 is a sc but the backend classified kind=0' $W/m22.log
mut m23 's/^AT 72 A_ACC src=0 cpu=1 hart=0 op=2 param=4/AT 72 A_ACC src=0 cpu=1 hart=0 op=2 param=0/'; rej m23 'must map to TL param 4, the accepted A carries param 0' $W/m23.log
mut m24 '/^AT 40 CPU_REQ/i AT 39 CPU_REQ hart=0 txid=9 addr=0x80000100 write=0 size=3 amo=0 lrsc=0 data=0x0 mask=0xff legal=1'; rej m24 'CPU_REQ txid=3 while txid=9 has no response' $W/m24.log
mut m25 's/^AT 86 CPU_RESP hart=0 txid=4 data=0x7/AT 86 CPU_RESP hart=0 txid=4 data=0x9/'; rej m25 'txid=4 data 0x0000000000000009, model says 0x0000000000000007' $W/m25.log
mut m26 's/kills=1/kills=2/';                                               rej m26 'kills=2, the model counted 1 cleared reservation' $W/m26.log
                                                                            rej m27 'kill 1 != required exactly 2' $W/base.log --expect-kills 2
# a second minimal log for the core-clear (trap) path: both harts hold reservations, both trap in the same
# cycle (two VALID reservations cleared in one cycle -> kills=2 exactly), both SCs then fail
cat > $W/base2.log <<'L'
AT 1 CPU_SOURCE hart=0 lo=0 hi=1 clients=2 harts=2
AT 1 CPU_SOURCE hart=1 lo=1 hi=2 clients=2 harts=2
AT 10 CPU_REQ hart=0 txid=1 addr=0x80000100 write=0 size=3 amo=0 lrsc=1 data=0x0 mask=0xff legal=1
AT 12 A_ACC src=0 cpu=1 hart=0 op=4 param=0 addr=0x80000100 size=3 data=0x0 mask=0xff kind=1
AT 16 D_OUT src=0 data=0x0 err=0 kind=1
AT 18 CPU_RESP hart=0 txid=1 data=0x0 err=0 scfail=0
AT 20 CPU_REQ hart=1 txid=1 addr=0x80000108 write=0 size=3 amo=0 lrsc=1 data=0x0 mask=0xff legal=1
AT 22 A_ACC src=1 cpu=1 hart=1 op=4 param=0 addr=0x80000108 size=3 data=0x0 mask=0xff kind=1
AT 26 D_OUT src=1 data=0x0 err=0 kind=1
AT 28 CPU_RESP hart=1 txid=1 data=0x0 err=0 scfail=0
AT 40 CPU_TRAP hart=0
AT 40 CPU_TRAP hart=1
AT 50 CPU_REQ hart=0 txid=2 addr=0x80000100 write=1 size=3 amo=0 lrsc=2 data=0x9 mask=0xff legal=1
AT 52 A_ACC src=0 cpu=1 hart=0 op=1 param=0 addr=0x80000100 size=3 data=0x9 mask=0xff kind=2
AT 54 D_OUT src=0 data=0x0 err=0 kind=2 scfail=1
AT 56 CPU_RESP hart=0 txid=2 data=0x0 err=0 scfail=1
AT 60 CPU_REQ hart=1 txid=2 addr=0x80000108 write=1 size=3 amo=0 lrsc=2 data=0x3 mask=0xff legal=1
AT 62 A_ACC src=1 cpu=1 hart=1 op=1 param=0 addr=0x80000108 size=3 data=0x3 mask=0xff kind=2
AT 64 D_OUT src=1 data=0x0 err=0 kind=2 scfail=1
AT 66 CPU_RESP hart=1 txid=2 data=0x0 err=0 scfail=1
AT 80 FINISHED cpuResp=4 cpuResp0=2 cpuResp1=2 amo=0 scOk=0 scFail=2 kills=2 bridgeIllegal=0 tlErr=0
L
mut2() { local n=$1; shift; sed "$@" $W/base2.log > $W/$n.log; }
ok   base2-two-traps $W/base2.log --expect-kills 2 --expect-scfail 2 --expect-scok 0
mut2 m28 's/kills=2/kills=1/';                                              rej m28 'kills=1, the model counted 2 cleared reservation' $W/m28.log
mut2 m29 '/^AT 40 CPU_TRAP hart=1/d';                                       rej m29 'SC result scfail=1, model says 0 (hart 1)' $W/m29.log
                                                                            rej m30 'kill 2 != required exactly 1' $W/base2.log --expect-kills 1
echo "SELFTEST score2 pass=$pass fail=$fail ($W)"; [ $fail = 0 ]
