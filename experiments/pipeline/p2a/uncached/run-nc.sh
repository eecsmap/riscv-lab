#!/bin/bash
# PIPE-P2a uncached instruction-access footprint bench: build the program and the bench variants from a pinned
# snapshot, sweep 12 port profiles (ready delay 0..2 x response delay 1..4).
#   run-nc.sh <fresh outdir> <src dir: rtl/*.v + pipeline/tcpu_core_pipe.v + inc/> <variant>...   variant = name:PIPE_FAULT
set -u
OUT=${1:?outdir}; SRC=${2:?src}; shift 2; [ $# -ge 1 ] || { echo "no variants"; exit 2; }; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
NCD=$(dirname "$(readlink -f "$0")"); T1=/home/engineer/fpga/worktrees/pipe-single/experiments/pipeline/p1/tests
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null 2>&1; set -u
mkdir -p $OUT/src $OUT/prog
cp $SRC/pipeline/tcpu_core_pipe.v $SRC/rtl/tcpu_regfile.v $SRC/rtl/tcpu_csr.v $SRC/rtl/tcpu_icache.v $SRC/rtl/tcpu_cacheable.v $SRC/rtl/tcpu_cdecode.v $SRC/inc/tcpu_defs.vh $OUT/src/
cp $NCD/nc_tb.v $NCD/nc_prog.S $NCD/nc.ld $T1/p1crt.S $T1/p1mac.h $OUT/src/
(cd $OUT/src && sha256sum *) > $OUT/src.sha256
riscv64-unknown-elf-gcc -march=rv64imc_zicsr_zifencei -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -O0 \
  -Wa,--fatal-warnings -T $OUT/src/nc.ld -I$OUT/src -o $OUT/prog/nc.elf $OUT/src/p1crt.S $OUT/src/nc_prog.S > $OUT/prog/cc.log 2>&1 || { cat $OUT/prog/cc.log; exit 3; }
riscv64-unknown-elf-objdump -d $OUT/prog/nc.elf > $OUT/prog/nc.dis; riscv64-unknown-elf-nm $OUT/prog/nc.elf > $OUT/prog/nc.sym
riscv64-unknown-elf-objcopy -O binary --remove-section=.devtext $OUT/prog/nc.elf $OUT/prog/ram.bin
riscv64-unknown-elf-objcopy -O binary --only-section=.devtext $OUT/prog/nc.elf $OUT/prog/dev.bin
python3 - $OUT/prog <<'PY'
import sys
d = sys.argv[1]
for name, size in (("ram", 65536), ("dev", 4096)):
    b = open(f"{d}/{name}.bin", "rb").read(); assert len(b) <= size, (name, len(b)); b += bytes(size - len(b))
    open(f"{d}/{name}.hex", "w").write("".join("%016x\n" % int.from_bytes(b[i:i + 8], "little") for i in range(0, size, 8)))
PY
sym() { awk -v n="$1" '$3==n{print $1}' $OUT/prog/nc.sym | sed 's/^0*//'; }
E1=$(sym dev4); E2=$(printf '%x' $((0x$(sym dev5) + 2))); E3=$(printf '%x' $((0x$(sym dev6) + 2)))
ARGS="+ram=$OUT/prog/ram.hex +dev=$OUT/prog/dev.hex +tohost=$(sym tohost) +err1=$E1 +err2=$E2 +err3=$E3"
echo "$ARGS" > $OUT/prog/args.txt; echo "device errors at $E1 (dev4, first parcel), $E2 (dev5 second parcel), $E3 (dev6 second parcel, next word)"
fail=0
for v in "$@"; do n=${v%%:*}; pf=${v#*:}; mkdir -p $OUT/$n
  if ! timeout 600 verilator --binary --timing -j 4 -O2 -Wno-fatal -Wno-WIDTH -Wno-UNUSED -Wno-DECLFILENAME -Wno-UNSIGNED \
      -Wno-MULTIDRIVEN -Wno-BLKSEQ --top-module nc_tb -GPF=$pf -I$OUT/src -Mdir $OUT/$n/obj -o nc_tb $OUT/src/nc_tb.v \
      $OUT/src/tcpu_core_pipe.v $OUT/src/tcpu_regfile.v $OUT/src/tcpu_csr.v $OUT/src/tcpu_icache.v $OUT/src/tcpu_cacheable.v \
      $OUT/src/tcpu_cdecode.v > $OUT/$n/build.log 2>&1; then echo "BUILD FAIL $n"; grep %Error $OUT/$n/build.log | head -5; fail=1; continue; fi
  cp $OUT/$n/obj/nc_tb $OUT/$n/; rm -rf $OUT/$n/obj
  for rd in 0 1 2; do for rs in 1 2 3 4; do
    timeout 120 $OUT/$n/nc_tb $ARGS +ready-delay=$rd +resp-delay=$rs > $OUT/$n/rd$rd-rs$rs.log 2>&1
    echo "$n rd=$rd rs=$rs rc=$? $(grep '^NC END' $OUT/$n/rd$rd-rs$rs.log | cut -d' ' -f3-) asserts=$(grep -c 'PIPE ASSERT' $OUT/$n/rd$rd-rs$rs.log)"
  done; done | tee $OUT/$n/sweep.txt
done
echo "RUN_NC_DONE fail=$fail"; exit $fail
