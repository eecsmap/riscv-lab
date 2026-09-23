#!/usr/bin/env bash
# E1 restore: DEPLOY-AND-RESTORE.md steps 8-12. Required, and not authority for unsafe recovery.
#
# Reached whether the measurement succeeded or failed: a shortfall means the measurement failed, not
# that restoration is abandoned.
set -euo pipefail
cd "$(dirname "$0")"; . ./lib-e1.sh; . ./artefacts.sh
O=${E1_OUT:-$R/riscv-lab/experiments/E1-clock-scaling}
S=$O/session-restore-$(date -u +%Y%m%dT%H%M%SZ); mkdir -p "$S/gates" "$S/memory"
export E1_LOG=$S/session.log
trap release_owned_leases EXIT

say "=== E1 restore, session $S"

say "== leases, before any transport"
claim_leases board serial

say "== step 8: the second cold cycle"
verify_power_record "$O/state/restore-power.txt" "$O/state/restore-pin.txt"
verify_cold_cycle "$O/state/restore-pin.txt" "$S/boot-id.txt" 600
NEWBID=$(cat "$S/boot-id.txt")

say "== the same evidence chain as install"
capture_memory_evidence "$S/memory" "$NEWBID"
run_mem_preflight "$S/memory" "$NEWBID" "$S/mem-preflight.json"

say "== step 9: deploy and verify the ACCEPTED payload"
deploy_verified "$ACCEPTED_PAYLOAD" /root/xv6run/teaching.bit.bin "$S/deploy.log"
deploy_verified "$HOSTBIN"          /root/xv6run/fesvr-teaching-static "$S/deploy.log"
for f in $GATES; do
  deploy_verified "$(elf_path "$f")" "/root/xv6run/$f.elf" "$S/deploy.log"
done
make_executable "/root/xv6run/*.elf /root/xv6run/fesvr-teaching-static"

say "== step 10: program the accepted bitstream"
program_payload /root/xv6run/teaching.bit.bin

say "== step 11: the eight gates again. The session is not closed until they pass"
run_startup_gates "$S/gates" 120
record_adapter_status "$S/gates/boot01_marker.out" "$S/adapter-status.txt"

say "== step 12: final state, then release"
board_must "reading the final state" "echo BOOTID=\$(cat /proc/sys/kernel/random/boot_id); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo FESVR_N=\$(pgrep -x fesvr-teaching-static | wc -l); echo LOCK=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); sha256sum /root/xv6run/teaching.bit.bin"
printf '%s\n' "$BOARD_OUT" > "$S/final-state.txt"
say "E1_RESTORE_DONE  session=$S"
say "The board holds the ACCEPTED 40 MHz bitstream again, with 8/8 gates re-verified."
