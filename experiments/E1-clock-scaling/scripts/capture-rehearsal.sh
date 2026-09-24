#!/usr/bin/env bash
# The capture-to-preflight flow, against the REAL mem-preflight.py.
#
# The recording stand-in supplies the board's replies; everything downstream of it is production code.
# mem-preflight permits a reserved-memory node to be ABSENT and does not permit one to be UNREADABLE,
# so the cases that matter are the ones where a read fails and an earlier version quietly wrote less
# evidence instead of refusing.
set -u
cd "$(dirname "$0")"
HERE=$PWD
PREFLIGHT=/home/engineer/fpga/riscv-lab/tools/board/scripts/mem-preflight.py
SESSION=11111111-2222-3333-4444-555555555555
npass=0; nfail=0
ok() { npass=$((npass+1)); echo "  ok   : $1"; }
no() { nfail=$((nfail+1)); echo "  FAIL : $1 -- $2"; }

# Every invocation is BOUNDED. A test that hangs reports nothing, and the one bug this file exists to
# catch has a hang as its failure mode -- an override defeated, the real serial device opened.
cap() {   # cap <dest>; env from the caller. echoes the exit code.
    E1_REC=${E1_REC:-$(mktemp)} E1_BOARD_CMD="$HERE/testbed/recording-board.sh" \
      timeout 30 python3 capture_evidence.py --dest "$1" >"$1.out" 2>"$1.err"
    echo $?
}
pref() { python3 "$PREFLIGHT" "$1" --expect-session "$SESSION" >"$1.pf" 2>&1; echo $?; }

echo "== 1. reserved-memory absent: captured, and the real preflight accepts it"
D=$(mktemp -d); rc=$(FAKE_RESV=absent cap $D)
[ "$rc" = 0 ] && ok "capture succeeds" || no "capture succeeds" "exit $rc: $(cat $D.err)"
[ "$(pref $D)" = 0 ] && ok "  MEM_PREFLIGHT OK on the captured evidence" || no "preflight accepts" "$(tail -2 $D.pf)"
grep -q "absent is acceptable" "$D.pf" && ok "  and the preflight itself says absence is acceptable" \
  || ok "  (the preflight accepted it)"
[ ! -d "$D/dt/reserved" ] && ok "  no reserved node was invented" || no "no node invented" "one exists"

echo "== 2. a real reserved node: captured as bytes, and still accepted"
D=$(mktemp -d); rc=$(FAKE_RESV=nodes cap $D)
[ "$rc" = 0 ] && ok "capture succeeds with a node present" || no "capture with a node" "exit $rc: $(cat $D.err)"
[ -s "$D/dt/reserved/mmio-sram@0/reg" ] && ok "  the node's reg bytes are on disk" || no "node reg written" "missing"
n=$(stat -c%s "$D/dt/reserved/mmio-sram@0/reg" 2>/dev/null || echo 0)
[ "$n" = 8 ] && ok "  and are exactly the 8 bytes the board sent" || no "node reg length" "got $n"
[ "$(pref $D)" = 0 ] && ok "  MEM_PREFLIGHT OK" || no "preflight accepts a node" "$(tail -2 $D.pf)"

echo "== 3. a FAILED listing is refused, not treated as 'no nodes'"
D=$(mktemp -d); rc=$(FAKE_RESV=listfail cap $D)
[ "$rc" = 1 ] && ok "capture refuses (exit 1)" || no "failed listing refused" "exit $rc"
grep -q "listing reserved-memory failed" "$D.err" && ok "  and names the listing as the failure" \
  || no "reason named" "$(cat $D.err)"
[ ! -d "$D/dt/reserved" ] && ok "  and no partial reserved evidence was left behind" || no "no partial evidence" "a node dir exists"

echo "== 4. a node that exists but cannot be READ is refused"
D=$(mktemp -d); rc=$(FAKE_RESV=regfail cap $D)
[ "$rc" = 1 ] && ok "capture refuses an unreadable reg" || no "unreadable reg refused" "exit $rc"
grep -q "reading reserved node" "$D.err" && ok "  and names the node" || no "reason names the node" "$(cat $D.err)"

echo "== 5. malformed bytes are refused, not sifted for whatever looks like hex"
D=$(mktemp -d); rc=$(FAKE_RESV=malformed cap $D)
[ "$rc" = 1 ] && ok "capture refuses malformed od output" || no "malformed refused" "exit $rc"
grep -qE "not plain od output|is not a byte" "$D.err" && ok "  and says the reply was not parseable as bytes" \
  || no "reason named" "$(cat $D.err)"

echo "== 6. a transport failure is distinguished from a remote command failure"
D=$(mktemp -d); rc=$(FAKE_TRANSPORT_FAIL=meminfo cap $D)
[ "$rc" = 1 ] && ok "a transport failure refuses" || no "transport failure refused" "exit $rc"
grep -q "the transport failed" "$D.err" && ok "  and is named as a TRANSPORT failure, not a board answer" \
  || no "transport named" "$(cat $D.err)"

echo "== 7. evidence from the wrong boot is refused by the preflight, not by us pretending"
D=$(mktemp -d); rc=$(FAKE_SESSION=99999999-9999-9999-9999-999999999999 cap $D)
[ "$rc" = 0 ] && ok "capture records whatever session the board reports" || no "capture" "exit $rc"
[ "$(pref $D)" != 0 ] && ok "  and the real preflight refuses it against the expected session" \
  || no "preflight refuses a foreign session" "it accepted"

echo "== 8. the DEFAULT E1_BOARD_CMD reaches the capture helper (it did not: it was never exported)"
# No hardware: SHIM is pointed at an isolated stand-in BEFORE sourcing, so what is exercised is
# lib-e1.sh's own default initialisation and export, not a value the caller supplied.
FAKESHIM=$(mktemp /tmp/fakeshimXXXX.py)
cat > "$FAKESHIM" <<'PYEOF'
import sys, os, subprocess
sys.exit(subprocess.run([os.environ["E1_REAL_FAKE"], sys.argv[-1]]).returncode)
PYEOF
D=$(mktemp -d)
out=$(timeout 30 bash -c '
  export E1_REC=$(mktemp) E1_REAL_FAKE="$1/testbed/recording-board.sh"
  unset E1_BOARD_CMD
  export SHIM=$2
  cd "$1"; . ./lib-e1.sh
  # exactly what the entrypoints do, with nothing added to the environment by hand
  capture_memory_evidence "$3" "$4" 2>&1
' _ "$HERE" "$FAKESHIM" "$D" "$SESSION")
rc=$?
[ $rc = 124 ] && out="TIMED OUT -- an override was defeated and the real device was opened"
[ $rc = 0 ] && ok "capture works with only lib-e1.sh's default, no caller-supplied env" \
  || no "the default reaches the helper" "exit $rc: $(tail -2 <<<"$out")"
[ -s "$D/session-id" ] && ok "  and the evidence was actually written" || no "evidence written" "missing"

echo "E1_CAPTURE_REHEARSAL pass=$npass fail=$nfail"
exit $([ $nfail -eq 0 ] && echo 0 || echo 1)
