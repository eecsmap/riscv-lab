#!/bin/bash
# PIPE-P4c install on a COLD boot (copy of P3b's p3b-install.sh for the two-hart image): cold-cycle gates -> memory
# evidence + production preflight -> hash-verified deploy -> program + status + prog_done + payload re-hash -> the six
# dual-hart startup gates (exact marker AND RC=0) -> the frequency reference (two-hart freq_spin_dual, timed by the
# PS clock, 3 pairs) -> final state. The first failure stops the session; nothing is retried, nothing re-programmed.
set -euo pipefail
cd "$(dirname "$0")"; . ./p4c-lib.sh
O=$(readlink -f "$STATE/current-precycle")
S=${P4C_SESSION:-$WS/sessions/session-pipedual-$(date -u +%Y%m%dT%H%M%SZ)}
[ -e "$S" ] && die 2 "$S exists"; mkdir -p "$S/gates" "$S/memory" "$S/freq"; export E1_LOG=$S/session.log
trap release_owned_leases EXIT
printf 'pipedual\n' > "$S/variant.txt"; printf '%s\n' "$O" > "$S/precycle.txt"
printf '{ "variant": "pipedual", "payload_sha256": "%s", "bit_sha256": "%s", "expected_gates": %s, "gates": "%s", "started_utc": "%s" }\n' \
  "$PAYLOAD_SHA" "$BIT_SHA" "$GATE_COUNT" "$GATES" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$S/intent.json"
say "=== PIPE-P4c dual-pipeline board session, $S (pre-cycle step $O)"
p4c_check_artefacts; apply_recorded_timeout "$O/timeout.txt"
say "== leases, before any transport"; claim_leases board serial
say "== step 1: the cold cycle"
verify_power_record "$O/power.txt" "$O/pin.txt"
verify_cold_cycle   "$O/pin.txt" "$S/boot-id.txt" 600
NEWBID=$(cat "$S/boot-id.txt")
p4c_no_host "checking for a host by comm scan, pgrep and the lock"
say "== step 2: this boot's memory evidence, then the production preflight"
capture_memory_evidence "$S/memory" "$NEWBID"; run_mem_preflight "$S/memory" "$NEWBID" "$S/mem-preflight.json"
say "== step 3: deploy, each artefact hash-verified on the board"; p4c_deploy_install "$S"
say "== step 4: program from the cold, quiescent platform"
p4c_no_host "checking again for a host before programming"
board_must "reading prog_done before programming" "echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done)"
printf 'prog_done_before=%s\n' "$(field PD)" > "$S/program.txt"
program_payload /root/xv6run/pipedual.bit.bin
board_must "re-reading the programmed payload's hash on the board" "echo PSHA=\$(sha256sum /root/xv6run/pipedual.bit.bin | cut -d' ' -f1); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done)"
printf 'prog_rc=0\nprog_done_after=%s\npayload_on_board=%s\npayload_expected=%s\nbit=%s\n' "$(field PD)" "$(field PSHA)" "$PAYLOAD_SHA" "$BIT_SHA" >> "$S/program.txt"
[ "$(field PSHA)" = "$PAYLOAD_SHA" ] || die $EX_HASH "the payload on the board hashes $(field PSHA) after programming, not $PAYLOAD_SHA"
say "  the payload on the board still hashes ${PAYLOAD_SHA:0:16}… after programming"
say "== step 5: the $GATE_COUNT dual-hart startup gates (exact marker AND RC=0)"
run_startup_gates "$S/gates" 120
say "== step 6: the frequency reference: short and long two-hart spins timed by the PS's own clock (/proc/uptime), 3 pairs"
for i in 1 2 3; do for v in freq_spin_short freq_spin_long; do
  board_must "timing $v #$i" "cd /root/xv6run && a=\$(cut -d' ' -f1 /proc/uptime); ${E1_TIMEOUT}120 ./fesvr-teaching-static ./$v.elf 2>&1; r=\$?; b=\$(cut -d' ' -f1 /proc/uptime); echo RC=\$r; echo T0=\$a; echo T1=\$b"
  printf '%s\n' "$BOARD_OUT" > "$S/freq/$v.$i.out"
  [ "$(field RC)" = 0 ] && grep -q TEACHING-FREQ-SPIN-OK "$S/freq/$v.$i.out" || die $EX_GATE "$v #$i did not complete (RC=$(field RC))"
  say "  $v #$i: T0=$(field T0) T1=$(field T1) $(tr -d '\r' < "$S/freq/$v.$i.out" | grep -o 'FREQ-SPIN.*' | head -1)"
done; done
set +e; python3 "$P4C/freq_judge.py" "$S/freq" | tee "$S/freq/result.txt"; fj=${PIPESTATUS[0]}; set -e; [ "$fj" = 0 ] || die $EX_GATE "the frequency judge refused (see $S/freq/result.txt)"
say "== step 6b: can the board SEE a running host? (every 'no host running' guard depends on it)"
# The host's kernel name is 15 characters, "fesvr-teaching-"; whether this board's `pgrep -x fesvr-teaching-static`
# (used by the accepted library's guards) matches it is not known offline (procps' pgrep cannot). One bounded run of
# the already-timed freq_spin_long in the background; both methods are read while it runs, then its exit is awaited.
board_must "host detection probe" "cd /root/xv6run && (./fesvr-teaching-static ./freq_spin_long.elf > /tmp/p4c-hostprobe.out 2>&1 &); sleep 3; echo PGX=\$(pgrep -x fesvr-teaching-static | wc -l); echo COMM=\$(cat /proc/[0-9]*/comm 2>/dev/null | grep -cx fesvr-teaching-); echo PIDOF=\$(pidof fesvr-teaching-static | wc -w); i=0; while [ \$i -lt 90 ] && [ \$(cat /proc/[0-9]*/comm 2>/dev/null | grep -cx fesvr-teaching-) != 0 ]; do sleep 1; i=\$((i+1)); done; echo AFTER=\$(cat /proc/[0-9]*/comm 2>/dev/null | grep -cx fesvr-teaching-); echo WAITED=\$i; grep -c TEACHING-FREQ-SPIN-OK /tmp/p4c-hostprobe.out; rm -f /tmp/p4c-hostprobe.out"
printf '%s\n' "$BOARD_OUT" > "$S/host-detection.txt"
say "  while a host ran: pgrep -x=$(field PGX) comm-scan=$(field COMM) pidof=$(field PIDOF); after: comm-scan=$(field AFTER) (waited $(field WAITED) s)"
[ "$(field AFTER)" = 0 ] || die $EX_BUSY "the probe's host did not exit within 90 s"
[ "$(field COMM)" = 1 ] || die $EX_GATE "the comm scan did not see the running host (got '$(field COMM)'): the launcher's guard would be blind"
[ "$(field PGX)" = 1 ] || say "  NOTE: pgrep -x does NOT see a running host on this board: the accepted library's 'no host' checks are blind (reported, not changed here); the lock is the effective guard"
say "== step 7: state and health"
board_must "reading the final state" "echo BOOTID=\$(cat /proc/sys/kernel/random/boot_id); echo UP=\$(cut -d. -f1 /proc/uptime); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo FESVR=\$(pgrep -x fesvr-teaching-static | wc -l); echo COMMHOSTS=\$(cat /proc/[0-9]*/comm 2>/dev/null | grep -cx fesvr-teaching-); echo LOCK=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); echo LOAD=\$(cut -d' ' -f1-3 /proc/loadavg); cd /root/xv6run && sha256sum *; dmesg | tail -5"
printf '%s\n' "$BOARD_OUT" > "$S/final-state.txt"
printf 'variant=pipedual\ncompleted_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$S/completed.txt"
say "P4C_INSTALL_DONE session=$S"
say "The board holds the dual-pipeline bitstream (payload ${PAYLOAD_SHA:0:16}…). Next: ./p4c-xv6.sh $S m4smoke ; ./p4c-xv6.sh $S perf-board ; ./p4c-interactive.sh $S"
