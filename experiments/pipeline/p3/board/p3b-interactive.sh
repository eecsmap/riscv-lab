#!/bin/bash
# PIPE-P3b interactive handoff, same boot as the install session, after m4smoke and perf-board have passed on it:
# installs the launcher /root/xv6run/xv6-pipe.sh, the performance kernel, the user's OWN disk fs-user.img (a fresh
# copy of fs-perf.img, byte-identical to the disk the perf-board run verified; never overwritten if it exists), the
# pre-cycle backup of the user's previous disk as fs-user-previous.img (if one was taken), checks the launcher, boot-
# tests it once on a THROWAWAY copy (removed afterwards), and leaves NO host running, NO lock, and no lease held.
set -euo pipefail
cd "$(dirname "$0")"; . ./p3b-lib.sh
S=${1:?install session}; O=${P3B_OUT:-$P3B/state}
[ -s "$S/completed.txt" ] || die 2 "$S is not a completed install session"
for wl in m4smoke perf-board; do   # both judged runs must have passed on this boot, or there is nothing verified to hand over
  ok=0; for x in "$S"/xv6-$wl-*; do [ -f "$x/check.txt" ] && grep -q "^XV6_RC=0 " "$x/verdict.txt" && tail -n 1 "$x/check.txt" | grep -q "^PASS" && ok=1; done
  [ $ok = 1 ] || die 2 "no passing $wl run in $S: not handing over"; done
H=$S/handoff-$(date -u +%Y%m%dT%H%M%SZ); mkdir -p "$H"; export E1_LOG=$H/session.log
trap release_owned_leases EXIT
p3b_check_artefacts; claim_leases board serial
board_must "reading the state" "mkdir -p /var/lock; echo BID=\$(cat /proc/sys/kernel/random/boot_id); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo F=\$(pgrep -x fesvr-teaching-static | wc -l); echo L=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); echo PSHA=\$(sha256sum /root/xv6run/pipe.bit.bin | cut -d' ' -f1); echo USERDISK=\$(test -e $USER_DISK && sha256sum $USER_DISK | cut -d' ' -f1 || echo NONE)"
[ "$(field BID)" = "$(cat "$S/boot-id.txt")" ] || die $EX_NOT_COLD "the boot id changed since the install session"
[ "$(field PD)" = 1 ] || die $EX_PROG "prog_done is not 1"; [ "$(field F)" = 0 ] || die $EX_BUSY "a host is running"
[ "$(field L)" = NO_LOCK ] || die $EX_BUSY "the host lock is present"; [ "$(field PSHA)" = "$PAYLOAD_SHA" ] || die $EX_HASH "the payload file on the board is not $PAYLOAD_SHA"
UD=$(field USERDISK)
say "== the launcher, the performance kernel, the user's disk"
deploy_verified "$P3B/xv6-pipe.sh" /root/xv6run/xv6-pipe.sh "$H/deploy.log"
deploy_verified "$ART/kernel-perf-128mib" /root/xv6run/kernel-perf-128mib "$H/deploy.log"
if [ "$UD" = NONE ]; then deploy_verified "$ART/fs-perf.img" $USER_DISK "$H/deploy.log"; say "  fs-user.img: a fresh copy of fs-perf.img (d558e444…)"
else say "  fs-user.img already exists (sha ${UD:0:16}…): NOT overwritten"; fi
if [ -d "$O/backup" ] && grep -q '^BACKUP ' "$O/backup/backup.txt" 2>/dev/null; then
  for n in $(awk '$1=="BACKUP" && $3 ~ /\.img$/ {print $3}' "$O/backup/backup.txt"); do
    deploy_verified "$O/backup/$n" /root/xv6run/fs-user-previous.img "$H/deploy.log"; say "  the pre-cycle backup of $n is /root/xv6run/fs-user-previous.img"; done
fi
make_executable /root/xv6run/xv6-pipe.sh
board_must "checking the launcher" "cd /root/xv6run && ./xv6-pipe.sh --check; echo RC=\$?"
printf '%s\n' "$BOARD_OUT" > "$H/launcher-check.txt"; [ "$(field RC)" = 0 ] && grep -q "CHECK OK" "$H/launcher-check.txt" || die $EX_GATE "the launcher check failed"
say "== boot test of the launcher on a THROWAWAY disk copy"
deploy_verified "$ART/fs-perf.img" /root/xv6run/fs-launchtest.img "$H/deploy.log"
python3 "$P3B/launch-test.py" /root/xv6run/fs-launchtest.img "$H/launch-test.transcript" | tee "$H/launch-test.txt"; lt=${PIPESTATUS[0]}
board_must "removing the throwaway disk and reading the final state" "rm -f /root/xv6run/fs-launchtest.img; echo F=\$(pgrep -x fesvr-teaching-static | wc -l); echo L=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo BID=\$(cat /proc/sys/kernel/random/boot_id); cd /root/xv6run && ls -la && sha256sum *"
printf '%s\n' "$BOARD_OUT" > "$H/final-state.txt"
[ "$(field F)" = 0 ] && [ "$(field L)" = NO_LOCK ] || die $EX_BUSY "after the boot test a host or the lock remains: NOT handed over"
[ "$lt" = 0 ] || die $EX_GATE "the launcher boot test failed: NOT handed over (see $H)"
say "P3B_HANDOFF_READY: no host running, lock free; the user launches with: cd /root/xv6run && ./xv6-pipe.sh"
