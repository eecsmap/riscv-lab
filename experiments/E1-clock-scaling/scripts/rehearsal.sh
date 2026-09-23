#!/usr/bin/env bash
# Prove the E1 gates refuse, each FOR ITS OWN REASON, without touching the board.
#
# A gate that always refused would pass every negative test here, so each negative asserts the specific
# exit code AND that the message names the right thing, and the positives prove the same gates let a
# healthy board through. Nothing in this file opens a serial device.
set -u
cd "$(dirname "$0")"
export E1_BOARD_CMD="$PWD/fake-board.sh"
export E1_LOG=""
PIN=$(mktemp); echo "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" > $PIN
EMPTY=$(mktemp); : > $EMPTY
npass=0; nfail=0
ok() { npass=$((npass+1)); echo "  ok   : $1"; }
no() { nfail=$((nfail+1)); echo "  FAIL : $1 -- $2"; }

# Run a gate in a subshell, capturing its exit code and its message.
try() { ( . ./lib-e1.sh; "$@" ) 2>&1; }
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
  expect_refusal "an UNCHANGED boot id is refused as no power cycle" 10 "no power cycle" -- verify_cold_cycle $PIN
FAKE_UP=99999 \
  expect_refusal "a changed boot id with a long uptime is refused" 11 "not the cold platform" -- verify_cold_cycle $PIN
FAKE_N=7 \
  expect_refusal "a non-empty /root/xv6run is refused" 12 "initramfs" -- verify_cold_cycle $PIN
FAKE_F=1 \
  expect_refusal "a running host is refused" 13 "host process" -- verify_cold_cycle $PIN
FAKE_L=PRESENT \
  expect_refusal "an ownership lock is refused and NOT cleared" 13 "must not be cleared" -- verify_cold_cycle $PIN
FAKE=unreadable \
  expect_refusal "an unreadable boot id is refused, not assumed" 10 "state is unknown" -- verify_cold_cycle $PIN
expect_refusal "with no pinned value there is nothing to compare against" 50 "BEFORE powering down" -- verify_cold_cycle $EMPTY

echo "== 2. the same gate PASSES a genuinely cold board, and returns the new boot id cleanly"
out=$( . ./lib-e1.sh; verify_cold_cycle $PIN 2>/dev/null ); c=$?
[ "$c" = 0 ] && ok "a cold board passes" || no "a cold board passes" "exit $c"
[ "$out" = "11111111-2222-3333-4444-555555555555" ] \
  && ok "  and stdout is exactly the new boot id, uncorrupted by progress output" \
  || no "  stdout is the new boot id" "got '$out'"

echo "== 3. the on-board hash gate"
FAKE_SHA=0000000000000000000000000000000000000000000000000000000000000000 \
  expect_refusal "a wrong hash ON THE BOARD is refused" 20 "expected" -- verify_on_board /root/x/y 6b5da7e786186bac97bd2156a720f4be78e4bf8e7e396bae61351ae9361c3acb
( . ./lib-e1.sh; verify_on_board /root/x/y 6b5da7e786186bac97bd2156a720f4be78e4bf8e7e396bae61351ae9361c3acb ) >/dev/null 2>&1 \
  && ok "the right hash passes" || no "the right hash passes" "it refused a correct hash"

echo "== 4. programming"
FAKE_PROGDONE=0 \
  expect_refusal "prog_done=0 after programming stops everything" 21 "not configured" -- program_payload /root/x/y.bin
FAKE_PROGDONE=x \
  expect_refusal "an unreadable prog_done is refused, not read as success" 21 "unreadable" -- program_payload /root/x/y.bin
( . ./lib-e1.sh; program_payload /root/x/y.bin ) >/dev/null 2>&1 \
  && ok "prog_done=1 passes" || no "prog_done=1 passes" "it refused a configured fabric"

echo "== 5. the eight startup gates"
G=$(mktemp -d)
for probe in boot01_marker ext04_sv39; do
  FAKE_GATE_FAIL=$probe \
    expect_refusal "a failing $probe stops the session (not skipped, not retried)" 30 "stops here" -- run_startup_gates $G 5
done
( . ./lib-e1.sh; run_startup_gates $G 5 ) >/dev/null 2>&1 \
  && ok "eight healthy gates pass" || no "eight healthy gates pass" "a healthy board was refused"
n=$(ls $G/*.out 2>/dev/null | wc -l)
[ "$n" -eq 8 ] && ok "  and all eight transcripts were written" || no "eight transcripts" "got $n"

echo "== 6. the refusals are distinguishable from one another"
codes=$(for s in "FAKE_BID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" "FAKE_UP=99999" "FAKE_N=7" "FAKE_F=1"; do
          ( export $s; code verify_cold_cycle $PIN ); done | sort -u | tr '\n' ' ')
[ "$(wc -w <<<"$codes")" -eq 4 ] \
  && ok "four different causes give four different exit codes ($codes)" \
  || no "distinct exit codes" "got: $codes"

echo "== 7. the shim's echo is wrapped by the terminal; the gate must read the ANSWER, not the echo"
# The decoy is what a wrapped echo puts FIRST, and it is also what we pin. A parser that reads the first
# match therefore sees bid == pinned and refuses with exit 10; one that reads the answer sees the real
# boot id and passes. The decoy also carries a bad uptime, a dirty directory, a live host and a lock, so
# reading the echo fails every other sub-gate too -- there is no way to pass this by accident.
DECOY=dddddddd-dddd-dddd-dddd-dddddddddddd
PIN2=$(mktemp); echo "$DECOY" > $PIN2
out=$( FAKE_WRAP=1 FAKE_DECOY=$DECOY; export FAKE_WRAP FAKE_DECOY; . ./lib-e1.sh; verify_cold_cycle $PIN2 2>/dev/null ); c=$?
if [ "$c" = 0 ] && [ "$out" = "11111111-2222-3333-4444-555555555555" ]; then
    ok "a wrapped echo carrying a decoy BID= line is not mistaken for the answer"
else
    no "a wrapped echo is not mistaken for the answer" "exit $c, read '$out' (the decoy would give exit 10)"
fi
rm -f $PIN2

echo "E1_REHEARSAL pass=$npass fail=$nfail"
rm -rf $G $PIN $EMPTY
exit $([ $nfail -eq 0 ] && echo 0 || echo 1)
