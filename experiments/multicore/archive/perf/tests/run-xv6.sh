#!/usr/bin/env bash
# MC-M3: drive xv6 through the (isolated copy of the) production runner on a NAMED simulator with a NAMED
# kernel and a FRESH copy of a named disk, with an explicit cycle budget and wall cap.
#   run-xv6.sh <sim binary> <kernel> <disk image> <workload> <fresh outdir> <max-cycles> <wall-s> [stage-timeout-s]
set -u; R=/home/engineer/fpga; M3=$R/experiments/multicore/perf
SIM=${1:?sim}; KERNEL=${2:?kernel}; DISK=${3:?disk}; WL=${4:?workload}; OUT=${5:?outdir}; MAXCYC=${6:?max-cycles}; WALL=${7:?wall}; STAGE=${8:-3600}
for f in "$SIM" "$KERNEL" "$DISK"; do [ -s "$f" ] || { echo "REFUSE: missing $f"; exit 2; }; done
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists"; exit 2; }; mkdir -p "$OUT"
cd $R; set +u; source experiments/chipyard-env.sh >/dev/null; set -u
cp "$KERNEL" "$OUT/kernel"; cp "$DISK" "$OUT/fs.img"      # a fresh disk copy for this run, per the disk policy
# the kernel's scheduler() range for the per-hart range counter (from this kernel's own symbols)
# DECIMAL: plusarg_reader parses %d, a 0x value would read as 0 (= counter off) -- found on the first run
LO=$(( $(riscv64-unknown-elf-nm -S "$OUT/kernel" | awk '$4=="scheduler"{print "0x"$1}') )); SZ=$(( $(riscv64-unknown-elf-nm -S "$OUT/kernel" | awk '$4=="scheduler"{print "0x"$2}') ))
HI=$(( LO + SZ ))
cat > "$OUT/sim-host.sh" <<HOST
#!/bin/sh
# board_run launches a host as: exec <host-binary> +blkdev=<disk> <kernel>
exec "$SIM" +max-cycles=$MAXCYC +rd2_progress=20000000 +rd2_range_lo=$LO +rd2_range_hi=$HI "\$@"
HOST
chmod +x "$OUT/sim-host.sh"
printf '#!/bin/sh\nexec /bin/sh -c "$1"\n' > "$OUT/session.sh"; chmod +x "$OUT/session.sh"
H=$(sha256sum "$OUT/sim-host.sh" | cut -d' ' -f1); K=$(sha256sum "$OUT/kernel" | cut -d' ' -f1); D=$(sha256sum "$OUT/fs.img" | cut -d' ' -f1)
{ echo "sim=$SIM ($(sha256sum $SIM | cut -c1-16))"; echo "kernel=$KERNEL ($K)"; echo "disk=$DISK ($D)"; echo "workload=$WL max_cycles=$MAXCYC wall=$WALL stage=$STAGE scheduler=[$(printf '0x%x' $LO),$(printf '0x%x' $HI)) (plusargs decimal $LO $HI)"; echo "start=$(date -u +%FT%TZ)"; } > "$OUT/cmd.txt"
s=$(date +%s)
timeout "$WALL" python3 $M3/tools/board/scripts/board-runner.py "$OUT/run" \
  --transport-cmd "$OUT/session.sh" --channel multiplexed \
  --host-binary "$OUT/sim-host.sh" --kernel "$OUT/kernel" --disk "$OUT/fs.img" \
  --evidence-dir /tmp/b0simrun/fix/safe-256 \
  --expect "$OUT/sim-host.sh=$H" --expect "$OUT/kernel=$K" --expect "$OUT/fs.img=$D" \
  --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52 \
  --workload "$WL" --stage-timeout "$STAGE" --startup-timeout "$STAGE" --stop-timeout 120 > "$OUT/runner.log" 2>&1
rc=$?; e=$(date +%s)
echo "XV6_RC=$rc wall=$((e-s))s" | tee "$OUT/verdict.txt"; tail -2 "$OUT/runner.log" | cut -c1-160
grep -E "^(HARTS|HARTS_USER|CYCLES|AXI|RD2HOST FINAL)" "$OUT/run/console.txt" 2>/dev/null | cut -c1-200
exit $rc
