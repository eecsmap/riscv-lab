#!/bin/bash
# PIPE-P3b xv6 on the board, same boot as the install session, through the production runner (the accepted isolated
# copy in multicore/perf/tools, reached via ./tools) over the serial console (exclusive channel, the production lock).
#   p3b-xv6.sh <install session> m4smoke      kernel-dual-128mib 33021237…, fresh fs-dual-deploy.img d8e50269…, judge m5_xv6_check.py
#   p3b-xv6.sh <install session> perf-board   kernel-perf-128mib 133f5b72…, fresh fs-perf.img d558e444…, judge perf_check.py (defaults)
# The benchmark disk is /root/xv6run/fs-run.img, a FRESH hash-verified copy for every run; fs-user.img is never used.
set -euo pipefail
cd "$(dirname "$0")"; . ./p3b-lib.sh
S=${1:?install session}; WL=${2:?m4smoke|perf-board}
[ -s "$S/completed.txt" ] && grep -q P3B_INSTALL_DONE "$S/session.log" || die 2 "$S is not a completed install session"
case $WL in m4smoke) K=kernel-dual-128mib; D=fs-dual-deploy.img; JUDGE="python3 $P3B/judge/m5_xv6_check.py";;
            perf-board) K=kernel-perf-128mib; D=fs-perf.img; JUDGE="python3 $P3B/judge/perf_check.py";; *) die 2 "unknown workload $WL";; esac
STAGE=${P3B_STAGE_TIMEOUT:-900}; WALL=${P3B_WALL:-5400}
X=$S/xv6-$WL-$(date -u +%Y%m%dT%H%M%SZ); [ -e "$X" ] && die 2 "$X exists"; mkdir -p "$X"; export E1_LOG=$X/session.log
trap release_owned_leases EXIT
p3b_check_artefacts; claim_leases board serial
KSHA=$(sha256sum "$ART/$K" | cut -d' ' -f1); DSHA=$(sha256sum "$ART/$D" | cut -d' ' -f1); HSHA=$(sha256sum "$ART/fesvr-teaching-static" | cut -d' ' -f1)
board_must "reading the state" "mkdir -p /var/lock; echo BID=\$(cat /proc/sys/kernel/random/boot_id); echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo F=\$(pgrep -x fesvr-teaching-static | wc -l); echo L=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); echo PSHA=\$(sha256sum /root/xv6run/pipe.bit.bin | cut -d' ' -f1)"
[ "$(field BID)" = "$(cat "$S/boot-id.txt")" ] || die $EX_NOT_COLD "the boot id changed since the install session"
[ "$(field PD)" = 1 ] || die $EX_PROG "prog_done is not 1"
[ "$(field F)" = 0 ] || die $EX_BUSY "a host is running"; [ "$(field L)" = NO_LOCK ] || die $EX_BUSY "the host lock is present"
[ "$(field PSHA)" = "$PAYLOAD_SHA" ] || die $EX_HASH "the payload file on the board is not $PAYLOAD_SHA"
say "== deploy the kernel and a FRESH disk copy (hash-verified on the board)"
deploy_verified "$ART/$K" /root/xv6run/$K "$X/deploy.log"; deploy_verified "$ART/$D" $RUN_DISK "$X/deploy.log"
{ echo "config=single pipeline (payload $PAYLOAD_SHA, bit $BIT_SHA) workload=$WL stage_timeout=$STAGE wall=$WALL"; echo "kernel=/root/xv6run/$K ($KSHA)"
  echo "disk=$RUN_DISK ($DSHA, fresh copy of $D)"; echo "host=/root/xv6run/fesvr-teaching-static ($HSHA)"; echo "evidence=$S/memory boot_id=$(cat "$S/boot-id.txt")"; echo "start=$(date -u +%FT%TZ)"; } > "$X/cmd.txt"
s=$(date +%s); set +e
timeout "$WALL" python3 "$P3B/tools/board/scripts/board-runner.py" "$X/run" \
  --transport-cmd "python3 $SHIM --device /dev/ttyUSB1" --channel exclusive --serial-device /dev/ttyUSB1 \
  --host-binary /root/xv6run/fesvr-teaching-static --kernel /root/xv6run/$K --disk $RUN_DISK \
  --evidence-dir "$S/memory" --expect "/root/xv6run/fesvr-teaching-static=$HSHA" --expect "/root/xv6run/$K=$KSHA" --expect "$RUN_DISK=$DSHA" \
  --bitstream-sha "$BIT_SHA" --workload "$WL" --stage-timeout "$STAGE" --startup-timeout "$STAGE" --stop-timeout 120 > "$X/runner.log" 2>&1
rc=$?; set -e; e=$(date +%s)
echo "XV6_RC=$rc wall=$((e-s))s" | tee "$X/verdict.txt"; tail -3 "$X/runner.log" | cut -c1-200
board "echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done); echo FESVR=\$(pgrep -x fesvr-teaching-static | wc -l); echo LOCK=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK); echo BID=\$(cat /proc/sys/kernel/random/boot_id)" || true
printf '%s\n' "$BOARD_OUT" > "$X/post-state.txt"; say "$BOARD_OUT"
$JUDGE "$X" | tee "$X/check.txt"; jr=${PIPESTATUS[0]}
echo "P3B_XV6_DONE workload=$WL rc=$rc judge=$jr dir=$X"; [ $rc = 0 ] && [ $jr = 0 ]
