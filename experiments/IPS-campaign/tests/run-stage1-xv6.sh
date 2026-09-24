#!/usr/bin/env bash
# xv6 with the frozen b0apps profile, on a named core, through the PRODUCTION lifecycle.
#
# Same kernel and same pristine disk as the accepted 2026-09-23 simulator record -- their hashes are
# checked here, not assumed -- so the software side of the comparison is identical and the CPU RTL is
# the only intended difference. The simulator BINARY necessarily differs; that is recorded as the
# confound it is.
#
#   run-stage1-xv6.sh <core: baseline|fetch32> <fresh outdir>
set -u
R=/home/engineer/fpga
CAMP=$(cd "$(dirname "$0")/.." && pwd)
CORE=${1:?usage: run-stage1-xv6.sh <baseline|fetch32> <outdir>}
OUT=${2:?outdir}
case "$CORE" in
  baseline) RTL=$R/worktrees/ips-baseline/rtl/cpu ;;
  fetch32)  RTL=$R/worktrees/ips-fetch32/rtl/cpu ;;
  *) echo "REFUSE: unknown core '$CORE'"; exit 2 ;;
esac
GEN=$R/teaching-cpu-work/fpga-zynq/simulation/src/verilog/RD2Harness.RD2AtomicXv6FastConfig.v
SRC=/tmp/b0simrun
KERNEL_SHA=6ad5c2338a31d59e5fb3fab74365c7f0334cf46e928f3baa20bf40e2df4a6a88
DISK_SHA=6bdd8148b79e5983ecaad04e394327f970e893a4c756a627b7e47da6e31c82ec
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }
mkdir -p "$OUT"

echo "== the software side must be IDENTICAL to the accepted record"
for pair in "kernel-4mib:$KERNEL_SHA" "fs-b0-pristine.img:$DISK_SHA"; do
  f=${pair%%:*}; want=${pair#*:}
  [ -f "$SRC/$f" ] || { echo "REFUSE: $SRC/$f is missing"; exit 2; }
  got=$(sha256sum "$SRC/$f" | cut -d' ' -f1)
  [ "$got" = "$want" ] || { echo "REFUSE: $f hashes $got, the accepted record says $want"; exit 2; }
  echo "  ok: $f = ${got:0:16}…"
done
cp "$SRC/kernel-4mib" "$OUT/kernel-4mib"
cp "$SRC/fs-b0-pristine.img" "$OUT/fs-b0.img"      # a FRESH copy for this sample, per the disk policy
echo "  fresh disk for this sample: $(sha256sum "$OUT/fs-b0.img" | cut -c1-16)…"

echo "== verilating the xv6 harness against the $CORE core"
bash "$CAMP/tests/build-xv6-sim.sh" "$GEN" "$RTL" "$OUT/sim" > "$OUT/build.log" 2>&1
grep -q XV6_SIM_BUILD_OK "$OUT/build.log" || {
  echo "  BUILD FAILED"; grep -m3 -E '%Error|FAIL' "$OUT/build.log"; exit 1; }
echo "  built: $(grep -A0 'obj_dir/sim' "$OUT/sim/inputs.sha256" | tail -1 | cut -c1-16)…"

cat > "$OUT/sim-host.sh" <<HOST
#!/bin/sh
# board_run launches a host as: exec <host-binary> +blkdev=<disk> <kernel>
exec "$OUT/sim/obj_dir/sim" +max-cycles=6000000000 +rd2_progress=20000000 "\$@"
HOST
chmod +x "$OUT/sim-host.sh"
cat > "$OUT/session.sh" <<'SESS'
#!/bin/sh
exec /bin/sh -c "$1"
SESS
chmod +x "$OUT/session.sh"

H=$(sha256sum "$OUT/sim-host.sh" | cut -d' ' -f1)
K=$(sha256sum "$OUT/kernel-4mib" | cut -d' ' -f1)
D=$(sha256sum "$OUT/fs-b0.img"   | cut -d' ' -f1)
echo "== driving xv6 through the production runner, workload b0apps"
python3 $R/riscv-lab/tools/board/scripts/board-runner.py "$OUT/run" \
  --transport-cmd "$OUT/session.sh" --channel multiplexed \
  --host-binary "$OUT/sim-host.sh" --kernel "$OUT/kernel-4mib" --disk "$OUT/fs-b0.img" \
  --evidence-dir /tmp/b0simrun/fix/safe-256 \
  --expect "$OUT/sim-host.sh=$H" --expect "$OUT/kernel-4mib=$K" --expect "$OUT/fs-b0.img=$D" \
  --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52 \
  --workload b0apps --stage-timeout 28800 --startup-timeout 28800 --stop-timeout 120
echo "XV6_RC=$? core=$CORE"
