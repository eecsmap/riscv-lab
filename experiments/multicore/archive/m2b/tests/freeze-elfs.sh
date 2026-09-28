#!/usr/bin/env bash
# Build the probe program set ONCE and freeze it: whole-file sha256 (elf.sha256) and load-semantic
# identity (elf-load.sha256, see elf_ident.py). rd2-probes.sh then takes ELFDIR=<this dir> and copies the
# same bytes for BEFORE and for AFTER, which is what makes "same programs" true by construction rather
# than by a per-run rebuild that embeds gcc's temporary object names.
#   freeze-elfs.sh <fresh outdir>
set -u
cd /home/engineer/fpga
R=/home/engineer/fpga; WS=$R/teaching-cpu-work; TC=$R/experiments/teaching-cpu; PREP=$TC/xv6-board-prep
CAMP=$R/worktrees/mc-dual-core/experiments/IPS-campaign
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OUT=${1:?fresh outdir}; [ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT/elf" "$OUT/logs"
set +u; source experiments/chipyard-env.sh >/dev/null; set -u
infra=0
for p in boot01_marker boot02_clint boot03_ddr boot04_badaddr; do cp "$PREP/deploy-bundle/$p.elf" "$OUT/elf/"; done
for p in ext01_m ext02_c ext03_a ext04_sv39; do cp "$PREP/probes/build/$p.elf" "$OUT/elf/"; done
for p in perf02_sv39 perf03_fetch perf04_where; do cp "$PREP/probes/build-perf/$p.elf" "$OUT/elf/"; done
bash "$CAMP/workloads/build-perf06.sh" "$OUT/b-perf06" > "$OUT/logs/perf06-build.log" 2>&1 && cp "$OUT/b-perf06/perf06_iws.elf" "$OUT/elf/" || { echo "INFRA: perf06 build"; infra=$((infra+1)); }
for t in tlb01 tlb02 cache01; do
  bash "$CAMP/workloads/build-$t.sh" "$OUT/b-$t" > "$OUT/logs/$t-build.log" 2>&1 && cp "$OUT/b-$t"/*.elf "$OUT/elf/" || { echo "INFRA: $t build"; infra=$((infra+1)); }
done
GCC=riscv64-unknown-elf-gcc
CF="-mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -I$WS/cpu/m3tests"
$GCC -march=rv64imc_zicsr $CF -T $TC/m2-prep/tests/link.ld -o "$OUT/elf/boot11_sv39.elf" $TC/cpu-sv39/tests/boot11_sv39.S $WS/cpu/m3tests/htif.S 2> "$OUT/logs/boot11-build.log" || { echo "INFRA: boot11 build"; infra=$((infra+1)); }
$GCC -march=rv64iac_zicsr $CF -T $TC/m2-prep/tests/link.ld -o "$OUT/elf/boot12_amo.elf" $TC/cpu-a/tests/boot12_amo.S $WS/cpu/m3tests/htif.S 2> "$OUT/logs/boot12-build.log" || { echo "INFRA: boot12 build"; infra=$((infra+1)); }
cp $R/xv6-on-rocket-pynq-z1/riscv-test/hello.riscv "$OUT/elf/hello.riscv"
[ $infra = 0 ] || { echo "FREEZE infra=$infra"; exit 1; }
(cd "$OUT/elf" && sha256sum *) > "$OUT/elf.sha256"
python3 "$HERE/elf_ident.py" "$OUT"/elf/* > "$OUT/elf-load.sha256"
{ echo "frozen $(date -u +%FT%TZ)"; riscv64-unknown-elf-gcc --version | head -1; } > "$OUT/tools.txt"
echo "FREEZE_OK $(wc -l < "$OUT/elf.sha256") programs in $OUT/elf"
