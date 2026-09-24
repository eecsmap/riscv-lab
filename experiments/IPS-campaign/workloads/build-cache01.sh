#!/usr/bin/env bash
#   build-cache01.sh <fresh outdir>
set -u
R=/home/engineer/fpga; WS=$R/teaching-cpu-work
P=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build-cache01.sh <fresh outdir>}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT"
set +u; source $R/experiments/chipyard-env.sh >/dev/null 2>&1; set -u
CC=riscv64-unknown-elf-gcc; LD=$R/experiments/teaching-cpu/m2-prep/tests/link.ld
BASE="-mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -I$WS/cpu/m3tests"
command -v $CC >/dev/null || { echo "REFUSE: $CC not on PATH"; exit 2; }
$CC $BASE -march=rv64i_zicsr_zifencei -c -o $OUT/cache01_smc.o $P/cache01_smc.S 2> $OUT/build.log || {
  echo "  BUILD FAIL"; head -8 $OUT/build.log; exit 1; }
$CC $BASE -march=rv64i_zicsr_zifencei -c -o $OUT/c01.htif.o $WS/cpu/m3tests/htif.S 2>> $OUT/build.log || {
  echo "  BUILD FAIL (htif)"; head -6 $OUT/build.log; exit 1; }
$CC $BASE -march=rv64i_zicsr_zifencei -T $LD -o $OUT/cache01_smc.elf $OUT/cache01_smc.o $OUT/c01.htif.o 2>> $OUT/build.log || {
  echo "  BUILD FAIL (link)"; head -8 $OUT/build.log; exit 1; }
riscv64-unknown-elf-objdump -d -M no-aliases $OUT/cache01_smc.elf > $OUT/cache01_smc.dis
# Scope: a self-modifying-code probe must contain fence.i AND a store into its own text, or it is
# testing something else entirely.
fail=0
for pair in "fence\.i:fence.i" "\bsw\b:a word store" "\blui\b:the instruction being replaced"; do
  rx=${pair%%:*}; what=${pair#*:}
  n=$(grep -cE "$rx" "$OUT/cache01_smc.dis" || true)
  [ "$n" = "0" ] && { echo "  SCOPE FAIL: no $what"; fail=1; } || printf "  ok: %-28s %s\n" "$what" "$n"
done
[ $fail = 0 ] || { echo "CACHE01_BUILD fail=1"; exit 1; }
sha256sum $OUT/cache01_smc.elf | tee $OUT/cache01_smc.sha256
echo "CACHE01_BUILD fail=0"
