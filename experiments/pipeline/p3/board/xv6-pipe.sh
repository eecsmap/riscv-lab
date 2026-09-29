#!/bin/sh
# PIPE-P3b: interactive xv6 on the single-pipeline core (payload 5f97d4ab…), installed in /root/xv6run.
#   ./xv6-pipe.sh            boot xv6 on the user disk /root/xv6run/fs-user.img (persistent across relaunches; lost
#                            at power-off, the root filesystem is RAM)
#   ./xv6-pipe.sh <disk>     boot another disk image (e.g. /root/xv6run/fs-user-previous.img if present)
#   ./xv6-pipe.sh --check    check everything and start nothing
# Stop: wait for the xv6 `$ ` prompt (no command running), press Ctrl-C once; the host exits and the lock is released.
# It takes the production host lock /var/lock/teaching-fesvr.lock, so no agent run can start while xv6 is up.
cd /root/xv6run || exit 1
K=/root/xv6run/kernel-perf-128mib; H=./fesvr-teaching-static; L=/var/lock/teaching-fesvr.lock
DISK=/root/xv6run/fs-user.img; CHECK=no
case "${1:-}" in --check) CHECK=yes ;; "") ;; *) DISK=$1 ;; esac
PD=$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done)
[ "$PD" = 1 ] || { echo "the PL is not programmed (prog_done=$PD): not starting"; exit 1; }
[ -x "$H" ] && [ -f "$K" ] && [ -f "$DISK" ] || { echo "missing: host $H, kernel $K or disk $DISK"; exit 1; }
[ "$(pgrep -x fesvr-teaching-static | wc -l)" = 0 ] || { echo "a host is already running: not starting"; exit 1; }
mkdir -p /var/lock
if [ -e "$L" ]; then echo "the host lock $L is held ($(cat $L/owner 2>/dev/null)): not starting"; exit 1; fi
if [ "$CHECK" = yes ]; then echo "CHECK OK: prog_done=1, host, kernel $K, disk $DISK present; no host running; lock free"; exit 0; fi
mkdir "$L" || { echo "could not take the host lock: not starting"; exit 1; }
echo "user-interactive xv6-pipe.sh" > "$L/owner"; echo $$ > "$L/pid"
trap 'true' INT
echo "xv6 on the single-pipeline core: disk $DISK. Stop: Ctrl-C at the xv6 prompt. Relaunch: $0"
"$H" +blkdev="$DISK" "$K"
rc=$?
rm -f "$L/owner" "$L/pid"; rmdir "$L"
echo "xv6 host exited (status $rc); lock released. Relaunch with: $0"
