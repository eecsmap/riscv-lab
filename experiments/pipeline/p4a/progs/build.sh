#!/usr/bin/env bash
# PIPE-P4a: build the P4a dual programs exactly as multicore/m2b/progs/build.sh builds the M2b ones (same flags, the
# M2b start.S / htif.S / dual.h / link.ld, read-only).   build.sh <fresh outdir>
set -u; HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); M=/home/engineer/fpga/experiments/multicore/m2b/progs
OUT=${1:?outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p "$OUT"
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
GCC=riscv64-unknown-elf-gcc; CF="-march=rv64imac_zicsr_zifencei -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -I$M"
for src in $HERE/dual*.S; do n=$(basename ${src%.S})
  $GCC $CF -c -o $OUT/$n.o $src && $GCC $CF -c -o $OUT/start.o $M/start.S && $GCC $CF -c -o $OUT/htif.o $M/htif.S \
    && $GCC $CF -T $M/link.ld -o "$OUT/$n.elf" $OUT/start.o $OUT/htif.o $OUT/$n.o 2> "$OUT/$n.build.log" || { echo "BUILD FAIL $n"; exit 1; }
  echo "built $n $(sha256sum $OUT/$n.elf | cut -c1-16)"; done
(cd "$OUT" && sha256sum *.elf) > "$OUT/elf.sha256"
