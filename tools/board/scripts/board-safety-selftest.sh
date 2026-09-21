#!/usr/bin/env bash
# End-to-end safety gates, against a fake remote board. No hardware, no network, no real remote command.
#
# The fake board is a directory: the session prefix runs its arguments locally, and the paths the runner
# asks about (boot id, lock, deployment files) live under it. That is enough to exercise the four things
# review found missing -- a real preflight binding, a board-scoped lock, a remote-owned lifecycle, and
# remote file identity -- because every one of them is a question the runner asks *through the transport*.
#
#   board-safety-selftest.sh <fresh dir>
set -u
here=$(cd "$(dirname "$0")" && pwd)
xv6=$here/../../xv6-boot/scripts
out=${1:?usage: board-safety-selftest.sh <fresh dir>}
[ -e "$out" ] && { echo "REFUSE: $out exists"; exit 2; }
mkdir -p "$out"

pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   : $1"; }
no() { fail=$((fail+1)); echo "  FAIL : $1 -- $2"; }
want() { if eval "$2"; then ok "$1"; else no "$1" "$3"; fi; }

BOARD=$out/board; mkdir -p "$BOARD"
LAUNCHES=$out/launches.txt; : > "$LAUNCHES"
SESSION=6f1d0a3c-2b47-4e18-9f55-1c0de7a94b21
printf '%s\n' "$SESSION" > "$BOARD/boot_id"

# the deployment files, on the "board"
printf 'fake kernel\n' > "$BOARD/kernel-128mib"
printf 'fake disk\n'   > "$BOARD/fs-run.img"
cat > "$BOARD/fesvr-teaching" <<EOF
#!/usr/bin/env bash
printf '%s\n' "launched: \$*" >> "$LAUNCHES"
exec env FAKESIM_MODE=ok FAKESIM_INPUT_LOG="$out/typed.txt" python3 "$xv6/fakesim.py" "\$@"
EOF
chmod +x "$BOARD/fesvr-teaching"
K_SHA=$(sha256sum "$BOARD/kernel-128mib" | cut -d' ' -f1)
D_SHA=$(sha256sum "$BOARD/fs-run.img"    | cut -d' ' -f1)
H_SHA=$(sha256sum "$BOARD/fesvr-teaching" | cut -d' ' -f1)

# The transport contract: the prefix receives ONE argument, a complete shell command, and runs it with a
# shell on the board. This fake is the minimal honest implementation of that -- which is also what
# `ssh host` does once its arguments have been joined.
cat > "$out/session.sh" <<'EOF'
#!/usr/bin/env bash
exec /bin/sh -c "$1"
EOF
chmod +x "$out/session.sh"

# The fake that behaves like real ssh: it JOINS all its command arguments with spaces and hands the result
# to a shell. The old `prefix + [sh, -c, script]` construction works under the fake above and breaks here,
# which is exactly why it survived review. The procedure's own invocation is run through this one.
cat > "$out/session-ssh.sh" <<'EOF'
#!/usr/bin/env bash
joined="$*"
exec /bin/sh -c "$joined"
EOF
chmod +x "$out/session-ssh.sh"

python3 "$here/make-mem-fixtures.py" "$out/fixtures" >/dev/null

run() {  # run <outdir> <evidence-dir> [extra args...]
  local o=$1 ev=$2; shift 2
  python3 "$here/_test_runner.py" "$o" \
    --transport-cmd "$out/session.sh" \
    --host-binary "$BOARD/fesvr-teaching" --kernel "$BOARD/kernel-128mib" --disk "$BOARD/fs-run.img" \
    --evidence-dir "$ev" \
    --expect "$BOARD/kernel-128mib=$K_SHA" --expect "$BOARD/fs-run.img=$D_SHA" \
    --expect "$BOARD/fesvr-teaching=$H_SHA" \
    --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52 \
    --channel multiplexed --remote-lock "$BOARD/host.lock" --remote-boot-id "$BOARD/boot_id" \
    --stage-timeout 30 --startup-timeout 30 "$@"
}

echo "== 1. the gate: every one of these must launch ZERO hosts"
before=$(wc -l < "$LAUNCHES")

run "$out/r-text" "just some text" > "$out/r-text.txt" 2>&1; rc=$?
want "arbitrary text instead of an evidence bundle is refused" "[ $rc = 2 ]" "it ran"
want "and it says a bundle is needed" "grep -q 'not a directory' $out/r-text.txt" "no reason"

run "$out/r-unsafe" "$out/fixtures/unsafe-512" > "$out/r-unsafe.txt" 2>&1; rc=$?
want "a bundle the preflight REFUSES is refused" "[ $rc = 2 ]" "it ran"
want "and the preflight's own reason is shown" "grep -q 'preflight refuses' $out/r-unsafe.txt" "no reason"

run "$out/r-stale" "$out/fixtures/changed-session" > "$out/r-stale.txt" 2>&1; rc=$?
want "a bundle from a different boot is refused" "[ $rc = 2 ]" "it ran"

# the board reboots after the evidence was captured: same bundle, new live boot id
printf '%s\n' "11111111-2222-3333-4444-555555555555" > "$BOARD/boot_id"
run "$out/r-reboot" "$out/fixtures/safe-256" > "$out/r-reboot.txt" 2>&1; rc=$?
want "a good bundle is refused once the board has REBOOTED under it" "[ $rc = 2 ]" "it ran"
want "and it says to capture again" "grep -q 'Capture again' $out/r-reboot.txt" "no instruction"
printf '%s\n' "$SESSION" > "$BOARD/boot_id"

cp -r "$out/fixtures/safe-256" "$out/substituted"
printf 'MemTotal:       524288 kB\n' > "$out/substituted/proc-meminfo"
run "$out/r-sub" "$out/substituted" > "$out/r-sub.txt" 2>&1; rc=$?
want "evidence substituted after capture is refused" "[ $rc = 2 ]" "it ran"

# a deployment file on the board that is not the approved one
printf 'tampered\n' > "$BOARD/kernel-128mib"
run "$out/r-tamper" "$out/fixtures/safe-256" > "$out/r-tamper.txt" 2>&1; rc=$?
want "a deployment file on the board that is not the approved one is refused" "[ $rc = 2 ]" "it ran"
want "and it names the file"  "grep -q 'not the approved ones' $out/r-tamper.txt" "no reason"
printf 'fake kernel\n' > "$BOARD/kernel-128mib"

after=$(wc -l < "$LAUNCHES")
want "ZERO hosts were launched by any of the six refusals" "[ $before = $after ]" \
     "$((after-before)) host(s) were launched"

echo "== 2. a good run, and a second one from a DIFFERENT output root"
run "$out/run-a" "$out/fixtures/safe-256" > "$out/run-a.txt" 2>&1; rc=$?
tail -3 "$out/run-a.txt" | sed 's/^/        /'
want "the good run completes"  "[ $rc = 0 ]" "it did not"
want "the remote exit was confirmed" "grep -qx '# remote exit confirmed: yes' $out/run-a/stages.txt" "not confirmed"
want "the board lock was released after a confirmed exit" "[ ! -d $BOARD/host.lock ]" "a stale lock remains"
want "remote file hashes are in the record, not NOT-LOCAL" \
     "grep -q \"# kernel sha256: $K_SHA\" $out/run-a/stages.txt && grep -q \"# host binary sha256: $H_SHA\" $out/run-a/stages.txt && ! grep -q NOT-LOCAL $out/run-a/stages.txt" \
     "the record does not identify the remote files"
want "the board's live boot id is in the record" "grep -q '$SESSION' $out/run-a/stages.txt" "not recorded"
want "the same checker accepts it" "python3 $xv6/check-xv6.py $out/run-a --require-commands > $out/check-a.txt 2>&1" \
     "$(head -3 $out/check-a.txt 2>/dev/null | tail -1)"

# hold the board lock as though another session owned it, from a different local output root
mkdir -p "$BOARD/host.lock"; echo "someone else" > "$BOARD/host.lock/owner"
n0=$(wc -l < "$LAUNCHES")
run "$out/run-b-different-root" "$out/fixtures/safe-256" > "$out/run-b.txt" 2>&1; rc=$?
want "a second run from a DIFFERENT output root is refused on the same board" "[ $rc = 2 ]" "both ran"
want "and it launched nothing" "[ $n0 = $(wc -l < $LAUNCHES) ]" "a second host was launched"
rm -rf "$BOARD/host.lock"

echo "== 3. an existing host on the board is detected before launch"
sleep 600 &
stock=$!
# make it look like a stock fesvr to the detector
n0=$(wc -l < "$LAUNCHES")
cat > "$out/session-busy.sh" <<EOF
#!/usr/bin/env bash
if [[ "\$1" == ps* ]]; then
  echo "  $stock /usr/local/bin/fesvr-zynq +blkdev=/root/fs.img /root/kernel"
  exit 0
fi
exec /bin/sh -c "\$1"
EOF
chmod +x "$out/session-busy.sh"
python3 "$here/_test_runner.py" "$out/run-busy" --transport-cmd "$out/session-busy.sh" \
  --host-binary "$BOARD/fesvr-teaching" --kernel "$BOARD/kernel-128mib" --disk "$BOARD/fs-run.img" \
  --evidence-dir "$out/fixtures/safe-256" \
  --expect "$BOARD/kernel-128mib=$K_SHA" --expect "$BOARD/fs-run.img=$D_SHA" \
  --expect "$BOARD/fesvr-teaching=$H_SHA" \
  --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52 \
  --channel multiplexed --remote-lock "$BOARD/host.lock" --remote-boot-id "$BOARD/boot_id" > "$out/run-busy.txt" 2>&1
rc=$?
kill $stock 2>/dev/null
want "an existing stock fesvr-zynq on the board is detected and the run refused" "[ $rc = 2 ]" "it ran anyway"
want "and it says a host is already running" "grep -q 'already running' $out/run-busy.txt" "no reason"
want "and it launched nothing" "[ $n0 = $(wc -l < $LAUNCHES) ]" "a host was launched"

echo "== 4. a remote host that outlives the local session"
# The session dies but the remote process keeps running: a local exit must not be read as a remote exit.
# a host that ignores SIGTERM: the remote process outlives both the signal and the session
cat > "$BOARD/fesvr-teaching-stubborn" <<EOF
#!/usr/bin/env bash
# Ignores TERM, so the remote side survives both the signal and the session. Records its own pid so the
# test can clean up by pid rather than by a pkill pattern -- a pattern here would match the test's own
# process tree, which is how a previous cleanup in this repo killed its own shell.
trap '' TERM
echo \\$\\$ > "$out/stubborn.pid"
echo "xv6 kernel is booting"
sleep 120
EOF
chmod +x "$BOARD/fesvr-teaching-stubborn"
S_SHA=$(sha256sum "$BOARD/fesvr-teaching-stubborn" | cut -d' ' -f1)

cat > "$out/session-drop.sh" <<'EOF'
#!/usr/bin/env bash
# Stands in for a session that drops: the remote work is started detached and survives, while the local
# client goes away. This is what makes "a local exit is not a remote exit" concrete.
# Only the launch command, which is the one that backgrounds the host and records its pid. Matching any
# mention of the binary would also hijack the gate's own sha256sum, which names it too.
if [[ "$1" == *fesvr-teaching-stubborn* && "$1" == *exec* ]]; then
  setsid /bin/sh -c "$1" </dev/null >/dev/null 2>&1 &
  sleep 0.5
  exit 255
fi
exec /bin/sh -c "$1"
EOF
chmod +x "$out/session-drop.sh"
rm -rf "$BOARD/host.lock"
timeout 300 python3 "$here/_test_runner.py" "$out/run-drop" --transport-cmd "$out/session-drop.sh" \
  --host-binary "$BOARD/fesvr-teaching-stubborn" --kernel "$BOARD/kernel-128mib" --disk "$BOARD/fs-run.img" \
  --evidence-dir "$out/fixtures/safe-256" \
  --expect "$BOARD/kernel-128mib=$K_SHA" --expect "$BOARD/fs-run.img=$D_SHA" \
  --expect "$BOARD/fesvr-teaching-stubborn=$S_SHA" \
  --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52 \
  --channel multiplexed --remote-lock "$BOARD/host.lock" --remote-boot-id "$BOARD/boot_id" \
  --stage-timeout 4 --startup-timeout 4 --stop-timeout 5 > "$out/run-drop.txt" 2>&1
rc=$?
tail -2 "$out/run-drop.txt" | sed 's/^/        /'
want "a run whose remote exit cannot be confirmed FAILS"  "[ $rc != 0 ]" "it reported success"
want "it is not labelled a deliberate stop" \
     "! grep -qx '# stop: deliberate-stop-after-all-commands' $out/run-drop/stages.txt" \
     "an unconfirmed run was labelled a clean stop"
want "the record says the remote exit was not confirmed" \
     "grep -qx '# remote exit confirmed: no' $out/run-drop/stages.txt" "not recorded"
want "the record demands a cold restart" "grep -q 'cold platform restart' $out/run-drop/stages.txt" "no instruction"
want "ownership was NOT released" "[ -d $BOARD/host.lock ]" "the lock was dropped on an uncertain state"
want "the checker rejects an uncertain transcript" \
     "! python3 $xv6/check-xv6.py $out/run-drop --require-commands > $out/check-drop.txt 2>&1" "it was accepted"
[ -f "$out/stubborn.pid" ] && kill -9 "$(cat "$out/stubborn.pid")" 2>/dev/null; true
rm -rf "$BOARD/host.lock"


echo "== 5. the SAME invocation through a fake that JOINS arguments, as real ssh does"
n0=$(wc -l < "$LAUNCHES")
python3 "$here/_test_runner.py" "$out/run-ssh" --transport-cmd "$out/session-ssh.sh" \
  --host-binary "$BOARD/fesvr-teaching" --kernel "$BOARD/kernel-128mib" --disk "$BOARD/fs-run.img" \
  --evidence-dir "$out/fixtures/safe-256" \
  --expect "$BOARD/kernel-128mib=$K_SHA" --expect "$BOARD/fs-run.img=$D_SHA" \
  --expect "$BOARD/fesvr-teaching=$H_SHA" \
  --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52 \
  --channel multiplexed --remote-lock "$BOARD/host.lock" --remote-boot-id "$BOARD/boot_id" \
  --stage-timeout 30 --startup-timeout 30 > "$out/run-ssh.txt" 2>&1
rc=$?
tail -2 "$out/run-ssh.txt" | sed 's/^/        /'
want "the run completes under an argument-joining transport" "[ $rc = 0 ]" \
     "the remote command did not survive being joined and re-parsed -- this is the real-ssh case"
want "the checker accepts that transcript too" \
     "python3 $xv6/check-xv6.py $out/run-ssh --require-commands > $out/check-ssh.txt 2>&1" \
     "$(head -3 $out/check-ssh.txt 2>/dev/null | tail -1)"
want "it really did launch under the joining transport" "[ $n0 != $(wc -l < $LAUNCHES) ]" "nothing launched"

echo "== 6. each role must be approved by its EXACT path"
n0=$(wc -l < "$LAUNCHES")
role_case() {  # role_case <name> <description> <expect args...>
  local nm=$1 desc=$2; shift 2
  python3 "$here/_test_runner.py" "$out/role-$nm" --transport-cmd "$out/session.sh" \
    --host-binary "$BOARD/fesvr-teaching" --kernel "$BOARD/kernel-128mib" --disk "$BOARD/fs-run.img" \
    --evidence-dir "$out/fixtures/safe-256" "$@" \
    --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52 \
    --channel multiplexed --remote-lock "$BOARD/host.lock" --remote-boot-id "$BOARD/boot_id" \
    > "$out/role-$nm.txt" 2>&1
  local rc=$?
  want "$desc" "[ $rc = 2 ]" "it ran anyway"
}
role_case no-host "a missing host-binary approval is refused" \
  --expect "$BOARD/kernel-128mib=$K_SHA" --expect "$BOARD/fs-run.img=$D_SHA"
role_case no-kernel "a missing kernel approval is refused" \
  --expect "$BOARD/fesvr-teaching=$H_SHA" --expect "$BOARD/fs-run.img=$D_SHA"
role_case no-disk "a missing disk approval is refused" \
  --expect "$BOARD/fesvr-teaching=$H_SHA" --expect "$BOARD/kernel-128mib=$K_SHA"
role_case unrelated "approvals for unrelated paths only are refused" \
  --expect "/etc/hostname=$K_SHA"
role_case badsha "an approval that is not a sha256 is refused" \
  --expect "$BOARD/fesvr-teaching=$H_SHA" --expect "$BOARD/kernel-128mib=not-a-hash" \
  --expect "$BOARD/fs-run.img=$D_SHA"

# the same basename in a different directory, approved -- the substitution the old basename match allowed
mkdir -p "$BOARD/elsewhere"; printf 'different kernel\n' > "$BOARD/elsewhere/kernel-128mib"
E_SHA=$(sha256sum "$BOARD/elsewhere/kernel-128mib" | cut -d' ' -f1)
role_case samebasename "a same-basename file from another directory cannot stand in" \
  --expect "$BOARD/fesvr-teaching=$H_SHA" --expect "$BOARD/elsewhere/kernel-128mib=$E_SHA" \
  --expect "$BOARD/fs-run.img=$D_SHA"
want "none of the role failures launched a host" "[ $n0 = $(wc -l < $LAUNCHES) ]" "a host was launched"

echo "== 7. the device lock is one lock, and cleanup is not a recursive delete"
python3 - "$here" <<'PYEOF'
import sys, os
sys.path.insert(0, sys.argv[1])
from transport import BoardTransport, TransportError, UncertainState

fails = []
def want(c, w, why):
    print(("  ok   : " if c else "  FAIL : ") + w + ("" if c else " -- " + why))
    if not c: fails.append(w)

# a non-production lock without the test flag is refused
try:
    BoardTransport("true", "/h", "/d", "/k", remote_lock="/tmp/elsewhere.lock",
                   channel="multiplexed")
    want(False, "a non-production lock path is refused without the test flag", "it was accepted")
except TransportError as e:
    want("not the production lock" in str(e),
         "a non-production lock path is refused without the test flag", f"wrong reason: {e}")

# an over-broad path is refused even with the test flag
for bad in ("/", "/tmp", "/tmp/x"):
    try:
        BoardTransport("true", "/h", "/d", "/k", remote_lock=bad, allow_test_lock=True,
                       channel="multiplexed")
        want(False, f"the over-broad lock path {bad!r} is refused", "it was accepted")
    except TransportError as e:
        want("too broad or unexpected" in str(e),
             f"the over-broad lock path {bad!r} is refused", f"wrong reason: {e}")

# cleanup issues named removals and an rmdir, never a recursive delete -- checked against a recording fake
class Recorder(BoardTransport):
    def __init__(self):
        super().__init__("true", "/h", "/d", "/k", remote_lock="/tmp/fake-board.lock",
                         allow_test_lock=True, channel="multiplexed")
        self.issued = []
        self.owned = True
        self.state = "remote-exit-confirmed"
        self.token = "1234-1700000000-deadbeef"   # the real shape: <pid>-<unix time>-<8 hex>
    def _run(self, script, timeout=30):
        self.issued.append(script)
        if script.startswith("cat "): return 0, "~ # 1234-1700000000-deadbeef"   # with console furniture
        return 0, "RELEASED"

r = Recorder(); r.release()
joined = " ; ".join(r.issued)
want(not any("rm -rf" in c for c in r.issued), "cleanup never issues rm -rf", f"issued {r.issued}")
want(any("rmdir" in c for c in r.issued), "cleanup rmdirs the lock directory", f"issued {r.issued}")
want(all(("owner" in c or "pid" in c or "exit" in c) for c in r.issued if c.startswith("rm ")),
     "cleanup removes only the three files it created", f"issued {r.issued}")

# a lock held by someone else is not ours to release
class Foreign(Recorder):
    def _run(self, script, timeout=30):
        self.issued.append(script)
        if script.startswith("cat "): return 0, "~ # 9999-1700000000-0badf00d"
        return 0, "RELEASED"
f = Foreign()
try:
    f.release(); want(False, "a lock with another owner's token is not released", "it was released")
except UncertainState:
    want(True, "a lock with another owner's token is not released", "")
    want(not any(c.startswith("rm ") for c in f.issued), "and nothing was removed", f"issued {f.issued}")

# cleanup that does not complete leaves ownership held and the state uncertain
class Stuck(Recorder):
    def _run(self, script, timeout=30):
        self.issued.append(script)
        if script.startswith("cat "): return 0, "~ # 1234-1700000000-deadbeef"
        return 1, "rmdir: Directory not empty"
st = Stuck()
try:
    st.release(); want(False, "failed cleanup raises rather than dropping ownership", "it returned")
except UncertainState:
    want(st.owned and st.state == "uncertain",
         "failed cleanup leaves ownership held and the state uncertain", "ownership was dropped")

sys.exit(1 if fails else 0)
PYEOF
if [ $? = 0 ]; then pass=$((pass+9)); else fail=$((fail+1)); echo "  FAIL : the lock unit checks"; fi


echo "== 8. the PRODUCTION CLI: no test switches, and conflicts refused before any remote call"
# A transport prefix that records every remote command. If the production CLI ever reaches the board in
# these cases, this file will say so.
CALLS=$out/production-calls.txt; : > "$CALLS"
cat > "$out/session-record.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$CALLS"
exec /bin/sh -c "\$1"
EOF
chmod +x "$out/session-record.sh"

prod() {  # prod <outdir> [args...]
  python3 "$here/board-runner.py" "$1" --transport-cmd "$out/session-record.sh" \
    --host-binary "$BOARD/fesvr-teaching" --kernel "$BOARD/kernel-128mib" --disk "$BOARD/fs-run.img" \
    --evidence-dir "$out/fixtures/safe-256" \
    --channel multiplexed \
    --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52 "${@:2}"
}

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
prod "$out/p-dup" --expect "$BOARD/kernel-128mib=$A" --expect "$BOARD/kernel-128mib=$B" \
     --expect "$BOARD/fesvr-teaching=$H_SHA" --expect "$BOARD/fs-run.img=$D_SHA" \
     > "$out/p-dup.txt" 2>&1
rc=$?
want "two different hashes for one path are refused" "[ $rc = 2 ]" "the later one silently won"
want "and the message names both" "grep -q "$A" $out/p-dup.txt && grep -q "$B" $out/p-dup.txt" "not named"
want "no remote command was issued" "[ ! -s $CALLS ]" "the board was contacted before the refusal"

prod "$out/p-same" --expect "$BOARD/kernel-128mib=$K_SHA" --expect "$BOARD/kernel-128mib=$K_SHA" \
     --expect "$BOARD/fesvr-teaching=$H_SHA" --expect "$BOARD/fs-run.img=$D_SHA" \
     > "$out/p-same.txt" 2>&1
want "an identical repeat is accepted (it is not a contradiction)" \
     "! grep -q 'two different hashes' $out/p-same.txt" "an identical repeat was called a conflict"

for sw in --allow-test-lock "--remote-lock=$BOARD/host.lock" "--remote-boot-id=$BOARD/boot_id"; do
  : > "$CALLS"
  prod "$out/p-sw" --expect "$BOARD/kernel-128mib=$K_SHA" "$sw" > "$out/p-sw.txt" 2>&1
  rc=$?
  want "the production CLI rejects $sw" "[ $rc != 0 ]" "it was accepted"
  want "  and issued no remote command" "[ ! -s $CALLS ]" "the board was contacted"
done

want "the production CLI mentions no test switch at all" \
     "! python3 $here/board-runner.py --help 2>&1 | grep -qE 'allow-test-lock|remote-lock|remote-boot-id'" \
     "a test override is still on the production entry point"
want "the production transport uses the production lock" \
     "python3 -c \"import sys; sys.path.insert(0,'$here'); from transport import BoardTransport as B; t=B('true','/h','/d','/k',channel='multiplexed'); sys.exit(0 if t.lock=='/var/lock/teaching-fesvr.lock' else 1)\"" \
     "the default lock is not the production one"

echo "BOARD_SAFETY_SELFTEST pass=$pass fail=$fail"
[ "$fail" = 0 ]
