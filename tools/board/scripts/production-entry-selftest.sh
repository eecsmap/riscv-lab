#!/usr/bin/env bash
# The PRODUCTION entry point, exercised AS production.
#
# Hardware session 2 failed because `board-runner.py` parsed --channel and --serial-device and never passed
# them to the transport. Every existing suite reached the runner through `_test_runner.py`, which did pass
# them, so the one construction production actually performs had no coverage at all -- and the file that
# was supposed to cover it, board-runner-selftest.sh, had rotted into passing stale flags: argparse exited
# 2 before anything ran and nine of its checks passed vacuously.
#
# So this runs `board-runner.py` itself, with its PRODUCTION constants unmodified -- the real
# /var/lock/teaching-fesvr.lock and the real /proc/sys/kernel/random/boot_id -- against a real /bin/sh on a
# real PTY. Nothing here is a fake of the runner; the only fake is the board.
#
# It ends by MUTATING the plumbing back to the broken state and proving these checks go red. A test that
# cannot fail for the bug it was written for is not evidence, and that is the lesson this file exists for.
#
#   production-entry-selftest.sh <fresh dir>
set -u
here=$(cd "$(dirname "$0")" && pwd)
xv6=$here/../../xv6-boot/scripts
shim=$here/../../xv6-board-run/scripts/serial-transport.py
out=${1:?usage: production-entry-selftest.sh <fresh dir>}
[ -e "$out" ] && { echo "REFUSE: $out exists"; exit 2; }
mkdir -p "$out"

pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   : $1"; }
no() { fail=$((fail+1)); echo "  FAIL : $1 -- $2"; }
want() { if eval "$2"; then ok "$1"; else no "$1" "$3"; fi; }

BIT=2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52
PROD_LOCK=/var/lock/teaching-fesvr.lock
BOOT=$(cat /proc/sys/kernel/random/boot_id)

# The production lock path is real on this host. If something is already there it is not ours to disturb.
[ -e "$PROD_LOCK" ] && { echo "REFUSE: $PROD_LOCK already exists; not touching it"; exit 2; }
BOARDPID=""
cleanup() {
  [ -n "$BOARDPID" ] && kill "$BOARDPID" 2>/dev/null
  rm -f "$PROD_LOCK"/owner "$PROD_LOCK"/pid "$PROD_LOCK"/exit 2>/dev/null
  rmdir "$PROD_LOCK" 2>/dev/null
  [ -n "${FLOCKPID:-}" ] && kill "$FLOCKPID" 2>/dev/null
  [ -n "${DEV2PID:-}" ] && kill "$DEV2PID" 2>/dev/null
  return 0
}
trap cleanup EXIT

board_up() {   # board_up <name> ; sets DEV and ST
  ST="$out/$1"; mkdir -p "$ST/root"
  python3 "$here/real_pty_board.py" "$ST" --host-mode normal > "$ST/dev" 2>"$ST/board.log" &
  BOARDPID=$!
  for _ in $(seq 1 50); do [ -s "$ST/dev" ] && break; sleep 0.2; done
  DEV=$(cat "$ST/dev")
  cp "$here/fake_host.py" "$ST/root/fesvr-teaching-static"; chmod +x "$ST/root/fesvr-teaching-static"
  printf 'kernel\n' > "$ST/root/kernel-128mib"
  printf 'disk\n'   > "$ST/root/fs-run.img"
  H=$(sha256sum "$ST/root/fesvr-teaching-static" | cut -d' ' -f1)
  K=$(sha256sum "$ST/root/kernel-128mib" | cut -d' ' -f1)
  D=$(sha256sum "$ST/root/fs-run.img" | cut -d' ' -f1)
}
board_down() { kill "$BOARDPID" 2>/dev/null; wait "$BOARDPID" 2>/dev/null; BOARDPID=""; }

# the memory evidence, bound to the boot id the production code path will actually read
python3 "$here/make-mem-fixtures.py" "$out/fixtures" >/dev/null
printf '%s\0' "$BOOT" > "$out/fixtures/safe-256/session-id"

# runner <entry-script> <outdir> [extra args...] -- PRODUCTION flags only; no test-only knobs exist here
runner() {
  local entry=$1 o=$2; shift 2
  python3 "$entry" "$o" \
    --transport-cmd "python3 $shim --device $DEV" \
    --channel exclusive --serial-device "$DEV" \
    --host-binary "$ST/root/fesvr-teaching-static" \
    --kernel "$ST/root/kernel-128mib" --disk "$ST/root/fs-run.img" \
    --evidence-dir "$out/fixtures/safe-256" \
    --expect "$ST/root/fesvr-teaching-static=$H" \
    --expect "$ST/root/kernel-128mib=$K" \
    --expect "$ST/root/fs-run.img=$D" \
    --bitstream-sha $BIT \
    --stage-timeout 25 --startup-timeout 25 --stop-timeout 15 "$@"
}

printf '%s\n' 'echo teaching-xv6-hello' 'ls' 'cat README' 'echo abc | wc' > "$out/expected-host-stdin.txt"

# Independence between sections. A leaked lock from section 2 once made both mutations in section 5 stop
# at "the board's host lock is held" -- and 5b reported a pass while running nothing at all, which is the
# same vacuous-pass failure this file was written to eliminate. Each section starts from a known state,
# and the leak itself is asserted where it happens rather than being inherited silently.
reset_lock() {
  rm -f "$PROD_LOCK"/owner "$PROD_LOCK"/pid "$PROD_LOCK"/exit 2>/dev/null
  rmdir "$PROD_LOCK" 2>/dev/null
  return 0
}

echo "== 1. board-runner.py itself, exclusive, through the four commands"
board_up normal
runner "$here/board-runner.py" "$out/run" > "$out/run.txt" 2>&1
rc=$?
tail -3 "$out/run.txt" | sed 's/^/        /'
want "the production run completes"        "[ $rc = 0 ]" "exit $rc -- $(tail -1 $out/run.txt)"
want "all seven stages are ok"             "[ \$(grep -c '^ok' $out/run/stages.txt) = 7 ]" "not seven"
want "the remote exit was confirmed"       "grep -qx '# remote exit confirmed: yes' $out/run/stages.txt" "not confirmed"
want "the stop was the deliberate one"     "grep -q '^# stop: deliberate' $out/run/stages.txt" "$(grep '^# stop:' $out/run/stages.txt)"
want "the production lock was released"    "[ ! -d $PROD_LOCK ]" "a stale lock remains at $PROD_LOCK"
want "the checker accepts the transcript" \
     "python3 $xv6/check-xv6.py $out/run --require-commands > $out/check.txt 2>&1" \
     "$(head -3 $out/check.txt 2>/dev/null | tail -1)"

echo "== 1b. the record states how the board was ACTUALLY driven"
# Session 2 was launched with --channel exclusive, driven multiplexed, and no record said so.
want "the record names the effective channel"  "grep -qx '# channel: exclusive' $out/run/stages.txt" \
     "$(grep '^# channel' $out/run/stages.txt || echo 'no channel line')"
want "  and the exact console device it locked" "grep -qx '# console device: $DEV' $out/run/stages.txt" \
     "$(grep '^# console device' $out/run/stages.txt || echo 'no device line')"

echo "== 1c. nothing of ours reached the host's stdin"
# THE hardware symptom: xv6 received 'stty -echo' and 'cat /var/lock/teaching-fesvr.lock/pid' and replied
# 'exec stty failed'. An exact transcript comparison catches an extra byte of any shape.
if diff -u "$out/expected-host-stdin.txt" "$ST/host-stdin.txt" > "$out/host-stdin.diff" 2>&1; then
  ok "the host's input is EXACTLY the four driver commands, in order, and nothing else"
else
  no "the host's input is EXACTLY the four driver commands, in order, and nothing else" \
     "$(head -6 "$out/host-stdin.diff" | tr '\n' ' ')"
fi
want "  no control command was typed at the host" \
     "! grep -qE 'stty|teaching-fesvr.lock|sha256sum|ps -eo' $ST/host-stdin.txt" \
     "$(grep -m1 -E 'stty|lock|sha256sum' $ST/host-stdin.txt)"
board_down

reset_lock
echo "== 2. the device is genuinely locked: a prior holder blocks the run"
board_up locked
flock "$DEV" sleep 30 & FLOCKPID=$!
sleep 0.5
runner "$here/board-runner.py" "$out/run-locked" > "$out/locked.txt" 2>&1
rc=$?
kill $FLOCKPID 2>/dev/null; FLOCKPID=""
want "a run against an already-held device is refused" "[ $rc = 2 ]" "exit $rc"
want "  and it says the device is held"  "grep -q 'already held by another process' $out/locked.txt" \
     "$(head -2 $out/locked.txt | tr '\n' ' ')"
want "  and it launched no host"         "grep -q 'No host was launched' $out/locked.txt" "it may have started one"
want "  and it left no lock behind"      "[ ! -d $PROD_LOCK ]" "a stale lock remains"
board_down

reset_lock
echo "== 3. the two names for the device must be the same line"
board_up mismatch
# it must stay open: a pty that has already been closed is refused for not existing, which would make
# this check pass without ever reaching the comparison it is about
python3 -c "import pty,os,sys,time; m,s=pty.openpty(); sys.stdout.write(os.ttyname(s)+chr(10)); sys.stdout.flush(); time.sleep(300)" > "$out/dev2" &
DEV2PID=$!
for _ in $(seq 1 50); do [ -s "$out/dev2" ] && break; sleep 0.2; done
DEV2=$(cat "$out/dev2")
python3 "$here/board-runner.py" "$out/run-mismatch" \
  --transport-cmd "python3 $shim --device $DEV" --channel exclusive --serial-device "$DEV2" \
  --host-binary "$ST/root/fesvr-teaching-static" --kernel "$ST/root/kernel-128mib" \
  --disk "$ST/root/fs-run.img" --evidence-dir "$out/fixtures/safe-256" \
  --expect "$ST/root/fesvr-teaching-static=$H" --expect "$ST/root/kernel-128mib=$K" \
  --expect "$ST/root/fs-run.img=$D" --bitstream-sha $BIT > "$out/mismatch.txt" 2>&1
rc=$?
# this can only be detected if BOTH values reached the constructor
want "a lock on one line and a shim on another is refused" "[ $rc = 2 ]" "exit $rc"
want "  and it names both lines"  "grep -q 'must be the same line' $out/mismatch.txt" \
     "$(head -2 $out/mismatch.txt | tr '\n' ' ')"

echo "== 4. exclusive without a device is refused before anything is sent"
python3 "$here/board-runner.py" "$out/run-nodev" \
  --transport-cmd "python3 $shim --device $DEV" --channel exclusive \
  --host-binary "$ST/root/fesvr-teaching-static" --kernel "$ST/root/kernel-128mib" \
  --disk "$ST/root/fs-run.img" --evidence-dir "$out/fixtures/safe-256" \
  --expect "$ST/root/fesvr-teaching-static=$H" --expect "$ST/root/kernel-128mib=$K" \
  --expect "$ST/root/fs-run.img=$D" --bitstream-sha $BIT > "$out/nodev.txt" 2>&1
rc=$?
want "an exclusive run with no --serial-device is refused" "[ $rc = 2 ]" "exit $rc"
want "  and it launched no host" "grep -q 'No host was launched' $out/nodev.txt" "it may have started one"
board_down

echo "== 5. THE MUTATIONS: put the defect back and prove these checks go red"
# A copy of the tree with the relative layout board_run.py needs (../../xv6-boot/scripts).
mutant() {   # mutant <name> <sed program applied to board_run.py>
  local name=$1 prog=$2
  local M="$out/$name/experiments/teaching-cpu"
  mkdir -p "$M/xv6-board-prep"
  cp -r "$here" "$M/xv6-board-prep/scripts"
  mkdir -p "$M/xv6-boot"; ln -s "$(cd "$xv6" && pwd)" "$M/xv6-boot/scripts"
  sed -i "$prog" "$M/xv6-board-prep/scripts/board_run.py"
  echo "$M/xv6-board-prep/scripts/board-runner.py"
}

reset_lock
echo "-- 5a. the channel is dropped on the floor again (the session-2 defect, exactly)"
E=$(mutant mut-drop 's/^    kw = dict(expect=expect, channel=a.channel, serial_device=a.serial_device)$/    kw = dict(expect=expect)/')
board_up mut1
runner "$E" "$out/run-mut-drop" > "$out/mut-drop.txt" 2>&1
rc=$?
want "with the arguments dropped, the run does NOT succeed" "[ $rc != 0 ]" "the mutant passed -- this suite cannot detect the bug"
want "  and the constructor says the channel was never given" \
     "grep -q 'channel was not given' $out/mut-drop.txt" "$(tail -2 $out/mut-drop.txt | tr '\n' ' ')"
board_down

reset_lock
echo "-- 5b. the channel is supplied but wrong: a serial console driven as ssh"
E=$(mutant mut-multiplexed 's/^    kw = dict(expect=expect, channel=a.channel, serial_device=a.serial_device)$/    kw = dict(expect=expect, channel="multiplexed", serial_device=None)/')
board_up mut2
runner "$E" "$out/run-mut-mux" > "$out/mut-mux.txt" 2>&1
rc=$?
if [ -f "$ST/host-stdin.txt" ] && diff -q "$out/expected-host-stdin.txt" "$ST/host-stdin.txt" >/dev/null 2>&1; then
  clean_stdin=yes
else
  clean_stdin=no
fi
want "a console driven as multiplexed does NOT produce a clean run" \
     "[ $rc != 0 ] || [ $clean_stdin = no ]" "the mutant passed cleanly -- the suite would not have caught session 2"
want "  and the damage is visible at the host's stdin" "[ $clean_stdin = no ]" \
     "the host's input was clean, so this check proves nothing"
# and it must have got far enough to matter: a mutant stopped at the lock proves nothing about the channel
want "  the mutant actually reached the board, so this is not a vacuous pass" \
     "! grep -q \"host lock $PROD_LOCK is held\" $out/mut-mux.txt" \
     "the mutant was stopped by a stale lock before the channel mattered"
echo "        mutant host stdin: $(head -c 200 "$ST/host-stdin.txt" 2>/dev/null | tr '\n' '|')"
board_down

reset_lock
echo "== 6. the OTHER channel, through the same production entry"
# board-safety-selftest.sh covers multiplexed behaviour thoroughly, but through _test_runner.py. What was
# never covered is the production CLI plumbing the multiplexed choice either -- the same line was wrong
# for both. Here the prefix is a local session script honouring the transport contract: invoked with
# exactly ONE further argument, a complete shell command.
board_up mux
cat > "$out/session.sh" <<EOS
#!/bin/sh
printf '%s\n' "\$1" >> "$out/issued.txt"
exec /bin/sh -c "\$1"
EOS
chmod +x "$out/session.sh"
TEACHING_FAKE_STATE="$ST" python3 "$here/board-runner.py" "$out/run-mux" \
  --transport-cmd "$out/session.sh" --channel multiplexed \
  --host-binary "$ST/root/fesvr-teaching-static" --kernel "$ST/root/kernel-128mib" \
  --disk "$ST/root/fs-run.img" --evidence-dir "$out/fixtures/safe-256" \
  --expect "$ST/root/fesvr-teaching-static=$H" --expect "$ST/root/kernel-128mib=$K" \
  --expect "$ST/root/fs-run.img=$D" --bitstream-sha $BIT \
  --stage-timeout 25 --startup-timeout 25 --stop-timeout 15 > "$out/mux.txt" 2>&1
rc=$?
tail -2 "$out/mux.txt" | sed 's/^/        /'
want "the multiplexed production run reaches all seven stages" \
     "[ -f $out/run-mux/stages.txt ] && [ \$(grep -c '^ok' $out/run-mux/stages.txt) = 7 ]" \
     "$(tail -1 $out/mux.txt)"
want "  the record names the effective channel" "grep -qx '# channel: multiplexed' $out/run-mux/stages.txt" \
     "$(grep '^# channel' $out/run-mux/stages.txt 2>/dev/null || echo none)"
want "  and records that no console device was locked" \
     "grep -qx '# console device: none (multiplexed)' $out/run-mux/stages.txt" \
     "$(grep '^# console device' $out/run-mux/stages.txt 2>/dev/null || echo none)"
want "  the remote pid was read back as a framed reply" \
     "grep -q 'CT' $out/issued.txt" "no framed control read was issued"
want "  and the production lock was released" "[ ! -d $PROD_LOCK ]" "a stale lock remains"
board_down

reset_lock
echo "== 7. a console device on a multiplexed channel is refused"
python3 "$here/board-runner.py" "$out/run-devmux" \
  --transport-cmd "$out/session.sh" --channel multiplexed --serial-device "$DEV2" \
  --host-binary "$ST/root/fesvr-teaching-static" --kernel "$ST/root/kernel-128mib" \
  --disk "$ST/root/fs-run.img" --evidence-dir "$out/fixtures/safe-256" \
  --expect "$ST/root/fesvr-teaching-static=$H" --expect "$ST/root/kernel-128mib=$K" \
  --expect "$ST/root/fs-run.img=$D" --bitstream-sha $BIT > "$out/devmux.txt" 2>&1
rc=$?
want "a device given for a multiplexed channel is refused" "[ $rc = 2 ]" "exit $rc"
want "  and it launched no host" "grep -q 'No host was launched' $out/devmux.txt" "it may have started one"

echo "PRODUCTION_ENTRY_SELFTEST pass=$pass fail=$fail"
[ "$fail" = 0 ]
