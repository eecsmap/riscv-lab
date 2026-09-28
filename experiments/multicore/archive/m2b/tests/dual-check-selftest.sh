#!/usr/bin/env bash
# dual_check.py against MUTATED copies of real passing run directories: each mutation removes or corrupts one
# piece of evidence and the judge must reject it for that reason. (The injected-defect PROGRAMS are the other
# half, in m2b-suite.sh neg.)   dual-check-selftest.sh <passing runs root (smoke3-style)> <workdir>
set -u; T=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); SRC=${1:?runs root}; W=${2:?workdir}; P=/home/engineer/fpga/experiments/multicore/m2b/progs/build
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
mkdir -p $W; pass=0; fail=0
mk() { local n=$1 src=$2; rm -rf $W/$n; cp -r $SRC/$src $W/$n; }
ok()  { local n=$1; shift; if python3 $T/dual_check.py $W/$n "$@" > $W/$n.out 2>&1; then echo "ok    $n: accepted"; pass=$((pass+1)); else echo "FAIL  $n: should accept: $(grep -m2 '  FAIL' $W/$n.out | tr '\n' ' ')"; fail=$((fail+1)); fi; }
rej() { local n=$1 why=$2; shift 2; if python3 $T/dual_check.py $W/$n "$@" > $W/$n.out 2>&1; then echo "FAIL  $n: ACCEPTED a mutant"; fail=$((fail+1)); elif grep -q -- "$why" $W/$n.out; then echo "ok    $n: rejected: $(grep -m1 -- "$why" $W/$n.out | cut -c3-120)"; pass=$((pass+1)); else echo "FAIL  $n: wrong reason: $(grep -m2 '  FAIL' $W/$n.out | tr '\n' ' ' | cut -c1-200)"; fail=$((fail+1)); fi; }
E1="--prog dual01_boot --elf $P/dual01_boot.elf"
mk base dual01_boot;                                                          ok  base $E1
mk m01 dual01_boot; sed -i '/COMMIT hart=1/d' $W/m01/events.txt;             rej m01 'hart 1 never committed the entry' $E1
mk m02 dual01_boot; sed -i 's/HARTS n=2/HARTS n=1/' $W/m02/console.txt;        rej m02 'HARTS n=1' $E1
mk m03 dual01_boot; sed -i -E 's/(HARTS n=2 retired0=[0-9]+ traps0=[0-9]+ cause0=0x[0-9a-f]+ maxawait0=[0-9]+ awaits0=[0-9]+ epoch0=[0-9]+ retired1=)[0-9]+/\10/' $W/m03/console.txt; rej m03 'hart 1 retired 0' $E1
mk m04 dual01_boot; sed -i 's/M2B-BOOT-OK/M2B-BOOT-XX/' $W/m04/console-clean.txt; rej m04 'expected marker M2B-BOOT-OK absent' $E1
mk m05 dual01_boot; sed -i '/Completed after/d' $W/m05/console.txt;             rej m05 'no "Completed after"' $E1
mk m06 dual01_boot; echo 2 > $W/m06/exit;                                       rej m06 'simulator exit 2' $E1
mk m07 dual01_boot; sed -i '/HOSTDONE/d' $W/m07/console.txt $W/m07/events.txt;  rej m07 'no HOSTDONE' $E1
mk m08 dual01_boot; sed -i '/REQ hart=0 .*addr=0x02000004 write=1/d' $W/m08/events.txt; rej m08 'never wrote msip\[1\]=1' $E1
mk m09 dual01_boot; sed -i -E '0,/COMMIT hart=1 pc=0x0000000080000000/s/^EV +([0-9]+) +COMMIT hart=1 pc=0x0000000080000000/EV 100 COMMIT hart=1 pc=0x0000000080000000/' $W/m09/events.txt; rej m09 'before hart 0 cleared msip\[0\]' $E1
mk m10 dual01_boot; sed -i -E 's/(M2B-BOOT-OK sp1=0x)[0-9a-f]+/\10000000080000010/' $W/m10/console-clean.txt; rej m10 'is not inside its stack' $E1
mk m11 dual01_boot; sed -i 's/HARTS n=2 retired0=\([0-9]*\)/HARTS n=2 retired0=1/' $W/m11/console.txt; rej m11 'COMMIT events in the trace, HARTS says 1' $E1
E2="--prog dual02_clint --elf $P/dual02_clint.elf"
mk base2 dual02_clint;                                                         ok  base2 $E2
mk m12 dual02_clint; sed -i '/TRAP hart=1 interrupt=1 cause=0x8000000000000003/d' $W/m12/events.txt; rej m12 'hart 1 took 0 software-interrupt traps' $E2
mk m13 dual02_clint; sed -i -E 's/(M2B-CLINT-OK mtip0=0x)[0-9a-f]+/\10000000000000002/' $W/m13/console-clean.txt; rej m13 'timer traps per hart 2' $E2
E5="--prog dual05_fencei --elf $P/dual05_fencei.elf"
mk base5 dual05_fencei;                                                        ok  base5 $E5
mk m14 dual05_fencei; sed -i '/COMMIT hart=1 .*insn=0x00200513/d' $W/m14/events.txt; rej m14 'never committed the NEW instruction' $E5
mk m15 dual05_fencei; sed -i -E 's/ fence=0x[0-9a-f]+/ fence=0x0000000000000001/' $W/m15/console-clean.txt; rej m15 'expected 2 (the new code)' $E5
mk m16 dual05_fencei; sed -i '/COMMIT hart=1 .*insn=0x0000100f/d' $W/m16/events.txt; rej m16 'never committed fence.i' $E5
echo "DUAL_CHECK_SELFTEST pass=$pass fail=$fail ($W)"; [ $fail = 0 ]
