#!/usr/bin/env bash
# A scripted stand-in for the serial shim, for the rehearsal only. It answers the same queries the real
# board answers, from a scenario in $FAKE. It never touches a device.
set -u
CMD="$1"
: "${FAKE:=happy}"
: "${FAKE_BID:=11111111-2222-3333-4444-555555555555}"
: "${FAKE_UP:=42}"
: "${FAKE_N:=0}"
: "${FAKE_F:=0}"
: "${FAKE_L:=NO_LOCK}"
: "${FAKE_SHA:=6b5da7e786186bac97bd2156a720f4be78e4bf8e7e396bae61351ae9361c3acb}"
: "${FAKE_PROGDONE:=1}"
: "${FAKE_GATE_FAIL:=}"
: "${FAKE_TMO:=yes}"

# The real shim ECHOES the command before its output. Reproducing that here is the point: a parse that
# matches the echo instead of the answer is the defect this fakes into existence.
# The real shim's echo is WRAPPED by the terminal at the console width -- the run-2 logs show commands
# broken mid-word across lines. If a wrap lands just after "echo ", the next line BEGINS with "BID=",
# which an anchored first-match parse would read as the answer. FAKE_WRAP fakes exactly that.
if [ "${FAKE_WRAP:-0}" = 1 ]; then
    printf 'echo \n'
    printf 'BID=%s\n' "${FAKE_DECOY:-dddddddd-dddd-dddd-dddd-dddddddddddd}"
    printf 'UP=999999\nN=99\nF=1\nL=PRESENT\n'
else
    printf '%s\n' "$CMD"
fi

case "$CMD" in
  *BID=*)
      if [ "$FAKE" = unreadable ]; then echo "cat: can't open"; else
        echo "BID=$FAKE_BID"; echo "UP=$FAKE_UP"; echo "N=$FAKE_N"; echo "F=$FAKE_F"; echo "L=$FAKE_L"
      fi ;;
  *TMO=*)
      echo "TMO=$FAKE_TMO" ;;
  *boot_id*)
      if [ "$FAKE" = unreadable ]; then echo "cat: can't open"; else echo "$FAKE_BID"; fi ;;
  *sha256sum*)
      echo "$FAKE_SHA  /root/xv6run/whatever" ;;
  *xdevcfg*)
      : ;;                                   # programming produces no output
  *prog_done*)
      echo "$FAKE_PROGDONE" ;;
  *fesvr-teaching-static*)
      probe=$(sed -n 's|.*\./\([a-z0-9_]*\)\.elf.*|\1|p' <<<"$CMD")
      echo "teaching: ready after 50 ms; status=0x00131811 cpu_restart_safe=1 pl_reconfig_safe=0 boot_ready=1"
      if [ "$probe" = "$FAKE_GATE_FAIL" ]; then echo "PROBE-FAILED"; echo "RC=1"; else echo "TEACHING-OK"; echo "RC=0"; fi ;;
  *) echo "(fake: unhandled) $CMD" ;;
esac
