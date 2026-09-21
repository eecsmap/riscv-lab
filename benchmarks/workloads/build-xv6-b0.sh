#!/usr/bin/env bash
# Build the B0 application image: the imported xv6 tree plus the three B0 user programs.
#
# The imported tree under software/xv6 is NEVER modified -- it is provenance-protected and the accepted
# kernel and disk were built from it. This copies it to a build directory, adds the three programs, and
# builds there. The build directory is generated and is not committed.
#
# The resulting KERNEL is expected to be byte-identical to the accepted one: the three programs live in
# fs.img, not in the kernel. The DISK differs, and is therefore a different workload image.
#
#   build-xv6-b0.sh [outdir]        default: benchmarks/workloads/xv6-b0
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT=${1:-$HERE/xv6-b0}

rm -rf "$OUT"
mkdir -p "$OUT"
cp -r "$ROOT/software/xv6/." "$OUT/"
cp "$HERE/src/b0compute.c" "$HERE/src/b0array.c" "$HERE/src/b0file.c" "$OUT/user/"

python3 - "$OUT/Makefile" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "UPROGS=\\\n"
assert s.count(old) == 1, "UPROGS not found exactly once in the xv6 Makefile"
s = s.replace(old, "UPROGS=\\\n\t$U/_b0compute\\\n\t$U/_b0array\\\n\t$U/_b0file\\\n", 1)
open(p, "w").write(s)
PY

make -B -C "$OUT" kernel/kernel fs.img CPPFLAGS=-DTEACHING_SIM_MEM_MIB=128 \
  ${TOOLPREFIX:+TOOLPREFIX=$TOOLPREFIX} > "$OUT/build.log" 2>&1 || {
    echo "BUILD FAIL -- see $OUT/build.log"; tail -5 "$OUT/build.log"; exit 1; }

echo "XV6_B0_BUILT"
echo "  kernel  $(sha256sum "$OUT/kernel/kernel" | cut -d' ' -f1)"
echo "  fs.img  $(sha256sum "$OUT/fs.img" | cut -d' ' -f1)"
echo "  accepted kernel e990fb31fad483b805aaeae77ecaebb3111abcec012d70447c620c9e9b289c2c"
echo "  accepted disk   4691ffea6b05562d33a599a3406ab3b6d69e6c2444addb08838f1ef6f97527b7"
