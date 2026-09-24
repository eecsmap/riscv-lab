#!/usr/bin/env bash
# Build perf06_iws, and CHECK ITS FOOTPRINT rather than trusting the source.
#
# The accepted probe sources and their build script are read-only inputs to this campaign, so this
# builds only the new probe, with the same toolchain, linker script and htif.S they use.
#
# The scope check here is specific rather than a keyword grep: a probe that claims to exceed a 1 KiB
# cache has to be measured doing so. Both bodies are located in the disassembly and their byte spans
# compared against the frozen geometry.
set -u
R=/home/engineer/fpga
WS=$R/teaching-cpu-work
P=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build-perf06.sh <fresh outdir>}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT"
set +u; source $R/experiments/chipyard-env.sh >/dev/null 2>&1; set -u
CC=riscv64-unknown-elf-gcc
LD=$R/experiments/teaching-cpu/m2-prep/tests/link.ld
BASE="-mabi=lp64 -mcmodel=medany -nostdlib -nostartfiles -ffreestanding -O0 -Wall -I$WS/cpu/m3tests"
CACHE_BYTES=1024

command -v $CC >/dev/null || { echo "REFUSE: $CC is not on PATH"; exit 2; }
$CC $BASE -march=rv64i_zicsr -c -o $OUT/perf06_iws.o        $P/perf06_iws.S      2> $OUT/build.log || {
  echo "  BUILD FAIL"; head -5 $OUT/build.log; exit 1; }
$CC $BASE -march=rv64i_zicsr -c -o $OUT/perf06_iws.htif.o   $WS/cpu/m3tests/htif.S 2>> $OUT/build.log || {
  echo "  BUILD FAIL (htif)"; head -5 $OUT/build.log; exit 1; }
$CC $BASE -march=rv64i_zicsr -T $LD -o $OUT/perf06_iws.elf $OUT/perf06_iws.o $OUT/perf06_iws.htif.o 2>> $OUT/build.log || {
  echo "  BUILD FAIL (link)"; head -5 $OUT/build.log; exit 1; }
riscv64-unknown-elf-objdump -d -M no-aliases $OUT/perf06_iws.elf > $OUT/perf06_iws.dis

python3 - "$OUT/perf06_iws.dis" "$CACHE_BYTES" <<'PY'
import re, sys
dis, cache = open(sys.argv[1]).read(), int(sys.argv[2])
def span(sym):
    """Byte span from a function's label to its first csrr AFTER the body -- i.e. the loop footprint."""
    m = re.search(rf"^([0-9a-f]+) <{sym}>:$", dis, re.M)
    if not m: sys.exit(f"SCOPE FAIL: {sym} not in the disassembly")
    start = int(m.group(1), 16)
    body = dis[m.end():]
    nxt = re.search(r"^[0-9a-f]+ <\w+>:$", body, re.M)
    body = body[:nxt.start()] if nxt else body
    addrs = [int(a, 16) for a in re.findall(r"^\s*([0-9a-f]+):", body, re.M)]
    n_addi = len(re.findall(r"\baddi\b", body))
    return (max(addrs) - start + 4), n_addi
rs, rn = span("measure_resident")
es, en = span("measure_exceeds")
print(f"  measure_resident : {rs:5d} bytes, {rn:5d} addi   ({rs/cache:.2f}x the {cache}-byte cache)")
print(f"  measure_exceeds  : {es:5d} bytes, {en:5d} addi   ({es/cache:.2f}x the {cache}-byte cache)")
bad = []
if rs >= cache:      bad.append(f"the RESIDENT body is {rs} bytes and does not fit in {cache}")
if es <= cache:      bad.append(f"the EXCEEDS body is {es} bytes and does NOT exceed {cache}")
if en < 1024:        bad.append(f"the EXCEEDS body has only {en} addi; it was expected to be 1024")
if bad:
    print("SCOPE FAIL:"); [print("   -", b) for b in bad]; sys.exit(1)
print("  footprints are on the right sides of the frozen 1 KiB geometry")
PY
rc=$?
[ $rc = 0 ] || { echo "PERF06_BUILD fail=1"; exit 1; }

# The probe asserts its own retirement count; that assertion is only worth having if the constant is
# right. Derive it from the real instructions in the real binary, not from arithmetic done by hand.
python3 $P/check_retirement.py $OUT/perf06_iws.dis || { echo "PERF06_BUILD fail=1"; exit 1; }
sha256sum $OUT/perf06_iws.elf | tee $OUT/perf06_iws.sha256
echo "PERF06_BUILD fail=0"
