#!/usr/bin/env bash
# Build every dual program (rv64imac_zicsr, lp64, medany, no libc), record sha256 and load identity.
#   build.sh [outdir]      default progs/build
set -u; HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); OUT=${1:-$HERE/build}; mkdir -p "$OUT"
cd /home/engineer/fpga; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
GCC=riscv64-unknown-elf-gcc; CF="-march=rv64imac_zicsr_zifencei -mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -I$HERE"
rc=0
for src in $HERE/dual*.S $HERE/neg*.S; do n=$(basename ${src%.S})
  $GCC $CF -T $HERE/link.ld -o "$OUT/$n.elf" $HERE/start.S $HERE/htif.S $src 2> "$OUT/$n.build.log" || { echo "BUILD FAIL $n: $(head -3 $OUT/$n.build.log)"; rc=1; continue; }
  riscv64-unknown-elf-objdump -d "$OUT/$n.elf" > "$OUT/$n.dis"; echo "built $n"; done
(cd "$OUT" && sha256sum *.elf) > "$OUT/elf.sha256"
python3 /home/engineer/fpga/experiments/multicore/m2a/tests/elf_ident.py "$OUT"/*.elf > "$OUT/elf-load.sha256" 2>/dev/null
$GCC --version | head -1 > "$OUT/tools.txt"
exit $rc
