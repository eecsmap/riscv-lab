#!/bin/bash
# PIPE-P4c: assemble the frozen artefact set in $P4C_WS/artefacts from the ACCEPTED sources, each checked against
# artefacts.sha256 (committed). Only the two frequency programs are built (reproducibly, build-freq-dual.sh: the two-hart
# freq_spin_dual.S). The gates are the six accepted M5 dual-hart programs; no single-hart program runs on this image.
set -euo pipefail
B=$(cd "$(dirname "$0")" && pwd); WS=${P4C_WS:-/home/engineer/fpga/worktrees/pipe-dual/experiments/pipeline/p4c/ws}; ART=$WS/artefacts; mkdir -p "$ART"
F=/home/engineer/fpga; IPS=$F/worktrees/ips-cache/experiments/IPS-campaign/board/elfs; MC=$F/experiments/multicore
cp "$F/worktrees/pipe-dual/experiments/pipeline/p4b/runs/attempt-1/reports/rocketchip_wrapper.bit.bin" "$ART/pipedual.bit.bin"
for f in dual01_boot dual02_clint dual03_lock dual04_pbus dual05_fencei dual07_long; do cp "$MC/m5-board/elfs-dual/$f.elf" "$ART/"; done
cp "$IPS/fesvr-teaching-static" "$MC/m5-board/elfs-dual/kernel-dual-128mib" "$MC/m5-board/elfs-dual/fs-dual-deploy.img" "$ART/"
cp "$MC/perf/elfs-dual/kernel-perf-128mib" "$MC/perf/elfs-dual/fs-perf.img" "$ART/"
T=$(mktemp -d /tmp/claude-1000/p4cfreq-XXXX); rmdir "$T"; bash "$B/build-freq-dual.sh" "$T" > /dev/null; cp "$T"/freq_spin_short.elf "$T"/freq_spin_long.elf "$ART/"
( cd "$ART" && sha256sum -c "$B/artefacts.sha256" ) && echo "FREEZE_OK $ART"
