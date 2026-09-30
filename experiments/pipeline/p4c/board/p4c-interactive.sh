#!/bin/bash
# PIPE-P4c interactive handoff, same boot as the install session, after m4smoke and perf-board have passed on it (copy
# of P3b's p3b-interactive.sh for the two-hart image). Installs in /root/xv6run:
#   xv6-pipe-dual.sh, kernel-perf-128mib             the launcher and the measurement kernel
#   every user disk image backed up by the pre-cycle step, restored under its own name (fs-user.img = the persistent
#   disk the user was using, fs-user-previous.img = the one before); fs-run.img (the agents' benchmark scratch) is
#   NOT restored (its backup stays on this PC). If there was no fs-user.img, a fresh copy of fs-perf.img becomes it.
#   fs-bench-pristine.img (read-only, = fs-perf.img d558e444…) and fs-bench.img (a fresh copy; `--bench` re-makes it)
# then checks the launcher, tests launch / commands / stop / restart / stop on a THROWAWAY copy (removed afterwards,
# whatever the result), and leaves NO host running, NO lock, and no lease held.
set -euo pipefail
cd "$(dirname "$0")"; . ./p4c-lib.sh
S=${1:?install session}; O=$(cat "$S/precycle.txt")
# the user disks come from the pre-cycle step that backed them up: when a later pre-cycle step re-pinned an already
# empty board (P4c: the first install refused a 1811 s uptime), P4C_BACKUP_DIR names the original backups
BK=${P4C_BACKUP_DIR:-$O/backup}; [ -s "$BK/backup.txt" ] && ( cd "$BK" && sha256sum -c backup.sha256 > /dev/null ) || die $EX_HASH "no verified backup set in $BK"
[ -s "$S/completed.txt" ] || die 2 "$S is not a completed install session"
for wl in m4smoke perf-board; do   # both judged runs must have passed on this boot, or there is nothing verified to hand over
  ok=0; for x in "$S"/xv6-$wl-*; do [ -f "$x/check.txt" ] && grep -q "^XV6_RC=0 " "$x/verdict.txt" && tail -n 1 "$x/check.txt" | grep -q "^PASS" \
    && grep -q "^HART_CHECK PASS" "$x/hart-check.txt" && ok=1; done
  [ $ok = 1 ] || die 2 "no passing $wl run in $S: not handing over"; done
H=$S/handoff-$(date -u +%Y%m%dT%H%M%SZ); mkdir -p "$H"; export E1_LOG=$H/session.log
trap release_owned_leases EXIT
p4c_check_artefacts; claim_leases board serial
board_must "reading the state" "mkdir -p /var/lock; echo BID=\$(cat /proc/sys/kernel/random/boot_id); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo F=\$(pgrep -x fesvr-teaching-static | wc -l); echo L=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); echo PSHA=\$(sha256sum /root/xv6run/pipedual.bit.bin | cut -d' ' -f1); echo USERDISK=\$(test -e $USER_DISK && sha256sum $USER_DISK | cut -d' ' -f1 || echo NONE)"
[ "$(field BID)" = "$(cat "$S/boot-id.txt")" ] || die $EX_NOT_COLD "the boot id changed since the install session"
[ "$(field PD)" = 1 ] || die $EX_PROG "prog_done is not 1"; [ "$(field F)" = 0 ] || die $EX_BUSY "a host is running"
[ "$(field L)" = NO_LOCK ] || die $EX_BUSY "the host lock is present"; [ "$(field PSHA)" = "$PAYLOAD_SHA" ] || die $EX_HASH "the payload file on the board is not $PAYLOAD_SHA"
[ "$(field USERDISK)" = NONE ] || die $EX_BUSY "fs-user.img already exists on this boot (sha $(field USERDISK)): not overwriting it"
p4c_no_host "checking for a host by comm scan, pgrep and the lock"
say "== the launcher, the measurement kernel"
deploy_verified "$P4C/xv6-pipe-dual.sh" /root/xv6run/xv6-pipe-dual.sh "$H/deploy.log"
deploy_verified "$ART/kernel-perf-128mib" /root/xv6run/kernel-perf-128mib "$H/deploy.log"
say "== the user's disks, restored from the pre-cycle backups ($BK)"
: > "$H/disks.txt"
for n in $(awk '$1=="BACKUP" && $3 ~ /\.img$/ && $3 != "fs-run.img" {print $3}' "$BK/backup.txt"); do
  deploy_verified "$BK/$n" "/root/xv6run/$n" "$H/deploy.log"
  echo "$n $(sha256sum "$BK/$n" | cut -d' ' -f1) restored from the pre-cycle backup" | tee -a "$H/disks.txt"; done
grep -q '^fs-user.img ' "$H/disks.txt" || { deploy_verified "$ART/fs-perf.img" $USER_DISK "$H/deploy.log"; echo "fs-user.img $(sha256sum "$ART/fs-perf.img" | cut -d' ' -f1) fresh copy of fs-perf.img (no backup existed)" | tee -a "$H/disks.txt"; }
say "== the benchmark disks"
deploy_verified "$ART/fs-perf.img" /root/xv6run/fs-bench-pristine.img "$H/deploy.log"
deploy_verified "$ART/fs-perf.img" /root/xv6run/fs-bench.img "$H/deploy.log"
board_must "making the pristine benchmark disk read-only and the launcher executable" "chmod 444 /root/xv6run/fs-bench-pristine.img && chmod +x /root/xv6run/xv6-pipe-dual.sh && echo MODE=ok"
[ "$(field MODE)" = ok ] || die $EX_HASH "could not set the file modes"
board_must "checking the launcher" "cd /root/xv6run && ./xv6-pipe-dual.sh --check; echo RC=\$?"
printf '%s\n' "$BOARD_OUT" > "$H/launcher-check.txt"; [ "$(field RC)" = 0 ] && grep -q "CHECK OK" "$H/launcher-check.txt" || die $EX_GATE "the launcher check failed"
say "== launch / commands / stop / restart / stop on a THROWAWAY disk copy"
deploy_verified "$ART/fs-perf.img" /root/xv6run/fs-launchtest.img "$H/deploy.log"
set +e; python3 "$P4C/launch-test.py" /root/xv6run/fs-launchtest.img "$H/launch-test.transcript" | tee "$H/launch-test.txt"; lt=${PIPESTATUS[0]}; set -e
# whatever the test said, the throwaway disk is removed and the final state read before any verdict
board_must "removing the throwaway disk and reading the final state" "rm -f /root/xv6run/fs-launchtest.img; echo F=\$(pgrep -x fesvr-teaching-static | wc -l); echo C=\$(cat /proc/[0-9]*/comm 2>/dev/null | grep -cx fesvr-teaching-); echo L=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo BID=\$(cat /proc/sys/kernel/random/boot_id); cd /root/xv6run && ls -la && sha256sum *"
printf '%s\n' "$BOARD_OUT" > "$H/final-state.txt"
[ "$(field F)" = 0 ] && [ "$(field C)" = 0 ] && [ "$(field L)" = NO_LOCK ] || die $EX_BUSY "after the launch test a host or the lock remains: NOT handed over"
[ "$lt" = 0 ] || die $EX_GATE "the launch test failed: NOT handed over (see $H)"
say "P4C_HANDOFF_READY: installed and ready, NOT running (no host, lock free). The user launches with: cd /root/xv6run && ./xv6-pipe-dual.sh"
