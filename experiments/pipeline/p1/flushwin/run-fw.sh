#!/bin/bash
# PIPE-P1 flush-window bench (codex-pipe-p1-flush-boundary): build the program and one bench per variant from a pinned
# source snapshot, then sweep every variant.
#   run-fw.sh <fresh outdir> <src dir> <variant>...          variant = name:PIPE_FAULT:ICACHE_BYTES
# <src dir> has the build-sims.sh layout (rtl/*.v, pipeline/tcpu_core_pipe.v, inc/tcpu_defs.vh) and optionally fw/
# (the bench sources; otherwise they are taken from this directory). REF_SIM=<multicycle harness binary> adds a
# reference run of the same program on the multicycle core (<out>/ref.txt).
# Per variant: 15 timing profiles (ready delay 0..2 x response delay 1..5), 4 in parallel; per profile the interrupt
# line is raised at every cycle from 1 to the length of the interrupt-free run. Output <out>/<variant>/rd<R>-rs<S>.log.
set -u
OUT=${1:?outdir}; SRC=${2:?src dir}; shift 2; [ $# -ge 1 ] || { echo "no variants"; exit 2; }
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
FWD=$(dirname "$(readlink -f "$0")"); PREP=/home/engineer/fpga/experiments/teaching-cpu/m2-prep/tests
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
mkdir -p $OUT/src/rtl $OUT/src/inc $OUT/src/fw $OUT/prog
cp $SRC/pipeline/tcpu_core_pipe.v $SRC/rtl/tcpu_regfile.v $SRC/rtl/tcpu_csr.v $SRC/rtl/tcpu_icache.v $SRC/rtl/tcpu_cacheable.v $OUT/src/rtl/
cp $SRC/inc/tcpu_defs.vh $OUT/src/inc/
if [ -d $SRC/fw ]; then cp $SRC/fw/fw_tb.v $SRC/fw/fw_prog.S $SRC/fw/mkhex.py $OUT/src/fw/
else cp $FWD/fw_tb.v $FWD/fw_prog.S $FWD/mkhex.py $OUT/src/fw/; fi
(cd $OUT/src && find . -type f | sort | xargs sha256sum) > $OUT/src.sha256
{ echo "sources from: $SRC"; echo "verilator: $(verilator --version)"; echo "date: $(date -u +%FT%TZ)"; } > $OUT/tools.txt
# ---- program
riscv64-unknown-elf-gcc -march=rv64i_zicsr_zifencei -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -O0 \
  -Wa,--fatal-warnings -T $PREP/link.ld -o $OUT/prog/fw.elf $OUT/src/fw/fw_prog.S > $OUT/prog/cc.log 2>&1 || { cat $OUT/prog/cc.log; exit 3; }
riscv64-unknown-elf-objcopy -O binary $OUT/prog/fw.elf $OUT/prog/fw.bin
python3 $OUT/src/fw/mkhex.py $OUT/prog/fw.bin $OUT/prog/fw.hex
riscv64-unknown-elf-nm $OUT/prog/fw.elf > $OUT/prog/fw.sym; riscv64-unknown-elf-objdump -d $OUT/prog/fw.elf > $OUT/prog/fw.dis
sym() { awk -v n="$1" '$3==n{print $1}' $OUT/prog/fw.sym | sed 's/^0*//'; }
ARGS="+hex=$OUT/prog/fw.hex +tohost=$(sym tohost) +result=$(sym fw_result) +irqn=$(sym irq_n) +errline=$(sym fw_errline)"
echo "$ARGS" > $OUT/prog/args.txt
# ---- reference: the same program, no interrupt, on the multicycle core in the accepted harness
if [ -n "${REF_SIM:-}" ]; then
  timeout 120 $REF_SIM +elf=$OUT/prog/fw.elf +max-cycles=3000000 +mem-dump=80000000:8192:$OUT/ref.mem > $OUT/ref.log 2>&1; rc=$?
  r=$(awk -v a="0x$(printf '%016x' 0x$(sym fw_result))" '$1==a{print $2}' $OUT/ref.mem)
  echo "REF exit=$rc sum=${r#0x} $(grep -m1 '^TOHOST code=' $OUT/ref.log)" | tee $OUT/ref.txt
fi
# ---- benches, then the sweeps
fail=0
for v in "$@"; do
  IFS=: read name pf icb <<< "$v"
  mkdir -p $OUT/$name
  if ! timeout 900 verilator --binary --timing -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED \
       -Wno-MULTIDRIVEN -Wno-BLKSEQ --top-module fw_tb -GPF=$pf -GICB=$icb -I$OUT/src/inc -Mdir $OUT/$name/obj -o fw_tb \
       $OUT/src/fw/fw_tb.v $OUT/src/rtl/tcpu_core_pipe.v $OUT/src/rtl/tcpu_regfile.v $OUT/src/rtl/tcpu_csr.v \
       $OUT/src/rtl/tcpu_icache.v $OUT/src/rtl/tcpu_cacheable.v > $OUT/$name/build.log 2>&1; then
    echo "BUILD FAIL $name"; grep %Error $OUT/$name/build.log | head -5; fail=1; continue
  fi
  cp $OUT/$name/obj/fw_tb $OUT/$name/fw_tb; rm -rf $OUT/$name/obj
  echo "$name $pf $icb $(sha256sum $OUT/$name/fw_tb | cut -c1-16)" >> $OUT/variants.txt
done
for v in "$@"; do n=${v%%:*}; [ -x $OUT/$n/fw_tb ] || continue
  for rd in 0 1 2; do for rs in 1 2 3 4 5; do echo "$n $rd $rs"; done; done; done |
  xargs -P 4 -L 1 bash -c 'timeout 900 '"$OUT"'/$0/fw_tb '"$ARGS"' +ready-delay=$1 +resp-delay=$2 > '"$OUT"'/$0/rd$1-rs$2.log 2>&1; echo "$0 rd=$1 rs=$2 rc=$? $(grep -E "^FW TOTAL" '"$OUT"'/$0/rd$1-rs$2.log)"' |
  sort > $OUT/sweep.txt
cat $OUT/sweep.txt
echo "RUN_FW_DONE fail=$fail"
exit $fail
