#!/usr/bin/env bash
# Run the ACTUAL install and restore entrypoints against recording stubs, and assert what they did NOT do.
#
# The library rehearsal proves each gate refuses. It does not prove the CALLER stops -- and it did not:
# `NEWBID=$(verify_cold_cycle ...)` let `die` exit only the subshell while the parent went on to program
# the FPGA. That is what this file exists to catch, so every negative asserts ZERO subsequent deploy,
# program and probe operations, read off a recording of everything the entrypoint actually asked for.
set -u
cd "$(dirname "$0")"
HERE=$PWD
npass=0; nfail=0
ok() { npass=$((npass+1)); echo "  ok   : $1"; }
no() { nfail=$((nfail+1)); echo "  FAIL : $1 -- $2"; }

# Counts of the dangerous classes, from the recording.
#
# `grep -c` PRINTS 0 and EXITS 1 when there are no matches, so the obvious `|| echo 0` appends a second
# zero and every count reads "0\n0". Use `|| true`: the printed count is already right.
n_deploy()  { grep -c '^SEND '                            "$REC" 2>/dev/null || true; }
n_program() { grep -c 'BOARD cat .*xdevcfg'               "$REC" 2>/dev/null || true; }
n_probe()   { grep -cE 'BOARD cd /root/xv6run && .*\.elf'  "$REC" 2>/dev/null || true; }
n_perf()    { grep -cE 'BOARD cd /root/xv6run && .*perf0' "$REC" 2>/dev/null || true; }
n_board()   { grep -c '^BOARD '                           "$REC" 2>/dev/null || true; }

setup() {                                   # fresh output root + recording, with the pins in place
    OUT=$(mktemp -d); REC=$OUT/recording.txt; : > "$REC"
    mkdir -p "$OUT/state"
    echo "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" > "$OUT/state/install-pin.txt"
    echo "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" > "$OUT/state/restore-pin.txt"
    for p in install restore; do
        { echo "POWER_REMOVED=yes"; echo "AT=now"; } > "$OUT/state/$p-power.txt"
    done
}

runscript() {                               # runscript <script> [args...]; env comes from the caller
    E1_OUT=$OUT E1_REC=$REC \
    E1_BOARD_CMD="$HERE/testbed/recording-board.sh" \
    E1_COORD="$HERE/testbed/recording-coord.sh" \
    SEND="$HERE/testbed/recording-send.py" \
    E1_MEMPREFLIGHT="$HERE/testbed/recording-mempreflight.py" \
    bash "$HERE/$1" "${@:2}" >"$OUT/stdout.txt" 2>"$OUT/stderr.txt"
    echo $?
}

# assert a refusal happened AND nothing dangerous followed it
expect_stop() {   # <label> <wanted-exit> <what may already have happened: deploy|program|probe|none>
    local label=$1 want=$2 allow=$3 rc=$4
    local d p b; d=$(n_deploy); p=$(n_program); b=$(n_probe)
    if [ "$rc" != "$want" ]; then
        no "$label" "exit $rc, wanted $want; stderr: $(tail -1 "$OUT/stderr.txt")"; return
    fi
    case "$allow" in
        none)    [ "$d" = 0 ] && [ "$p" = 0 ] && [ "$b" = 0 ] || { no "$label" "after refusing it still did deploy=$d program=$p probe=$b"; return; } ;;
        deploy)  [ "$p" = 0 ] && [ "$b" = 0 ] || { no "$label" "after refusing it still did program=$p probe=$b"; return; } ;;
        program) [ "$b" = 0 ] || { no "$label" "after refusing it still ran $b probe(s)"; return; } ;;
        # a gate failure happens PART WAY THROUGH the gates, so earlier gates having run is correct.
        # What must not happen is any perf sample after it.
        gates)   [ "$(n_perf)" = 0 ] || { no "$label" "after the gate failure it still took $(n_perf) perf sample(s)"; return; } ;;
    esac
    ok "$label (exit $want; deploy=$d program=$p probe=$b)"
}

echo "== A. the defect this file exists for: a refused cold cycle must stop the ENTRYPOINT"
setup; rc=$(FAKE_BID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee runscript e1-install.sh)
expect_stop "an UNCHANGED boot id stops install before any deploy or programming" 10 none "$rc"

echo "== B. a missing pin"
setup; rm -f "$OUT/state/install-pin.txt"; rc=$(runscript e1-install.sh)
expect_stop "no pinned boot id stops install" 50 none "$rc"

echo "== C. no attested power removal"
setup; rm -f "$OUT/state/install-power.txt"; rc=$(runscript e1-install.sh)
expect_stop "no power-removal record stops install" 14 none "$rc"
[ "$(n_board)" = 0 ] && ok "  and it never spoke to the board at all" || no "no board traffic" "$(n_board) commands"

echo "== D. a denied lease"
for l in board serial; do
  setup; rc=$(FAKE_CLAIM_DENY=$l runscript e1-install.sh)
  expect_stop "a denied '$l' lease stops install" 60 none "$rc"
  [ "$(n_board)" = 0 ] && ok "  and no transport call preceded the claim" || no "leases precede transport ($l)" "$(n_board) board commands were issued"
done

echo "== E. the memory preflight refusing"
setup; rc=$(FAKE_MEM_RC=1 runscript e1-install.sh)
expect_stop "a refused memory preflight stops install before deploying anything" 61 none "$rc"

echo "== F. a failed upload"
setup; rc=$(FAKE_SEND_FAIL=e1-25mhz runscript e1-install.sh)
expect_stop "a failed deploy stops install before programming" 20 deploy "$rc"

echo "== G. programming that fails, and programming that leaves prog_done=0"
setup; rc=$(FAKE_PROGRC=1 runscript e1-install.sh)
expect_stop "a non-zero programming status stops install before any probe" 21 program "$rc"
setup; rc=$(FAKE_PROGDONE=0 runscript e1-install.sh)
expect_stop "prog_done=0 after programming stops install before any probe" 21 program "$rc"

echo "== H. a startup gate that exits 0 but prints no marker"
setup; rc=$(FAKE_MARKER_MISSING=ext02_c runscript e1-install.sh)
expect_stop "a gate with rc=0 and no completion marker stops install" 30 gates "$rc"
grep -q "never printed its completion marker" "$OUT/stderr.txt" \
  && ok "  and the refusal says an exit status is not a result" \
  || no "the reason names the marker" "$(tail -1 "$OUT/stderr.txt")"

echo "== I. a transport failure mid-session"
setup; rc=$(FAKE_TRANSPORT_FAIL=xdevcfg runscript e1-install.sh)
expect_stop "a transport failure while programming stops install" 62 program "$rc"

echo "== J. the positive path: install runs to the end and does everything once"
setup; rc=$(runscript e1-install.sh)
if [ "$rc" != 0 ]; then
  no "install completes on a healthy board" "exit $rc: $(tail -2 "$OUT/stderr.txt")"
else
  d=$(n_deploy); p=$(n_program); b=$(n_probe)
  [ "$d" = 12 ] && ok "  12 artefacts deployed (payload, host, 8 gates, 2 perf probes)" || no "deploy count" "got $d, wanted 12"
  [ "$p" = 1 ]  && ok "  the PL is programmed exactly ONCE" || no "program count" "got $p, wanted 1"
  [ "$b" = 18 ] && ok "  18 probe runs (8 gates + 2 probes x 5 samples)" || no "probe count" "got $b, wanted 18"
  grep -q "E1_INSTALL_DONE" "$OUT/stderr.txt" && ok "  and it reports E1_INSTALL_DONE" || no "completion" "no marker"
  ls "$OUT"/session-install-*/samples/perf03_fetch.5.out >/dev/null 2>&1 \
    && ok "  and every sample transcript is on disk" || no "sample transcripts" "missing"
fi

echo "== K. a sample the probe parser rejects is not counted"
setup; rc=$(FAKE_SAMPLE_BAD=perf04_where runscript e1-install.sh)
[ "$rc" = 40 ] && ok "unusable samples are a measurement FAILURE (exit 40), not a pass" \
  || no "sample shortfall" "exit $rc"
grep -q "Restoration is still required" "$OUT/stderr.txt" \
  && ok "  and the refusal says restoration is still required" || no "restore still required" "$(tail -1 "$OUT/stderr.txt")"

echo "== L. restore has the same chain and the same refusals"
setup; rc=$(FAKE_BID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee runscript e1-restore.sh)
expect_stop "an UNCHANGED boot id stops restore too" 10 none "$rc"
setup; rc=$(runscript e1-restore.sh)
if [ "$rc" != 0 ]; then no "restore completes on a healthy board" "exit $rc: $(tail -2 "$OUT/stderr.txt")"
else
  d=$(n_deploy); p=$(n_program); b=$(n_probe)
  [ "$d" = 10 ] && ok "  restore deploys 10 artefacts (payload, host, 8 gates)" || no "restore deploy count" "got $d, wanted 10"
  [ "$p" = 1 ]  && ok "  restore programs the PL exactly once" || no "restore program count" "got $p"
  [ "$b" = 8 ]  && ok "  restore re-runs the 8 gates and no perf samples" || no "restore probe count" "got $b, wanted 8"
  grep -q "E1_RESTORE_DONE" "$OUT/stderr.txt" && ok "  and it reports E1_RESTORE_DONE" || no "completion" "no marker"
fi

echo "== N. the probes are TARGET ELFs and must go through fesvr"
setup; rc=$(runscript e1-install.sh)
[ "$rc" = 0 ] || no "install completes (for the fesvr assertions)" "exit $rc"
# assert the COMMAND, not a count: the stand-in also refuses a bare ./probe.elf, so a regression shows
# up twice -- once as a wrong command here and once as REJECTED-NO-FESVR in the recording.
bare=$(grep -c 'REJECTED-NO-FESVR' "$REC" 2>/dev/null || true)
[ "$bare" = 0 ] && ok "no target ELF was invoked without fesvr" || no "bare ELF invocation" "$bare of them"
want='BOARD cd /root/xv6run && timeout 120 ./fesvr-teaching-static ./boot01_marker.elf 2>&1; echo RC=$?'
grep -qxF "$want" "$REC" && ok "  the gate command is exactly the production form"   || no "gate command form" "recorded: $(grep -m1 'boot01_marker' "$REC")"
want='BOARD cd /root/xv6run && timeout 120 ./fesvr-teaching-static ./perf03_fetch.elf 2>&1; echo RC=$?'
grep -qxF "$want" "$REC" && ok "  the perf command is exactly the production form"   || no "perf command form" "recorded: $(grep -m1 'perf03_fetch' "$REC")"
n=$(grep -c 'fesvr-teaching-static \./' "$REC" 2>/dev/null || true)
[ "$n" = 18 ] && ok "  all 18 probe runs went through fesvr" || no "fesvr count" "got $n, wanted 18"

echo "== O. with the bound disabled the command is still a command"
setup; rc=$(E1_TIMEOUT= runscript e1-install.sh)
[ "$rc" = 0 ] && ok "install completes with E1_TIMEOUT empty" || no "empty E1_TIMEOUT" "exit $rc: $(tail -1 "$OUT/stderr.txt")"
want='BOARD cd /root/xv6run && ./fesvr-teaching-static ./boot01_marker.elf 2>&1; echo RC=$?'
grep -qxF "$want" "$REC" && ok "  and carries no stray numeric argument where the program belongs"   || no "empty-timeout command form" "recorded: $(grep -m1 'BOARD.*boot01_marker' "$REC")"
bare=$(grep -c 'REJECTED-NO-FESVR' "$REC" 2>/dev/null || true)
[ "$bare" = 0 ] && ok "  and still goes through fesvr" || no "fesvr with empty timeout" "$bare bare invocations"

echo "== M. leases are released on every path, and only ours"
setup; rc=$(FAKE_BID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee runscript e1-install.sh)
rel=$(grep -c '^COORD release' "$REC" 2>/dev/null || echo 0)
[ "$rel" = 2 ] && ok "a refused session still releases both leases it claimed" || no "release on refusal" "released $rel"
setup; rc=$(FAKE_CLAIM_DENY=serial runscript e1-install.sh)
rel=$(grep -c '^COORD release' "$REC" 2>/dev/null || echo 0)
[ "$rel" = 1 ] && ok "a partial claim releases only the lease actually held" || no "partial claim release" "released $rel, wanted 1"

echo "E1_ENTRYPOINT_REHEARSAL pass=$npass fail=$nfail"
exit $([ $nfail -eq 0 ] && echo 0 || echo 1)
