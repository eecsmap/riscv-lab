#!/bin/bash
# PIPE-P3b install on a COLD boot: cold-cycle gates -> memory evidence + production preflight -> hash-verified deploy
# -> program + prog_done + payload re-hash -> the 8 single-hart startup gates -> the 4 perf probes (>= 3 samples) ->
# the frequency reference (PS clock) -> final state. The first failure stops the session; nothing is retried.
set -euo pipefail
cd "$(dirname "$0")"; . ./p3b-lib.sh
O=${P3B_OUT:-$P3B/state}
S=${P3B_SESSION:-$P3B/sessions/session-pipe-$(date -u +%Y%m%dT%H%M%SZ)}
[ -e "$S" ] && die 2 "$S exists"; mkdir -p "$S/gates" "$S/samples" "$S/memory" "$S/freq"; export E1_LOG=$S/session.log
trap release_owned_leases EXIT
printf 'pipe\n' > "$S/variant.txt"
printf '{ "variant": "pipe", "payload_sha256": "%s", "bit_sha256": "%s", "expected_gates": 8, "expected_probes": ["perf02_sv39","perf03_fetch","perf04_where","perf06_iws"], "min_samples": %s, "started_utc": "%s" }\n' \
  "$PAYLOAD_SHA" "$BIT_SHA" "$P3B_MIN_SAMPLES" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$S/intent.json"
say "=== PIPE-P3b single-pipeline board session, $S"
p3b_check_artefacts; apply_recorded_timeout "$O/pipe-timeout.txt"
say "== leases, before any transport"; claim_leases board serial
say "== step 1: the cold cycle"
verify_power_record "$O/pipe-power.txt" "$O/pipe-pin.txt"
verify_cold_cycle   "$O/pipe-pin.txt" "$S/boot-id.txt" 600
NEWBID=$(cat "$S/boot-id.txt")
say "== step 2: this boot's memory evidence, then the production preflight"
capture_memory_evidence "$S/memory" "$NEWBID"; run_mem_preflight "$S/memory" "$NEWBID" "$S/mem-preflight.json"
say "== step 3: deploy, each artefact hash-verified on the board"; p3b_deploy_install "$S"
say "== step 4: program from the cold, quiescent platform"
program_payload /root/xv6run/pipe.bit.bin
board_must "re-reading the programmed payload's hash on the board" "echo PSHA=\$(sha256sum /root/xv6run/pipe.bit.bin | cut -d' ' -f1)"
[ "$(field PSHA)" = "$PAYLOAD_SHA" ] || die $EX_HASH "the payload on the board hashes $(field PSHA) after programming, not $PAYLOAD_SHA"
say "  the payload on the board still hashes ${PAYLOAD_SHA:0:16}… after programming"
say "== step 5: the eight single-hart startup gates (exact marker AND RC=0)"
run_startup_gates "$S/gates" 120
record_adapter_status "$S/gates/boot01_marker.out" "$S/adapter-status.txt"
say "== step 6: perf02 / perf03 / perf04 / perf06, >= $P3B_MIN_SAMPLES valid samples each"
run_perf_samples "$S/samples" "$P3B_MIN_SAMPLES" 120
say "== step 7: the frequency reference: short and long spins timed by the PS's own clock (/proc/uptime), 3 pairs"
for i in 1 2 3; do for v in freq_spin_short freq_spin_long; do
  board_must "timing $v #$i" "cd /root/xv6run && a=\$(cut -d' ' -f1 /proc/uptime); ${E1_TIMEOUT}120 ./fesvr-teaching-static ./$v.elf 2>&1; r=\$?; b=\$(cut -d' ' -f1 /proc/uptime); echo RC=\$r; echo T0=\$a; echo T1=\$b"
  printf '%s\n' "$BOARD_OUT" > "$S/freq/$v.$i.out"
  [ "$(field RC)" = 0 ] && grep -q TEACHING-FREQ-SPIN-OK "$S/freq/$v.$i.out" || die $EX_GATE "$v #$i did not complete (RC=$(field RC))"
  say "  $v #$i: T0=$(field T0) T1=$(field T1) $(tr -d '\r' < "$S/freq/$v.$i.out" | grep -o 'FREQ-SPIN.*' | head -1)"
done; done
python3 "$P3B/freq_judge.py" "$S/freq" | tee "$S/freq/result.txt"
say "== step 8: state and health"
board_must "reading the final state" "echo BOOTID=\$(cat /proc/sys/kernel/random/boot_id); echo UP=\$(cut -d. -f1 /proc/uptime); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo FESVR=\$(pgrep -x fesvr-teaching-static | wc -l); echo LOCK=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); echo LOAD=\$(cut -d' ' -f1-3 /proc/loadavg); cd /root/xv6run && sha256sum *; dmesg | tail -5"
printf '%s\n' "$BOARD_OUT" > "$S/final-state.txt"
printf 'variant=pipe\ncompleted_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$S/completed.txt"
say "P3B_INSTALL_DONE session=$S"
say "The board holds the single-pipeline bitstream (payload ${PAYLOAD_SHA:0:16}…). Next: ./p3b-xv6.sh $S m4smoke ; ./p3b-xv6.sh $S perf-board ; ./p3b-interactive.sh $S"
