#!/usr/bin/env bash
# Deploy the accepted bundle plus the four extension probes into a fresh directory on the board.
# /root/xv6run is empty after the cold boot (RAM initramfs), so nothing is overwritten.
set -u
R=/home/engineer/fpga
X=$R/experiments/teaching-cpu/xv6-board-run-3
P=$R/experiments/teaching-cpu/xv6-board-prep
S=$R/experiments/teaching-cpu/xv6-board-run/scripts/send-file.py
send() { python3 $S "$1" "$2" --log $X/logs/03-deploy.log || exit 1; }

for f in boot01_marker boot02_clint boot03_ddr boot04_badaddr; do
  send $P/deploy-bundle/$f.elf /root/xv6run/$f.elf
done
for f in ext01_m ext02_c ext03_a ext04_sv39; do
  send $P/probes/build/$f.elf /root/xv6run/$f.elf
done
send $P/deploy-bundle/kernel-128mib          /root/xv6run/kernel-128mib
send $P/deploy-bundle/fesvr-teaching-static  /root/xv6run/fesvr-teaching-static
send $P/deploy-bundle/fs-pristine.img        /root/xv6run/fs-run.img
send $R/experiments/teaching-cpu/xv6-board-run/derived/teaching.bit.bin /root/xv6run/teaching.bit.bin
echo DEPLOY_OK
