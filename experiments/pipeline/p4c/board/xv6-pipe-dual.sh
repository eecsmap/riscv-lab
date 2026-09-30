#!/bin/sh
# PIPE-P4c: interactive xv6 on the DUAL-pipeline system (two pipelined harts; payload f330769d…), in /root/xv6run.
#   ./xv6-pipe-dual.sh            boot xv6 on your persistent disk /root/xv6run/fs-user.img (kept across relaunches;
#                                 lost at power-off: the board's root filesystem is RAM)
#   ./xv6-pipe-dual.sh <disk>     boot another disk image (e.g. /root/xv6run/fs-user-previous.img)
#   ./xv6-pipe-dual.sh --bench    boot a FRESH benchmark disk: fs-bench.img is re-made from the read-only pristine
#                                 copy fs-bench-pristine.img (hash-checked) on every --bench launch
#   ./xv6-pipe-dual.sh --check    check everything and start nothing
# Stop: wait for the xv6 `$ ` prompt (no command running), press Ctrl-C once; the host exits and the lock is released.
# It takes the production host lock /var/lock/teaching-fesvr.lock, so no agent run can start while xv6 is up.
cd /root/xv6run || exit 1
K=/root/xv6run/kernel-perf-128mib; H=./fesvr-teaching-static; L=/var/lock/teaching-fesvr.lock
PRISTINE=/root/xv6run/fs-bench-pristine.img; PRISTINE_SHA=d558e4444abcea6046147d85b81e538ecf604049b6d8ab15552f9a3d32bf688c
DISK=/root/xv6run/fs-user.img; CHECK=no; BENCH=no
case "${1:-}" in --check) CHECK=yes ;; --bench) BENCH=yes; DISK=/root/xv6run/fs-bench.img ;; "") ;; *) DISK=$1 ;; esac
PD=$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done)
[ "$PD" = 1 ] || { echo "the PL is not programmed (prog_done=$PD): not starting"; exit 1; }
[ -x "$H" ] && [ -f "$K" ] || { echo "missing: host $H or kernel $K"; exit 1; }
[ "$BENCH" = yes ] || [ -f "$DISK" ] || { echo "missing disk $DISK"; exit 1; }
# a running host: its kernel name (comm) is the first 15 characters, "fesvr-teaching-"; `pgrep -x` of the full
# 21-character name cannot match that on every pgrep, so the comm scan is the check and pgrep only an extra one
hosts() { n=0; for c in /proc/[0-9]*/comm; do [ "$(cat "$c" 2>/dev/null)" = fesvr-teaching- ] && n=$((n+1)); done; echo $n; }
[ "$(hosts)" = 0 ] && [ "$(pgrep -x fesvr-teaching-static | wc -l)" = 0 ] || { echo "a host is already running: not starting"; exit 1; }
mkdir -p /var/lock
if [ -e "$L" ]; then echo "the host lock $L is held ($(cat $L/owner 2>/dev/null)): not starting"; exit 1; fi
if [ "$CHECK" = yes ]; then
  [ "$(sha256sum "$PRISTINE" 2>/dev/null | cut -d' ' -f1)" = "$PRISTINE_SHA" ] || { echo "the pristine benchmark disk $PRISTINE is missing or changed"; exit 1; }
  echo "CHECK OK: prog_done=1, host, kernel $K, disk $DISK, pristine benchmark disk present; no host running; lock free"; exit 0; fi
mkdir "$L" || { echo "could not take the host lock: not starting"; exit 1; }
echo "user-interactive xv6-pipe-dual.sh" > "$L/owner"; echo $$ > "$L/pid"
if [ "$BENCH" = yes ]; then
  if [ "$(sha256sum "$PRISTINE" | cut -d' ' -f1)" != "$PRISTINE_SHA" ] || ! cp "$PRISTINE" "$DISK"; then
    echo "the pristine benchmark disk is missing or changed: not starting"; rm -f "$L/owner" "$L/pid"; rmdir "$L"; exit 1; fi
  echo "fresh benchmark disk: $DISK (a fresh copy of fs-bench-pristine.img)"
fi
trap 'true' INT
echo "xv6 on the dual-pipeline system (2 harts): disk $DISK. Stop: Ctrl-C at the xv6 prompt. Relaunch: $0"
"$H" +blkdev="$DISK" "$K"
rc=$?
rm -f "$L/owner" "$L/pid"; rmdir "$L"
echo "xv6 host exited (status $rc); lock released. Relaunch with: $0"
