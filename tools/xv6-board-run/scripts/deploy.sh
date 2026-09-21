#!/usr/bin/env bash
# Deploy the approved bundle to a dedicated directory on the board. Nothing existing is overwritten:
# /root/xv6run is new, and the initramfs's own /root files (fesvr-zynq, fs.img, xv6-kernel from Sep 9) are
# left exactly where they are -- they are NOT the approved artefacts and are not used.
set -u
R=/home/engineer/fpga
X=$R/experiments/teaching-cpu/xv6-board-run
P=$R/experiments/teaching-cpu/xv6-board-prep
send() { python3 $X/scripts/send-file.py "$1" "$2" --log $X/logs/13-deploy.log || exit 1; }

send $P/deploy-bundle/boot02_clint.elf     /root/xv6run/boot02_clint.elf
send $P/deploy-bundle/boot03_ddr.elf       /root/xv6run/boot03_ddr.elf
send $P/deploy-bundle/boot04_badaddr.elf   /root/xv6run/boot04_badaddr.elf
send $P/deploy-bundle/fesvr-teaching-static /root/xv6run/fesvr-teaching-static
send $P/deploy-bundle/fs-pristine.img      /root/xv6run/fs-run.img
send $X/derived/teaching.bit.bin           /root/xv6run/teaching.bit.bin
echo DEPLOY_OK
