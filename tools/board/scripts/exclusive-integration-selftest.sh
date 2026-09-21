#!/usr/bin/env bash
# The exclusive channel, end to end, against a REAL terminal.
#
# Not direct start/stop calls this time: the shared `board_run.run` is driven through the shell stage, the
# four commands and the checker, over a real `/bin/sh` on a real controlling PTY, using the **production**
# serial shim pointed at that PTY with --device. The previous round tested the lifecycle in isolation and
# against a fake that wrote the answers itself; this tests the thing that will actually run.
#
#   exclusive-integration-selftest.sh <fresh dir>
set -u
here=$(cd "$(dirname "$0")" && pwd)
xv6=$here/../../xv6-boot/scripts
shim=$here/../../xv6-board-run/scripts/serial-transport.py
out=${1:?usage: exclusive-integration-selftest.sh <fresh dir>}
[ -e "$out" ] && { echo "REFUSE: $out exists"; exit 2; }
mkdir -p "$out"

pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   : $1"; }
no() { fail=$((fail+1)); echo "  FAIL : $1 -- $2"; }
want() { if eval "$2"; then ok "$1"; else no "$1" "$3"; fi; }

SESSION=9e62de9e-f7f1-4cf4-93f0-060bff64ae3b
BIT=2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52

board_up() {   # board_up <name> <host-mode> ; sets DEV and ST
  ST="$out/$1"; mkdir -p "$ST"
  python3 "$here/real_pty_board.py" "$ST" --host-mode "$2" > "$ST/dev" 2>"$ST/board.log" &
  BOARDPID=$!
  for _ in $(seq 1 50); do [ -s "$ST/dev" ] && break; sleep 0.2; done
  DEV=$(cat "$ST/dev")
  # the deployment the fake board will be asked about
  mkdir -p "$ST/root"
  cp "$here/fake_host.py" "$ST/root/fesvr-teaching-static"   # a real executable: exec must really run it
  chmod +x "$ST/root/fesvr-teaching-static"
  printf 'kernel\n' > "$ST/root/kernel-128mib"
  printf 'disk\n'   > "$ST/root/fs-run.img"
  H=$(sha256sum "$ST/root/fesvr-teaching-static" | cut -d' ' -f1)
  K=$(sha256sum "$ST/root/kernel-128mib" | cut -d' ' -f1)
  D=$(sha256sum "$ST/root/fs-run.img" | cut -d' ' -f1)
  # the board's boot id, with the trailing NUL the real one has
  printf '%s\0' "$SESSION" > "$ST/boot_id"
}
board_down() { kill "$BOARDPID" 2>/dev/null; wait "$BOARDPID" 2>/dev/null; }

python3 "$here/make-mem-fixtures.py" "$out/fixtures" >/dev/null
# bind the fixture to the boot id this fake board reports
printf '%s\0' "$SESSION" > "$out/fixtures/safe-256/session-id"

run_exclusive() {   # run_exclusive <outdir> [extra args...]
  local o=$1; shift
  python3 "$here/_test_runner.py" "$o" \
    --transport-cmd "python3 $shim --device $DEV" \
    --channel exclusive --serial-device "$DEV" \
    --host-binary "$ST/root/fesvr-teaching-static" \
    --kernel "$ST/root/kernel-128mib" --disk "$ST/root/fs-run.img" \
    --evidence-dir "$out/fixtures/safe-256" \
    --expect "$ST/root/fesvr-teaching-static=$H" \
    --expect "$ST/root/kernel-128mib=$K" \
    --expect "$ST/root/fs-run.img=$D" \
    --bitstream-sha $BIT \
    --remote-lock "$ST/board.lock" --remote-boot-id "$ST/boot_id" \
    --stage-timeout 25 --startup-timeout 25 --stop-timeout 15 "$@"
}

echo "== 0. the drain is genuinely bounded -- against the PRODUCTION pump"
# The previous version of this check reimplemented pump() inside the test, so it proved only that the copy
# was bounded. Review caught it counting a 34.16 s UNBOUNDED result as success. It now imports
# board_run.ConsolePump -- the exact object run() uses -- and drives it against a real unbuffered producer
# that never stops and never exits. BOUNDED is required; UNBOUNDED must fail the suite.
python3 - "$here" <<'PYEOF' > "$out/drain.txt" 2>&1
import re, subprocess, sys, time
here = sys.argv[1]
sys.path.insert(0, here)
from board_run import ConsolePump          # the production implementation, not a copy

producer = subprocess.Popen(
    [sys.executable, "-u", "-c", "import time\nwhile True:\n    print('noise'); time.sleep(0.02)"],
    stdout=subprocess.PIPE, bufsize=0)     # unbuffered, as the transport opens its session
seen = []
p = ConsolePump(producer.stdout, producer.poll, seen.append,
                re.compile(r"((AT|RD2|EV|EVA|EVH|RD2HOST|RBOOT)\s+\d+\s+\S.*)$"))
BOUND = 2.0
start = time.monotonic()
ret = p.pump(time.monotonic() + BOUND, drain=True)
el = time.monotonic() - start
producer.kill(); producer.wait()
print(f"drain returned={ret} after {el:.3f}s, {len(seen)} console pieces")
print("BOUNDED" if (ret is True and el < BOUND * 2) else "UNBOUNDED")
sys.exit(0 if (ret is True and el < BOUND * 2) else 1)
PYEOF
drain_rc=$?
want "the PRODUCTION pump's drain returns within its bound" \
     "[ $drain_rc = 0 ] && grep -qx BOUNDED $out/drain.txt" "$(tail -1 $out/drain.txt)"
want "  and it really did keep reading while bounded" \
     "grep -qE 'console pieces' $out/drain.txt && ! grep -q ', 0 console pieces' $out/drain.txt" \
     "$(tail -1 $out/drain.txt)"
want "  and the exemption is gone from the production code" \
     "! grep -vE '^\s*#' $here/board_run.py | grep -q 'not drain and'" "the exemption is still there"

echo "== 1. the shared runner, over a real terminal, through the four commands"
board_up normal normal
run_exclusive "$out/run" > "$out/run.txt" 2>&1
rc=$?
tail -3 "$out/run.txt" | sed 's/^/        /'
want "the run completes"                 "[ $rc = 0 ]" "it did not"
want "all four commands are recorded ok" "[ \$(grep -c '^ok' $out/run/stages.txt) = 7 ]" "not seven stages"
want "the remote exit was confirmed"     "grep -qx '# remote exit confirmed: yes' $out/run/stages.txt" "not confirmed"
want "the checker accepts the transcript" \
     "python3 $xv6/check-xv6.py $out/run --require-commands > $out/check.txt 2>&1" \
     "$(head -3 $out/check.txt 2>/dev/null | tail -1)"
want "the board lock was released"       "[ ! -d $ST/board.lock ]" "a stale lock remains"
# The host's complete input must be EXACTLY the four command lines, in order, and nothing else.
# Pattern-matching for "control-looking" lines was wrong twice over: it flagged `cat README`, which is one
# of the four commands the workload is supposed to send, and it could not have seen an injected command
# that did not happen to match the pattern. Comparing the whole input against the expected transcript
# detects an extra byte of any shape without assuming what one would look like.
printf '%s\n' 'echo teaching-xv6-hello' 'ls' 'cat README' 'echo abc | wc' > "$out/expected-host-stdin.txt"
if diff -u "$out/expected-host-stdin.txt" "$ST/host-stdin.txt" > "$out/host-stdin.diff" 2>&1; then
  ok "the host's input is EXACTLY the four driver commands, in order, and nothing else"
else
  no "the host's input is EXACTLY the four driver commands, in order, and nothing else" \
     "$(head -6 "$out/host-stdin.diff" | tr '\n' ' ')"
fi
board_down

echo "== 2. a host that really ignores SIGINT (the kernel delivers it; the host survives)"
board_up deaf deaf
run_exclusive "$out/run-deaf" > "$out/run-deaf.txt" 2>&1
rc=$?
tail -2 "$out/run-deaf.txt" | sed 's/^/        /'
want "the run fails"                       "[ $rc != 0 ]" "it reported success"
want "the state is recorded uncertain"     "grep -q 'uncertain' $out/run-deaf/stages.txt" "not recorded"
want "the remote exit was NOT confirmed"   "grep -qx '# remote exit confirmed: no' $out/run-deaf/stages.txt" "wrongly confirmed"
want "a cold restart is demanded"          "grep -q 'cold platform restart' $out/run-deaf/stages.txt" "no instruction"
want "ownership was NOT released"          "[ -d $ST/board.lock ]" "the lock was dropped on an uncertain state"
board_down

echo "== 3. the local transport dies while the remote host lives"
board_up drop normal
python3 - "$here" "$shim" "$DEV" "$ST" "$out" <<'PYEOF'
import os, subprocess, sys, time
here, shim, dev, st, out = sys.argv[1:6]
sys.path.insert(0, here)
from transport import BoardTransport, UncertainState
tp = BoardTransport(f"{sys.executable} {shim} --device {dev}",
                    f"{st}/root/fesvr-teaching-static", f"{st}/root/fs-run.img",
                    f"{st}/root/kernel-128mib",
                    remote_lock=f"{st}/board.lock", allow_test_lock=True,
                    remote_boot_id=f"{st}/boot_id", channel="exclusive", serial_device=dev)
tp.remote_boot_id(); tp.claim(); tp.start()
time.sleep(1.0)
# the local shim is killed outright: it cannot frame anything, and the host on the other side lives on
tp.proc.kill(); tp.proc.wait()
try:
    tp.stop(timeout=5)
    open(f"{out}/drop-result", "w").write("STOPPED-CLEANLY")
except UncertainState as e:
    open(f"{out}/drop-result", "w").write("UNCERTAIN " + str(e))
open(f"{out}/drop-owned", "w").write(str(tp.owned))
PYEOF
want "a killed transport is reported as uncertain" "grep -q '^UNCERTAIN' $out/drop-result" \
     "$(head -c 80 $out/drop-result)"
want "  and it says the shell may not have come back" \
     "grep -q 'no evidence' $out/drop-result" "no such reason"
want "  ownership is retained"  "grep -qx 'True' $out/drop-owned" "ownership was dropped"
# Nothing at all should have reached this host: the run never got as far as typing a command. `wc -c`
# rather than a grep, so an extra byte of any shape is visible. (`grep -c ... || echo 0` also printed two
# zero lines on no-match, which made the comparison itself unreliable.)
BYTES=$(wc -c < "$ST/host-stdin.txt" 2>/dev/null); BYTES=${BYTES:-0}
want "ZERO bytes of any kind reached the still-live host" "[ \"$BYTES\" -eq 0 ]" \
     "$BYTES byte(s) were delivered into a host that was still running"
board_down

echo "== 4. the serial device lock: two cooperating contenders"
# These used to be prints. A test that only prints SECOND-OK cannot fail, so it was not testing anything;
# the outcomes are assertions now and contribute to the suite's verdict.
board_up lockdev normal
python3 - "$here" "$DEV" "$ST" "$shim" <<'PYEOF' > "$out/lock.txt" 2>&1
import os, sys
here, dev, st, shim = sys.argv[1:5]
sys.path.insert(0, here)
from transport import BoardTransport, TransportError
def mk():
    # the real shim, pointed at this device: the transport now requires that the line it locks is the
    # line the shim opens, so a prefix that names no device is refused before anything is claimed
    return BoardTransport(f"{sys.executable} {shim} --device {dev}",
                          f"{st}/root/h", f"{st}/root/d", f"{st}/root/k",
                          remote_lock=f"{st}/x.lock", allow_test_lock=True,
                          channel="exclusive", serial_device=dev)
a = mk(); a._claim_local_device()
b = mk()
try:
    b._claim_local_device(); print("SECOND-OK")
except TransportError:
    print("SECOND-REFUSED")
a._release_local_device()
try:
    c = mk(); c._claim_local_device(); print("AFTER-RELEASE-OK"); c._release_local_device()
except TransportError as e:
    print("AFTER-RELEASE-REFUSED", e)
PYEOF
board_down > /dev/null 2>&1
want "a second cooperating opener of the same device is refused" \
     "grep -qx SECOND-REFUSED $out/lock.txt" "$(head -2 $out/lock.txt | tr '\n' ' ')"
want "  and the device is claimable again once released" \
     "grep -qx AFTER-RELEASE-OK $out/lock.txt" "$(head -2 $out/lock.txt | tr '\n' ' ')"
want "  the lock never reported SECOND-OK" \
     "! grep -qx SECOND-OK $out/lock.txt" "a second opener got the lock"

echo "EXCLUSIVE_INTEGRATION pass=$pass fail=$fail"
[ "$fail" = 0 ]
