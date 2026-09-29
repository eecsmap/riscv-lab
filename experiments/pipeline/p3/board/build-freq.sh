#!/usr/bin/env bash
# PIPE-P3b: build the two frequency-reference programs (named objects, as the accepted probe build, so the hash is
# reproducible).   build-freq.sh <fresh outdir>
set -u
cd /home/engineer/fpga
WS=/home/engineer/fpga/teaching-cpu-work; SRC=$(cd "$(dirname "$0")" && pwd)/src
OUT=${1:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p "$OUT"
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
CC=riscv64-unknown-elf-gcc; LD=experiments/teaching-cpu/m2-prep/tests/link.ld
BASE="-mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -march=rv64i_zicsr -I$WS/cpu/m3tests"
for v in "freq_spin_short 40000000" "freq_spin_long 840000000"; do set -- $v
  $CC $BASE -DSPIN_CYCLES=$2 -c -o $OUT/$1.o $SRC/freq_spin.S && $CC $BASE -c -o $OUT/$1.htif.o $WS/cpu/m3tests/htif.S \
    && $CC $BASE -T $LD -o $OUT/$1.elf $OUT/$1.o $OUT/$1.htif.o 2> $OUT/$1.buildlog || { echo "BUILD FAIL $1"; exit 1; }
  riscv64-unknown-elf-objdump -d $OUT/$1.elf | grep -qE "rdcycle|csrr.*cycle" || { echo "SCOPE FAIL $1: no cycle read"; exit 1; }
  echo "  $1 SPIN_CYCLES=$2 $(sha256sum $OUT/$1.elf | cut -c1-16)"
done
(cd $OUT && sha256sum *.elf > freq.sha256); echo FREQ_BUILD_OK
