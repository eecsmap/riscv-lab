#!/usr/bin/env bash
# E1 install: DEPLOY-AND-RESTORE.md steps 1-7. Requires a verified cold cycle, pinned by e1-precycle.sh.
#
# No retry, no recovery, no hot reload. Any gate that refuses ends the session with the board's actual
# state reported as it is.
set -u
cd "$(dirname "$0")"; . ./lib-e1.sh; . ./artefacts.sh
O=$R/riscv-lab/experiments/E1-clock-scaling
S=$O/session-install-$(date -u +%Y%m%dT%H%M%SZ); mkdir -p $S/gates $S/samples
export E1_LOG=$S/session.log

say "=== E1 install, session $S"

say "== step 1: the cold cycle"
NEWBID=$(verify_cold_cycle $O/state/install-pin.txt 600)
printf '%s\n' "$NEWBID" > $S/boot-id.txt

say "== step 2: leases and preflight"
(cd $R && ./coord claim board && ./coord claim serial) >/dev/null 2>&1
python3 $R/riscv-lab/tools/board/scripts/mem-preflight.py --evidence-dir $S/memory 2>&1 | tee -a $E1_LOG | tail -3
grep -q "MEM_PREFLIGHT OK" $E1_LOG || die $EX_BUSY "the memory preflight did not pass on this boot"

say "== step 3: deploy E1 payload and the eight probes, then verify on the board"
[ -f "$E1_PAYLOAD" ] || die $EX_HASH "$E1_PAYLOAD is missing locally"
python3 $SEND $E1_PAYLOAD /root/xv6run/e1-25mhz.bit.bin --log $S/deploy.log || die $EX_HASH "deploy failed"
for f in $GATES; do
  python3 $SEND "$(elf_path $f)" /root/xv6run/$f.elf --log $S/deploy.log || die $EX_HASH "deploy of $f.elf failed"
done
for f in $PERF_PROBES; do
  python3 $SEND "$(elf_path $f)" /root/xv6run/$f.elf --log $S/deploy.log || die $EX_HASH "deploy of $f.elf failed"
done
python3 $SEND $HOSTBIN /root/xv6run/fesvr-teaching-static --log $S/deploy.log \
  || die $EX_HASH "deploy of the host binary failed"
verify_on_board /root/xv6run/e1-25mhz.bit.bin $E1_PAYLOAD_SHA

say "== step 4: program from the cold, quiescent platform"
program_payload /root/xv6run/e1-25mhz.bit.bin

say "== step 5: the eight startup gates (a failure STOPS the session)"
run_startup_gates $S/gates 120
record_adapter_status $S/gates/boot01_marker.out $S/adapter-status.txt

say "== step 6: perf03 and perf04, 5 bounded samples each"
for probe in $PERF_PROBES; do
  ok=0
  for n in 1 2 3 4 5; do
    out=$(board "cd /root/xv6run && $E1_TIMEOUT""120 ./fesvr-teaching-static ./$probe.elf 2>&1; echo RC=\$?")
    printf '%s\n' "$out" > $S/samples/$probe.$n.out
    rc=$(sed -n 's/^RC=//p' <<<"$out" | tail -1)
    if [ "${rc:-1}" = "0" ]; then ok=$((ok+1)); say "  $probe sample $n: ok"; else say "  $probe sample $n: FAILED rc=${rc:-<none>} (recorded, not retried)"; fi
  done
  [ "$ok" -ge 5 ] || die $EX_SAMPLES "$probe produced $ok/5 usable samples; the policy is 5 and samples are not re-run on failure"
done

say "== step 7: state and health"
board "echo BOOTID=\$(cat /proc/sys/kernel/random/boot_id); echo UP=\$(cut -d. -f1 /proc/uptime); echo PROG_DONE=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo LOAD=\$(cut -d' ' -f1-3 /proc/loadavg); dmesg | tail -5" > $S/final-state.txt
say "E1_INSTALL_DONE  session=$S"
say "The board now holds the E1 25 MHz bitstream. Restore is REQUIRED: run e1-precycle.sh restore,"
say "have the user power-cycle again, then e1-restore.sh."
