#!/usr/bin/env bash
# MC-M1 T1.10: xv6 with the frozen b0apps profile through the PRODUCTION lifecycle, on a simulator built
# from a NAMED generated Verilog (the TeachingHart one) and a NAMED cpu RTL directory.
#
# Same kernel and same pristine disk as the accepted record -- hashes checked, not assumed -- so the only
# intended difference from experiments/IPS-campaign/runs/xv6-cache is the wrapper. Cycle budget 2e9 and
# a 4 h wall cap, sized from the accepted cache run (463,881,498 cycles, 2,917 s) with headroom; a timeout
# is a result, not a retry.
#
#   run-xv6-m1.sh <generated.v> <cpu-rtl-dir> <fresh outdir>
set -u
R=/home/engineer/fpga
CAMP=$R/worktrees/mc-single-wrapper/experiments/IPS-campaign
GEN=${1:?generated verilog}; RTL=${2:?cpu rtl dir}; OUT=${3:?outdir}
SRC=/tmp/b0simrun
KERNEL_SHA=6ad5c2338a31d59e5fb3fab74365c7f0334cf46e928f3baa20bf40e2df4a6a88
DISK_SHA=6bdd8148b79e5983ecaad04e394327f970e893a4c756a627b7e47da6e31c82ec
[ -s "$GEN" ] || { echo "REFUSE: missing $GEN"; exit 2; }
[ -d "$RTL" ] || { echo "REFUSE: missing rtl $RTL"; exit 2; }
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
echo "== verilating the xv6 harness: $GEN ($(sha256sum "$GEN" | cut -c1-16)) against $RTL ($(sha256sum "$RTL/tcpu_core.v" | cut -c1-16))"
s=$(date +%s)
bash "$CAMP/tests/build-xv6-sim.sh" "$GEN" "$RTL" "$OUT/sim" > "$OUT/build.log" 2>&1
e=$(date +%s)
grep -q XV6_SIM_BUILD_OK "$OUT/build.log" || { echo "  BUILD FAILED ($((e-s)) s)"; grep -m3 -E '%Error|FAIL' "$OUT/build.log"; exit 1; }
echo "  built in $((e-s)) s: $(grep obj_dir/sim "$OUT/sim/inputs.sha256" | cut -c1-16)…"
cat > "$OUT/sim-host.sh" <<HOST
#!/bin/sh
# board_run launches a host as: exec <host-binary> +blkdev=<disk> <kernel>
exec "$OUT/sim/obj_dir/sim" +max-cycles=2000000000 +rd2_progress=20000000 "\$@"
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
echo "== driving xv6 through the production runner, workload b0apps (wall cap 4 h)"
s=$(date +%s)
timeout 14400 python3 $R/riscv-lab/tools/board/scripts/board-runner.py "$OUT/run" \
  --transport-cmd "$OUT/session.sh" --channel multiplexed \
  --host-binary "$OUT/sim-host.sh" --kernel "$OUT/kernel-4mib" --disk "$OUT/fs-b0.img" \
  --evidence-dir /tmp/b0simrun/fix/safe-256 \
  --expect "$OUT/sim-host.sh=$H" --expect "$OUT/kernel-4mib=$K" --expect "$OUT/fs-b0.img=$D" \
  --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52 \
  --workload b0apps --stage-timeout 7200 --startup-timeout 7200 --stop-timeout 120
rc=$?; e=$(date +%s)
echo "XV6_RC=$rc wall=$((e-s))s"
