#!/bin/bash
# PIPE-P3b step 0, BEFORE the user cycles power. Read-only on the board except for the timeout probe's echo:
# checks the local artefacts, claims the leases, records the pre-state (boot id, uptime, PL state, host/lock,
# every file in /root/xv6run with its hash, mounts, tools), BACKS UP any file in /root/xv6run whose hash is not a
# known accepted artefact (the user's working disk in particular: the root is a RAM initramfs, a power cycle loses
# it) by reading it back over the console (gzip | base64, decoded and hash-checked here), records whether the board
# has `timeout`, and pins the current boot id. Nothing is programmed, deleted or started.
set -euo pipefail
cd "$(dirname "$0")"; . ./p3b-lib.sh
O=${P3B_OUT:-$P3B/state}; mkdir -p "$O"; PIN=$O/pipe-pin.txt
trap release_owned_leases EXIT
say "== local artefacts"; p3b_check_artefacts
say "== leases, before any transport"; claim_leases board serial
say "== pre-state (read-only)"
board_must "reading the pre-state" "echo BID=\$(cat /proc/sys/kernel/random/boot_id); echo UP=\$(cut -d. -f1 /proc/uptime); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo FESVR=\$(pgrep -x fesvr-teaching-static | wc -l); echo LOCK=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); echo TOOLS=\$(for t in timeout gzip base64 sha256sum flock; do command -v \$t >/dev/null && printf '%s,' \$t; done); echo DF=\$(df -k /root | tail -1); mount | grep -vE 'proc|sysfs|devpts|tmpfs' ; ls -la /root/xv6run; cd /root/xv6run && sha256sum * 2>/dev/null"
printf '%s\n' "$BOARD_OUT" > "$O/pre-state.txt"; say "$(tr -d '\r' < "$O/pre-state.txt" | grep -E '^(BID|UP|PD|FESVR|LOCK|TOOLS|DF)=')"
[ "$(field FESVR)" = 0 ] || die $EX_BUSY "a host is running on the board; the user's session must be ended first"
[ "$(field LOCK)" = NO_LOCK ] || die $EX_BUSY "the host lock is present; it must not be cleared by hand"
say "== files in /root/xv6run that are not a known accepted artefact are backed up before the power cycle"
KNOWN=$(cat "$P3B/known-hashes.txt" | awk '{print $1}')
mkdir -p "$O/backup"; : > "$O/backup/backup.txt"
tr -d '\r' < "$O/pre-state.txt" | grep -E '^[0-9a-f]{64}  ' | while read -r h n; do
  if grep -qx "$h" <<<"$KNOWN"; then echo "known   $h  $n" >> "$O/backup/backup.txt"
  else echo "BACKUP  $h  $n" >> "$O/backup/backup.txt"; fi
done
sed 's/^/  /' "$O/backup/backup.txt"
for n in $(awk '$1=="BACKUP"{print $3}' "$O/backup/backup.txt"); do
  h=$(awk -v n="$n" '$1=="BACKUP" && $3==n {print $2}' "$O/backup/backup.txt")
  say "  reading back /root/xv6run/$n (sha ${h:0:16}…) over the console"
  timeout 1800 python3 "$SHIM" "gzip -c /root/xv6run/$n | base64" 2>/dev/null | tr -d '\r\000' | sed -n '/^[A-Za-z0-9+\/=]*$/p' | base64 -d 2>/dev/null | gunzip > "$O/backup/$n" || true
  got=$(sha256sum "$O/backup/$n" | cut -d' ' -f1)
  [ "$got" = "$h" ] || die $EX_HASH "the backup of $n hashes $got, the board says $h: NOT safe to power-cycle yet"
  say "  backed up $n: $got (matches the board)"
done
say "== the board's timeout builtin"
board_must "probing for timeout" "echo TMO=\$(command -v timeout >/dev/null && echo yes || echo no)"
TMO=$(field TMO); printf '%s\n' "${TMO:-unknown}" > "$O/pipe-timeout.txt"
case "$TMO" in yes|no) say "  timeout: $TMO" ;; *) die $EX_TRANSPORT "could not determine 'timeout' (got '${TMO:-<none>}')" ;; esac
say "== pinning the current boot id"
board_must "reading the boot id" "cat /proc/sys/kernel/random/boot_id"
bid=$(tr -d '\r' <<<"$BOARD_OUT" | grep -oE '^[0-9a-f-]{36}$' | tail -1 || true)
[ -n "$bid" ] || die $EX_PIN "could not read the current boot id; refusing to pin an empty value"
printf '%s\n' "$bid" > "$PIN"; say "pinned pre-cycle boot id: $bid"
say "READY-FOR-COLD-CYCLE: the user removes power, restores it, then ./p3b-record-power-cycle.sh ; then ./p3b-install.sh"
