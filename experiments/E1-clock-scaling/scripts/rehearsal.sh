#!/usr/bin/env bash
# Prove the E1 gate FUNCTIONS refuse, each for its own reason, without touching the board.
#
# This is the library-level companion to entrypoint-rehearsal.sh, which drives the real scripts. Both
# use the same recording stand-in under testbed/ -- there is no second fake to drift.
#
# A gate that always refused would pass every negative here, so each negative asserts the exit code AND
# that the message names its own reason, and the positives prove the same gates pass a healthy board.
set -u
cd "$(dirname "$0")"
export E1_BOARD_CMD="$PWD/testbed/recording-board.sh"
export E1_REC=$(mktemp)
export E1_LOG=""
PIN=$(mktemp); echo "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" > $PIN
EMPTY=$(mktemp); : > $EMPTY
BID=$(mktemp)
npass=0; nfail=0
ok() { npass=$((npass+1)); echo "  ok   : $1"; }
no() { nfail=$((nfail+1)); echo "  FAIL : $1 -- $2"; }

try()  { ( . ./lib-e1.sh; "$@" ) 2>&1; }
code() { ( . ./lib-e1.sh; "$@" ) >/dev/null 2>&1; echo $?; }

expect_refusal() {   # <label> <wanted-code> <wanted-text> -- <gate...>
    local label=$1 want=$2 text=$3; shift 4
    local c m; c=$(code "$@"); m=$(try "$@")
    if [ "$c" != "$want" ]; then no "$label" "exit $c, wanted $want"; return; fi
    if ! grep -qi -- "$text" <<<"$m"; then no "$label" "refused with the wrong reason: $(tail -1 <<<"$m")"; return; fi
    ok "$label (exit $want, names its reason)"
}

echo "== 1. the cold-cycle gate"
FAKE_BID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" \
  expect_refusal "an UNCHANGED boot id is refused as no reboot" 10 "no reboot" -- verify_cold_cycle $PIN $BID
FAKE_UP=99999 \
  expect_refusal "a changed boot id with a long uptime is refused" 11 "not the cold platform" -- verify_cold_cycle $PIN $BID
FAKE_N=7 \
  expect_refusal "a non-empty /root/xv6run is refused" 12 "initramfs" -- verify_cold_cycle $PIN $BID
FAKE_F=1 \
  expect_refusal "a running host is refused" 13 "host process" -- verify_cold_cycle $PIN $BID
FAKE_L=PRESENT \
  expect_refusal "an ownership lock is refused and NOT cleared" 13 "must not be cleared" -- verify_cold_cycle $PIN $BID
FAKE_TRANSPORT_FAIL="boot_id" \
  expect_refusal "a transport failure is refused, not read as an answer" 62 "not known from here" -- verify_cold_cycle $PIN $BID
expect_refusal "with no pinned value there is nothing to compare against" 50 "BEFORE powering down" -- verify_cold_cycle $EMPTY $BID

echo "== 2. the same gate PASSES a genuinely cold board, and hands back the new boot id"
: > $BID; c=$(code verify_cold_cycle $PIN $BID)
[ "$c" = 0 ] && ok "a cold board passes" || no "a cold board passes" "exit $c"
[ "$(cat $BID)" = "11111111-2222-3333-4444-555555555555" ] \
  && ok "  and the new boot id is written to the file the caller named" \
  || no "the boot id is handed back" "got '$(cat $BID)'"

echo "== 3. the power-removal attestation, which the boot id cannot supply"
REC=$(mktemp); : > $REC
expect_refusal "an empty power record is refused" 14 "physically removing" -- verify_power_record $REC $PIN
printf 'POWER_REMOVED=no\n' > $REC
expect_refusal "a record that does not attest removal is refused" 14 "does not attest" -- verify_power_record $REC $PIN
printf 'POWER_REMOVED=yes\nAT=now\n' > $REC; touch -d '1 hour ago' $REC
expect_refusal "a record OLDER than the pin attests to an earlier cycle" 14 "OLDER than the pin" -- verify_power_record $REC $PIN
printf 'POWER_REMOVED=yes\nAT=now\n' > $REC
[ "$(code verify_power_record $REC $PIN)" = 0 ] && ok "a fresh attestation passes" || no "a fresh attestation passes" "refused"

echo "== 4. programming: the command's status AND prog_done, neither alone"
FAKE_PROGRC=1 \
  expect_refusal "a non-zero programming status is refused" 21 "was not written" -- program_payload /root/x.bin
FAKE_PROGRC=0 FAKE_PROGDONE=0 \
  expect_refusal "programming that leaves prog_done=0 is refused" 21 "not configured" -- program_payload /root/x.bin
FAKE_PROGRC=0 FAKE_PROGDONE=x \
  expect_refusal "a garbage prog_done is refused, not read as success" 21 "not configured" -- program_payload /root/x.bin
FAKE_PROGRC=0 FAKE_PROGDONE="" \
  expect_refusal "an EMPTY prog_done is named as unreadable, not assumed" 21 "unreadable" -- program_payload /root/x.bin
[ "$(code program_payload /root/x.bin)" = 0 ] && ok "rc=0 and prog_done=1 passes" || no "the healthy case passes" "refused"

echo "== 5. the eight startup gates"
G=$(mktemp -d)
for probe in boot01_marker ext04_sv39; do
  FAKE_GATE_FAIL=$probe \
    expect_refusal "a failing $probe stops the session (not skipped, not retried)" 30 "stops here" -- run_startup_gates $G 5
done
FAKE_MARKER_MISSING=boot03_ddr \
  expect_refusal "a gate that exits 0 without its marker is refused" 30 "not a result" -- run_startup_gates $G 5
rm -rf $G; G=$(mktemp -d)
[ "$(code run_startup_gates $G 5)" = 0 ] && ok "eight healthy gates pass" || no "eight healthy gates pass" "refused"
n=$(ls $G/*.out 2>/dev/null | wc -l)
[ "$n" -eq 8 ] && ok "  and all eight transcripts were written" || no "eight transcripts" "got $n"

echo "== 6. perf samples are judged by the probe parser, not by RC=0"
S=$(mktemp -d)
FAKE_SAMPLE_BAD=perf03_fetch \
  expect_refusal "a sample with rc=0 but no marker is not usable" 40 "MEASUREMENT FAILED" -- run_perf_samples $S 2 5
rm -rf $S; S=$(mktemp -d)
[ "$(code run_perf_samples $S 2 5)" = 0 ] && ok "healthy samples are usable" || no "healthy samples" "refused"

echo "== 7. the refusals are distinguishable from one another"
codes=$(for s in "FAKE_BID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" "FAKE_UP=99999" "FAKE_N=7" "FAKE_F=1"; do
          ( export $s; code verify_cold_cycle $PIN $BID ); done | sort -u | tr '\n' ' ')
[ "$(wc -w <<<"$codes")" -eq 4 ] \
  && ok "four different causes give four different exit codes ($codes)" \
  || no "distinct exit codes" "got: $codes"

echo "== 8. the shim's echo is wrapped by the terminal; the gate must read the ANSWER"
# The decoy is what a wrapped echo puts FIRST, and it is also what we pin. Reading the first match
# therefore yields bid == pinned and exit 10; reading the answer passes. The decoy also carries a bad
# uptime, a dirty directory, a live host and a lock, so there is no way to pass this by accident.
DECOY=dddddddd-dddd-dddd-dddd-dddddddddddd
PIN2=$(mktemp); echo "$DECOY" > $PIN2; : > $BID
c=$( FAKE_WRAP=1 FAKE_DECOY=$DECOY; export FAKE_WRAP FAKE_DECOY; code verify_cold_cycle $PIN2 $BID )
if [ "$c" = 0 ] && [ "$(cat $BID)" = "11111111-2222-3333-4444-555555555555" ]; then
    ok "a wrapped echo carrying a decoy BID= line is not mistaken for the answer"
else
    no "a wrapped echo is not mistaken for the answer" "exit $c, read '$(cat $BID)' (the decoy would give exit 10)"
fi

echo "E1_REHEARSAL pass=$npass fail=$nfail"
rm -rf $G $S $PIN $PIN2 $EMPTY $BID $REC $E1_REC
exit $([ $nfail -eq 0 ] && echo 0 || echo 1)
