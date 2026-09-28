#!/usr/bin/env bash
# Build tlb01_sfence, and check it actually contains what it claims to test.
#   build-tlb01.sh <fresh outdir>
set -u
R=/home/engineer/fpga
WS=$R/teaching-cpu-work
P=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build-tlb01.sh <fresh outdir>}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT"
set +u; source $R/experiments/chipyard-env.sh >/dev/null 2>&1; set -u
CC=riscv64-unknown-elf-gcc
LD=$R/experiments/teaching-cpu/m2-prep/tests/link.ld
BASE="-mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -I$WS/cpu/m3tests"
command -v $CC >/dev/null || { echo "REFUSE: $CC not on PATH"; exit 2; }
$CC $BASE -march=rv64i_zicsr -c -o $OUT/tlb01_sfence.o      $P/tlb01_sfence.S       2> $OUT/build.log || {
  echo "  BUILD FAIL"; head -6 $OUT/build.log; exit 1; }
$CC $BASE -march=rv64i_zicsr -c -o $OUT/tlb01_sfence.htif.o $WS/cpu/m3tests/htif.S 2>> $OUT/build.log || {
  echo "  BUILD FAIL (htif)"; head -6 $OUT/build.log; exit 1; }
$CC $BASE -march=rv64i_zicsr -T $LD -o $OUT/tlb01_sfence.elf $OUT/tlb01_sfence.o $OUT/tlb01_sfence.htif.o 2>> $OUT/build.log || {
  echo "  BUILD FAIL (link)"; head -6 $OUT/build.log; exit 1; }
riscv64-unknown-elf-objdump -d -M no-aliases $OUT/tlb01_sfence.elf > $OUT/tlb01_sfence.dis

# Scope: a probe that claims to test invalidation must contain sfence.vma AND a satp write AND a trap
# handler, or it is testing something else.
fail=0
for pair in "sfence\.vma:sfence.vma" "csrr[wsc].*medeleg:a medeleg write" "csrrw.*satp:a satp write" "csrr[wsc].*stvec:an stvec write" "sret:sret"; do
  rx=${pair%%:*}; what=${pair#*:}
  n=$(grep -cE "\b$rx" "$OUT/tlb01_sfence.dis" || true)
  if [ "$n" = "0" ]; then echo "  SCOPE FAIL: no $what in the disassembly"; fail=1
  else printf "  ok: %-18s %s occurrence(s)\n" "$what" "$n"; fi
done
[ $fail = 0 ] || { echo "TLB01_BUILD fail=1"; exit 1; }
sha256sum $OUT/tlb01_sfence.elf | tee $OUT/tlb01_sfence.sha256
echo "TLB01_BUILD fail=0"
