#!/usr/bin/env bash
# A recording stand-in for the serial shim. Every command it is asked to run is APPENDED to $E1_REC
# before anything is answered, so a test can assert what the entrypoint did -- and, more to the point,
# what it did NOT do after a refusal.
set -u
CMD="$1"
printf '%s\n' "BOARD $CMD" >> "${E1_REC:?E1_REC must be set}"
: "${FAKE_BID:=11111111-2222-3333-4444-555555555555}"
: "${FAKE_UP:=42}" ; : "${FAKE_N:=0}" ; : "${FAKE_F:=0}" ; : "${FAKE_L:=NO_LOCK}"
: "${FAKE_PROGRC:=0}" ; FAKE_PROGDONE=${FAKE_PROGDONE-1} ; : "${FAKE_GATE_FAIL:=}"
: "${FAKE_TRANSPORT_FAIL:=}" ; : "${FAKE_MARKER_MISSING:=}" ; : "${FAKE_SAMPLE_BAD:=}"
: "${FAKE_TMO:=yes}"

# The real shim echoes the command and the terminal WRAPS that echo; the run-2 logs show commands
# broken mid-word. If a wrap lands just after "echo ", the next line BEGINS with "BID=", which an
# anchored first-match parse would read as the answer. FAKE_WRAP fakes exactly that.
if [ "${FAKE_WRAP:-0}" = 1 ]; then
    printf 'echo \n'
    printf 'BID=%s\n' "${FAKE_DECOY:-dddddddd-dddd-dddd-dddd-dddddddddddd}"
    printf 'UP=999999\nN=99\nF=1\nL=PRESENT\n'
else
    printf '%s\n' "$CMD"
fi
[ -n "$FAKE_TRANSPORT_FAIL" ] && case "$CMD" in *"$FAKE_TRANSPORT_FAIL"*) echo "transport error"; exit 9 ;; esac

marker_of() { awk -v p="$1" '$1==p {print $2}' "$(dirname "$0")/../markers.tsv"; }

case "$CMD" in
  *BID=*)   echo "BID=$FAKE_BID"; echo "UP=$FAKE_UP"; echo "N=$FAKE_N"; echo "F=$FAKE_F"; echo "L=$FAKE_L" ;;
  *TMO=*)   echo "TMO=$FAKE_TMO" ;;
  *MODE=*)  echo "MODE=ok" ;;
  *PROG_RC=*) echo "PROG_RC=$FAKE_PROGRC" ;;
  *PD=*)    echo "PD=$FAKE_PROGDONE"; echo "BOOTID=$FAKE_BID"; echo "UP=$FAKE_UP"; echo "LOAD=0.0 0.0 0.0"; echo "FESVR_N=0"; echo "LOCK=NO_LOCK" ;;
  *__E1B__*)                                   # evidence capture
      echo "__E1B__"
      case "$CMD" in
        *boot_id*)        echo "$FAKE_BID" ;;
        *proc/iomem*)     echo "10000000-1fffffff : teaching-target" ;;
        *meminfo*)        echo "MemTotal:  262144 kB" ;;
        *address-cells*)  echo " 00 00 00 01" ;;
        *size-cells*)     echo " 00 00 00 01" ;;
        *memory/reg*)     echo " 00 00 00 00 10 00 00 00" ;;
        *reserved-memory*) : ;;
      esac
      echo "__E1E__" ;;
  *.elf*)
      probe=$(sed -n 's|.*\./\([a-z0-9_]*\)\.elf.*|\1|p' <<<"$CMD")
      echo "teaching: ready after 50 ms; status=0x00131811 cpu_restart_safe=1 pl_reconfig_safe=0 boot_ready=1"
      case "$probe" in perf03_fetch)
          echo "FETCH-CYC-32BIT=000000000012770a"; echo "FETCH-INS-32BIT=0000000000007532"
          echo "FETCH-CYC-COMPRESSED=000000000009e8d9"; echo "FETCH-INS-COMPRESSED=0000000000007532" ;;
        perf04_where)
          echo "WHERE-CYC-CLINT=00000000001397c2"; echo "WHERE-INS-CLINT=0000000000007532"
          echo "WHERE-CYC-DRAM=00000000001561da"; echo "WHERE-INS-DRAM=0000000000007532" ;;
      esac
      if [ "$probe" = "${FAKE_SAMPLE_BAD:-}" ]; then echo "(no marker)"; echo "RC=0"
      elif [ "$probe" = "${FAKE_MARKER_MISSING:-}" ]; then echo "RC=0"
      elif [ "$probe" = "${FAKE_GATE_FAIL:-}" ]; then echo "PROBE-FAILED"; echo "RC=1"
      else echo "$(marker_of "$probe")"; echo "RC=0"; fi ;;
  *) echo "(fake: unhandled)" ;;
esac
exit 0
