#!/usr/bin/env bash
# PIPE-P4c: build the two-hart frequency-reference programs with the M2b dual flags, entry, htif and link script
# (read-only, as p4a/progs/build.sh does).   build-freq-dual.sh <fresh outdir> [name:SPIN_CYCLES ...]
# Default: freq_spin_short 40000000, freq_spin_long 840000000 (P3b's sizes); a sim check passes small sizes.
set -u; SRC=$(cd "$(dirname "$0")" && pwd)/src; M=/home/engineer/fpga/experiments/multicore/m2b/progs
OUT=${1:?outdir}; shift; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p "$OUT"
[ $# -gt 0 ] || set -- freq_spin_short:40000000 freq_spin_long:840000000
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
GCC=riscv64-unknown-elf-gcc; CF="-march=rv64imac_zicsr_zifencei -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -I$M"
for v in "$@"; do n=${v%%:*}; c=${v#*:}
  $GCC $CF -DSPIN_CYCLES=$c -c -o $OUT/$n.o $SRC/freq_spin_dual.S && $GCC $CF -c -o $OUT/start.o $M/start.S && $GCC $CF -c -o $OUT/htif.o $M/htif.S \
    && $GCC $CF -T $M/link.ld -o $OUT/$n.elf $OUT/start.o $OUT/htif.o $OUT/$n.o 2> $OUT/$n.buildlog || { echo "BUILD FAIL $n"; exit 1; }
  riscv64-unknown-elf-objdump -d $OUT/$n.elf > $OUT/$n.dis
  grep -qE "csrr.*cycle|rdcycle" $OUT/$n.dis && grep -q "wfi" $OUT/$n.dis || { echo "SCOPE FAIL $n: no cycle read or no park"; exit 1; }
  echo "  $n SPIN_CYCLES=$c $(sha256sum $OUT/$n.elf | cut -c1-16)"
done
(cd $OUT && sha256sum *.elf > freq.sha256); echo FREQ_BUILD_OK
