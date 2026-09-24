#!/usr/bin/env bash
# E1 install: DEPLOY-AND-RESTORE.md steps 1-7.
#
# Failure propagation is explicit at every safety boundary. No gate result comes back through $( ) --
# `die` inside a command substitution exits only the subshell, and the parent used to carry on and
# program the FPGA. No retry, no recovery, no hot reload.
set -euo pipefail
cd "$(dirname "$0")"; . ./lib-e1.sh; . ./artefacts.sh
O=${E1_OUT:-$R/riscv-lab/experiments/E1-clock-scaling}
S=$O/session-install-$(date -u +%Y%m%dT%H%M%SZ); mkdir -p "$S/gates" "$S/samples" "$S/memory"
export E1_LOG=$S/session.log
trap release_owned_leases EXIT

say "=== E1 install, session $S"

apply_recorded_timeout "$O/state/install-timeout.txt"

say "== leases, before any transport"
claim_leases board serial

say "== step 1: the cold cycle"
verify_power_record "$O/state/install-power.txt" "$O/state/install-pin.txt"
verify_cold_cycle "$O/state/install-pin.txt" "$S/boot-id.txt" 600
NEWBID=$(cat "$S/boot-id.txt")

say "== step 2: this boot's memory evidence, then the production preflight"
capture_memory_evidence "$S/memory" "$NEWBID"
run_mem_preflight "$S/memory" "$NEWBID" "$S/mem-preflight.json"

say "== step 3: deploy, each artefact hash-verified on the board by the upload path"
deploy_verified "$E1_PAYLOAD" /root/xv6run/e1-25mhz.bit.bin "$S/deploy.log"
deploy_verified "$HOSTBIN"    /root/xv6run/fesvr-teaching-static "$S/deploy.log"
for f in $GATES $PERF_PROBES; do
  deploy_verified "$(elf_path "$f")" "/root/xv6run/$f.elf" "$S/deploy.log"
done
make_executable "/root/xv6run/*.elf /root/xv6run/fesvr-teaching-static"

say "== step 4: program from the cold, quiescent platform"
program_payload /root/xv6run/e1-25mhz.bit.bin

say "== step 5: the eight startup gates (exact marker AND confirmed exit; a failure STOPS the session)"
run_startup_gates "$S/gates" 120
record_adapter_status "$S/gates/boot01_marker.out" "$S/adapter-status.txt"

say "== step 6: perf03 and perf04, 5 samples each, validated by the production probe parser"
run_perf_samples "$S/samples" 5 120

say "== step 7: state and health"
board_must "reading the final state" "echo BOOTID=\$(cat /proc/sys/kernel/random/boot_id); echo UP=\$(cut -d. -f1 /proc/uptime); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo LOAD=\$(cut -d' ' -f1-3 /proc/loadavg); dmesg | tail -5"
printf '%s\n' "$BOARD_OUT" > "$S/final-state.txt"
say "E1_INSTALL_DONE  session=$S"
say "The board now holds the E1 25 MHz bitstream. Restore is REQUIRED:"
say "  ./e1-precycle.sh restore ; user power-cycles ; ./e1-record-power-cycle.sh restore ; ./e1-restore.sh"
