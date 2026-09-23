#!/usr/bin/env bash
# E1 restore: DEPLOY-AND-RESTORE.md steps 8-12. Required, and not authority for unsafe recovery.
set -u
cd "$(dirname "$0")"; . ./lib-e1.sh; . ./artefacts.sh
O=$R/riscv-lab/experiments/E1-clock-scaling
S=$O/session-restore-$(date -u +%Y%m%dT%H%M%SZ); mkdir -p $S/gates
export E1_LOG=$S/session.log

say "=== E1 restore, session $S"
say "== step 8: the second cold cycle"
NEWBID=$(verify_cold_cycle $O/state/restore-pin.txt 600)
printf '%s\n' "$NEWBID" > $S/boot-id.txt

(cd $R && ./coord claim board && ./coord claim serial) >/dev/null 2>&1

say "== step 9: deploy and verify the ACCEPTED payload"
python3 $SEND $ACCEPTED_PAYLOAD /root/xv6run/teaching.bit.bin --log $S/deploy.log || die $EX_HASH "deploy failed"
for f in $GATES; do
  python3 $SEND "$(elf_path $f)" /root/xv6run/$f.elf --log $S/deploy.log || die $EX_HASH "deploy of $f.elf failed"
done
python3 $SEND $HOSTBIN /root/xv6run/fesvr-teaching-static --log $S/deploy.log \
  || die $EX_HASH "deploy of the host binary failed"
verify_on_board /root/xv6run/teaching.bit.bin $ACCEPTED_PAYLOAD_SHA

say "== step 10: program the accepted bitstream"
program_payload /root/xv6run/teaching.bit.bin

say "== step 11: the eight gates again. The session is not closed until they pass"
run_startup_gates $S/gates 120
record_adapter_status $S/gates/boot01_marker.out $S/adapter-status.txt

say "== step 12: final state, then release"
board "echo BOOTID=\$(cat /proc/sys/kernel/random/boot_id); echo UP=\$(cut -d. -f1 /proc/uptime); echo PROG_DONE=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo FESVR_N=\$(pgrep -x fesvr-teaching-static | wc -l); echo LOCK=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); sha256sum /root/xv6run/teaching.bit.bin" > $S/final-state.txt
(cd $R && ./coord release serial && ./coord release board) >/dev/null 2>&1
say "E1_RESTORE_DONE  session=$S"
say "The board holds the ACCEPTED 40 MHz bitstream again, with 8/8 gates re-verified."
