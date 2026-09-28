#!/usr/bin/env bash
#   build-tlb02.sh <fresh outdir>
set -u
R=/home/engineer/fpga
WS=$R/teaching-cpu-work
P=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build-tlb02.sh <fresh outdir>}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT"
set +u; source $R/experiments/chipyard-env.sh >/dev/null 2>&1; set -u
CC=riscv64-unknown-elf-gcc
LD=$R/experiments/teaching-cpu/m2-prep/tests/link.ld
BASE="-mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -I$WS/cpu/m3tests"
command -v $CC >/dev/null || { echo "REFUSE: $CC not on PATH"; exit 2; }
$CC $BASE -march=rv64i_zicsr -c -o $OUT/tlb02_canonical.o $P/tlb02_canonical.S 2> $OUT/build.log || {
  echo "  BUILD FAIL"; head -8 $OUT/build.log; exit 1; }
$CC $BASE -march=rv64i_zicsr -c -o $OUT/tlb02.htif.o $WS/cpu/m3tests/htif.S 2>> $OUT/build.log || {
  echo "  BUILD FAIL (htif)"; head -6 $OUT/build.log; exit 1; }
$CC $BASE -march=rv64i_zicsr -T $LD -o $OUT/tlb02_canonical.elf $OUT/tlb02_canonical.o $OUT/tlb02.htif.o 2>> $OUT/build.log || {
  echo "  BUILD FAIL (link)"; head -8 $OUT/build.log; exit 1; }
riscv64-unknown-elf-objdump -d -M no-aliases $OUT/tlb02_canonical.elf > $OUT/tlb02_canonical.dis
fail=0
for pair in "csrr[wsc].*medeleg:a medeleg write" "csrr[wsc].*satp:a satp write" "csrr[wsc].*stvec:an stvec write" "csrrs.*stval:a stval READ" "sret:sret" "jalr:an indirect jump"; do
  rx=${pair%%:*}; what=${pair#*:}
  n=$(grep -cE "\b$rx" "$OUT/tlb02_canonical.dis" || true)
  if [ "$n" = "0" ]; then echo "  SCOPE FAIL: no $what"; fail=1; else printf "  ok: %-20s %s\n" "$what" "$n"; fi
done
[ $fail = 0 ] || { echo "TLB02_BUILD fail=1"; exit 1; }
sha256sum $OUT/tlb02_canonical.elf | tee $OUT/tlb02_canonical.sha256
echo "TLB02_BUILD fail=0"
