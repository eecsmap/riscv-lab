#!/bin/bash
# PIPE-P3b: assemble the frozen artefact set in <art dir> (default ./artefacts) from the ACCEPTED sources, each
# checked against artefacts.sha256 (committed). Nothing is built here except the two frequency programs, whose
# hashes are reproducible (build-freq.sh) and also pinned in artefacts.sha256.
set -euo pipefail
B=$(cd "$(dirname "$0")" && pwd); ART=${1:-$B/artefacts}; mkdir -p "$ART"
F=/home/engineer/fpga; IPS=$F/worktrees/ips-cache/experiments/IPS-campaign/board/elfs; MC=$F/experiments/multicore
cp "$F/worktrees/pipe-single/experiments/pipeline/p3/runs/attempt-1/reports/rocketchip_wrapper.bit.bin" "$ART/pipe.bit.bin"
for f in boot01_marker boot02_clint boot03_ddr boot04_badaddr ext01_m ext02_c ext03_a ext04_sv39 perf02_sv39 perf03_fetch perf04_where perf06_iws; do cp "$IPS/$f.elf" "$ART/"; done
cp "$IPS/fesvr-teaching-static" "$ART/"
cp "$MC/m5-board/elfs-dual/kernel-dual-128mib" "$MC/m5-board/elfs-dual/fs-dual-deploy.img" "$ART/"
cp "$MC/perf/elfs-dual/kernel-perf-128mib" "$MC/perf/elfs-dual/fs-perf.img" "$ART/"
T=$(mktemp -d /tmp/claude-1000/p3bfreq-XXXX); rmdir "$T"; bash "$B/build-freq.sh" "$T" > /dev/null; cp "$T"/freq_spin_short.elf "$T"/freq_spin_long.elf "$ART/"
( cd "$ART" && sha256sum -c "$B/artefacts.sha256" ) && echo "FREEZE_OK $ART"
