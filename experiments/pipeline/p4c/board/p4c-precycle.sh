#!/bin/bash
# PIPE-P4c step 0, BEFORE the user cycles power (a copy of P3b's p3b-precycle.sh, plus the stop of a running user
# session and an unconditional backup of every disk image). In order, the first failure stops everything:
#   1. the local frozen artefact set; the board + serial leases (before any transport)
#   2. no process on THIS host holds the board's serial ports (a user's screen/miniterm): if one does, refuse and
#      name it -- it is the user's to release, it is never killed
#   3. console-stop.py: ONE newline; at the ARM prompt nothing is running; at an IDLE xv6 prompt ONE Ctrl-C (the
#      documented stop of xv6-pipe.sh) and the host must exit; anything else (a command running, silence) is left
#      alone and the run refuses. Transcript kept.
#   4. the pre-state, read-only: boot id, uptime, prog_done, host process(es), the lock and its owner, ps, mounts,
#      df, every file in /root/xv6run with its hash (the launcher and the programmed payload file among them)
#   5. BACKUP over the console (gzip | base64, decoded and hash-checked here) of every *.img on the board, known
#      hash or not (each is a user's disk or could be), and of every other file whose hash is not a known accepted
#      artefact. Each run writes a NEW directory; nothing earlier is overwritten.
#   6. whether the board has `timeout`; the pin of the current boot id.
# Nothing is programmed, deleted, copied to the board or started.
set -euo pipefail
cd "$(dirname "$0")"; . ./p4c-lib.sh
O=$STATE/precycle-$(date -u +%Y%m%dT%H%M%SZ); [ -e "$O" ] && die 2 "$O exists"; mkdir -p "$O/backup"; export E1_LOG=$O/precycle.log
trap release_owned_leases EXIT
say "== local artefacts"; p4c_check_artefacts
say "== leases, before any transport"; claim_leases board serial
say "== no process on this host may hold the board's serial ports"
holders=""; for f in /proc/[0-9]*/fd/*; do
  case "$(readlink "$f" 2>/dev/null)" in /dev/ttyUSB0|/dev/ttyUSB1) p=${f#/proc/}; p=${p%%/*}; holders="$holders $p";; esac; done
holders=$(tr ' ' '\n' <<<"$holders" | sort -u | grep . || true)
{ echo "checked=/dev/ttyUSB0 /dev/ttyUSB1 via /proc/*/fd (processes of user $(id -un); others are not visible)"
  for p in $holders; do echo "HOLDER pid=$p cmd=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)"; done; } > "$O/host-serial.txt"
[ -z "$holders" ] || die $EX_BUSY "a process on this host holds the serial console ($(grep HOLDER "$O/host-serial.txt" | tr '\n' ';')): the user must release it; it is not killed"
say "  none"
say "== the console: stop a running user session only the documented way"
set +e; python3 "$P4C/console-stop.py" "$O/console-stop.transcript" --wait 30 | tee "$O/console-stop.txt"; cs=${PIPESTATUS[0]}; set -e
case $cs in 0) ;; 2) die $EX_BUSY "the console is not at a prompt (a command may be running): the USER must bring it to the xv6 or ARM prompt; nothing was sent but one newline";;
  *) die $EX_BUSY "console-stop.py returned $cs: the session did not stop cleanly; see $O/console-stop.transcript";; esac
say "== pre-state (read-only)"
board_must "reading the pre-state" "echo BID=\$(cat /proc/sys/kernel/random/boot_id); echo UP=\$(cut -d. -f1 /proc/uptime); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo FESVR=\$(pgrep -x fesvr-teaching-static | wc -l); echo LOCK=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); echo LOCKOWNER=\$(cat /var/lock/teaching-fesvr.lock/owner 2>/dev/null); echo TOOLS=\$(for t in timeout gzip base64 sha256sum flock; do command -v \$t >/dev/null && printf '%s,' \$t; done); echo DF=\$(df -k /root | tail -1); ps; mount | grep -vE 'proc|sysfs|devpts|tmpfs' ; ls -la /root/xv6run; cd /root/xv6run && { sha256sum * 2>/dev/null; echo LISTED=\$(ls -A | wc -l); }"
printf '%s\n' "$BOARD_OUT" > "$O/pre-state.txt"; say "$(tr -d '\r' < "$O/pre-state.txt" | grep -E '^(BID|UP|PD|FESVR|LOCK|LOCKOWNER|TOOLS|DF)=')"
[ "$(field FESVR)" = 0 ] || die $EX_BUSY "a host is still running on the board after the stop; not touching it further"
[ "$(field LOCK)" = NO_LOCK ] || die $EX_BUSY "the host lock is present (owner '$(field LOCKOWNER)'); it must not be cleared by hand"
say "== backups: every disk image, and every file that is not a known accepted artefact"
KNOWN=$(awk '{print $1}' "$P4C/known-hashes.txt")
tr -d '\r' < "$O/pre-state.txt" | grep -E '^[0-9a-f]{64}  ' | while read -r h n; do
  if [[ $n == *.img ]]; then echo "BACKUP  $h  $n  (disk image)"
  elif grep -qx "$h" <<<"$KNOWN"; then echo "known   $h  $n"
  else echo "BACKUP  $h  $n  (unknown hash)"; fi
done > "$O/backup/backup.txt"
sed 's/^/  /' "$O/backup/backup.txt"
for n in $(awk '$1=="BACKUP"{print $3}' "$O/backup/backup.txt"); do
  h=$(awk -v n="$n" '$1=="BACKUP" && $3==n {print $2}' "$O/backup/backup.txt")
  say "  reading back /root/xv6run/$n (sha ${h:0:16}…) over the console"
  timeout 1800 python3 "$SHIM" "gzip -c /root/xv6run/$n | base64" 2>/dev/null | tr -d '\r\000' | sed -n '/^[A-Za-z0-9+\/=]*$/p' | base64 -d 2>/dev/null | gunzip > "$O/backup/$n" || true
  got=$(sha256sum "$O/backup/$n" | cut -d' ' -f1)
  [ "$got" = "$h" ] || die $EX_HASH "the backup of $n hashes $got, the board says $h: NOT safe to power-cycle yet"
  say "  backed up $n: $got (matches the board)"
done
( cd "$O/backup" && awk '$1=="BACKUP"{print $3}' backup.txt | xargs -r sha256sum ) > "$O/backup/backup.sha256"
say "== re-reading the board's hashes after the backups (nothing may have changed while reading)"
board_must "re-reading the hashes" "echo FESVR=\$(pgrep -x fesvr-teaching-static | wc -l); cd /root/xv6run && { sha256sum * 2>/dev/null; echo LISTED=\$(ls -A | wc -l); }"
printf '%s\n' "$BOARD_OUT" > "$O/post-backup-hashes.txt"
diff <(tr -d '\r' < "$O/pre-state.txt" | grep -E '^[0-9a-f]{64}  ' | sort) <(tr -d '\r' < "$O/post-backup-hashes.txt" | grep -E '^[0-9a-f]{64}  ' | sort) \
  || die $EX_HASH "the files in /root/xv6run changed during the backup"
say "== the board's timeout builtin"
board_must "probing for timeout" "echo TMO=\$(command -v timeout >/dev/null && echo yes || echo no)"
TMO=$(field TMO); printf '%s\n' "${TMO:-unknown}" > "$O/timeout.txt"
case "$TMO" in yes|no) say "  timeout: $TMO" ;; *) die $EX_TRANSPORT "could not determine 'timeout' (got '${TMO:-<none>}')" ;; esac
say "== pinning the current boot id"
board_must "reading the boot id" "cat /proc/sys/kernel/random/boot_id"
bid=$(tr -d '\r' <<<"$BOARD_OUT" | grep -oE '^[0-9a-f-]{36}$' | tail -1 || true)
[ -n "$bid" ] || die $EX_PIN "could not read the current boot id; refusing to pin an empty value"
[ "$bid" = "$(tr -d '\r' < "$O/pre-state.txt" | sed -n 's/^BID=//p' | tail -1)" ] || die $EX_PIN "the boot id changed during the pre-cycle step"
printf '%s\n' "$bid" > "$O/pin.txt"; ln -sfn "$(basename "$O")" "$STATE/current-precycle"
say "pinned pre-cycle boot id: $bid ($O/pin.txt; $STATE/current-precycle -> $(basename "$O"))"
say "P4C_READY_FOR_COLD_CYCLE precycle=$O"
