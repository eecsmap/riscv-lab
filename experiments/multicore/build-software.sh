#!/usr/bin/env bash
# Build a fresh copy, never mutate the archived or shared source trees.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
MIB=${1:-128}
case "$MIB" in 4|128) ;; *) echo 'usage: build-software.sh [4|128]' >&2; exit 2;; esac
mkdir -p "$ROOT/build"
OUT=$(mktemp -d "$ROOT/build/mc-software-${MIB}.XXXXXX")
cp -R "$ROOT/software/xv6" "$OUT/xv6"
make -C "$OUT/xv6" -j4 kernel/kernel fs.img \
  CPPFLAGS="-DTEACHING_SIM_MEM_MIB=$MIB -DTEACHING_PLATFORM_NO_PLIC_DEVICES"
sha256sum "$OUT/xv6/kernel/kernel" "$OUT/xv6/fs.img"
printf 'Build retained in %s\n' "$OUT"
