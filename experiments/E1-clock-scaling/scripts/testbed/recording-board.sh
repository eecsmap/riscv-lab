#!/usr/bin/env bash
# A recording stand-in for the serial shim. Every command it is asked to run is APPENDED to $E1_REC
# before anything is answered, so a test can assert what the entrypoint did -- and, more to the point,
# what it did NOT do after a refusal.
#
# It also REFUSES a target ELF that is not passed to fesvr. The probes are RISC-V binaries and cannot
# execute on the ARM; an earlier version of the library invoked them directly and the mocks accepted it
# because they matched on ".elf". A stand-in that accepts what hardware would reject is worse than none.
set -u
CMD="$1"
printf '%s\n' "BOARD $CMD" >> "${E1_REC:?E1_REC must be set}"
: "${FAKE_BID:=11111111-2222-3333-4444-555555555555}"
: "${FAKE_UP:=42}" ; : "${FAKE_N:=0}" ; : "${FAKE_F:=0}" ; : "${FAKE_L:=NO_LOCK}"
: "${FAKE_PROGRC:=0}" ; FAKE_PROGDONE=${FAKE_PROGDONE-1} ; : "${FAKE_GATE_FAIL:=}"
: "${FAKE_TRANSPORT_FAIL:=}" ; : "${FAKE_MARKER_MISSING:=}" ; : "${FAKE_SAMPLE_BAD:=}"
: "${FAKE_TMO:=yes}" ; : "${FAKE_RESV:=absent}" ; : "${FAKE_SESSION:=$FAKE_BID}"

if [ "${FAKE_WRAP:-0}" = 1 ]; then
    # The real shim's echo is WRAPPED by the terminal; the run-2 logs show commands broken mid-word. A
    # wrap just after "echo " puts the next line at column 0, so even an anchored ^BID= can match the
    # question rather than the answer.
    printf 'echo \n'; printf 'BID=%s\n' "${FAKE_DECOY:-dddddddd-dddd-dddd-dddd-dddddddddddd}"
    printf 'UP=999999\nN=99\nF=1\nL=PRESENT\n'
else
    printf '%s\n' "$CMD"
fi
[ -n "$FAKE_TRANSPORT_FAIL" ] && case "$CMD" in *"$FAKE_TRANSPORT_FAIL"*) echo "transport error"; exit 9 ;; esac

marker_of() { awk -v p="$1" '$1==p {print $2}' "$(dirname "$0")/../markers.tsv"; }
S=0                                        # the remote status this reply will report

emit_evidence() {
  case "$CMD" in
    *boot_id*)        echo "$FAKE_SESSION" ;;
    *proc/iomem*)     printf '00000000-0fffffff : System RAM\n  00008000-006168fb : Kernel code\ne0000000-e0000ffe : xuartps\n' ;;
    *meminfo*)        printf 'MemTotal:         252956 kB\nMemFree:          237772 kB\n' ;;
    *address-cells*)  echo " 00 00 00 01" ;;
    *size-cells*)     echo " 00 00 00 01" ;;
    *memory/reg*)     echo " 00 00 00 00 10 00 00 00" ;;
    *"-d /proc/device-tree/reserved-memory"*)
        case "$FAKE_RESV" in absent) echo "DIR=absent" ;; *) echo "DIR=present" ;; esac ;;
    *"ls -1 /proc/device-tree/reserved-memory"*)
        case "$FAKE_RESV" in
          listfail) echo "ls: can't open"; S=1 ;;
          *)        echo "mmio-sram@0" ;;
        esac ;;
    *"-f /proc/device-tree/reserved-memory"*)
        echo "REG=yes" ;;
    *"reserved-memory/"*)                  # the node's reg bytes
        case "$FAKE_RESV" in
          regfail)   echo "od: can't open"; S=1 ;;
          malformed) echo " 00 zz 00 01" ;;
          *)         echo " 00 00 00 00 00 10 00 00" ;;
        esac ;;
  esac
}

case "$CMD" in
  *BID=*)     echo "BID=$FAKE_BID"; echo "UP=$FAKE_UP"; echo "N=$FAKE_N"; echo "F=$FAKE_F"; echo "L=$FAKE_L" ;;
  *TMO=*)     echo "TMO=$FAKE_TMO" ;;
  *MODE=*)    echo "MODE=ok" ;;
  *PROG_RC=*) echo "PROG_RC=$FAKE_PROGRC" ;;
  *PD=*)      echo "PD=$FAKE_PROGDONE"; echo "BOOTID=$FAKE_BID"; echo "UP=$FAKE_UP"
              echo "LOAD=0.0 0.0 0.0"; echo "FESVR_N=0"; echo "LOCK=NO_LOCK" ;;
  *__E1B__*)  echo "__E1B__"; emit_evidence; echo "__E1S__=$S"; echo "__E1E__" ;;
  *.elf*)
      case "$CMD" in
        *"./fesvr-teaching-static ./"*) : ;;
        *) echo "sh: ./${CMD##*./}: cannot execute binary file: Exec format error"
           echo "RC=126"
           printf '%s\n' "REJECTED-NO-FESVR $CMD" >> "$E1_REC"
           exit 0 ;;
      esac
      probe=$(sed -n 's|.*fesvr-teaching-static \./\([a-z0-9_]*\)\.elf.*|\1|p' <<<"$CMD")
      echo "teaching: ready after 50 ms; status=0x00131811 cpu_restart_safe=1 pl_reconfig_safe=0 boot_ready=1"
      case "$probe" in
        perf03_fetch) echo "FETCH-CYC-32BIT=000000000012770a"; echo "FETCH-INS-32BIT=0000000000007532"
                      echo "FETCH-CYC-COMPRESSED=000000000009e8d9"; echo "FETCH-INS-COMPRESSED=0000000000007532" ;;
        perf04_where) echo "WHERE-CYC-CLINT=00000000001397c2"; echo "WHERE-INS-CLINT=0000000000007532"
                      echo "WHERE-CYC-DRAM=00000000001561da"; echo "WHERE-INS-DRAM=0000000000007532" ;;
      esac
      if   [ "$probe" = "${FAKE_SAMPLE_BAD:-}" ];     then echo "(no marker)"; echo "RC=0"
      elif [ "$probe" = "${FAKE_MARKER_MISSING:-}" ]; then echo "RC=0"
      elif [ "$probe" = "${FAKE_GATE_FAIL:-}" ];      then echo "PROBE-FAILED"; echo "RC=1"
      else echo "$(marker_of "$probe")"; echo "RC=0"; fi ;;
  *) echo "(fake: unhandled)" ;;
esac
exit 0
