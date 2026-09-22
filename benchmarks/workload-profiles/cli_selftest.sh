#!/usr/bin/env bash
# The workload-profile delta exercised through the ACTUAL production entry, against a real PTY board.
#
# Two things the transcript-level tests cannot show:
#   * an unknown workload name must be refused BEFORE anything is constructed -- no transport, no lease,
#     no remote command, no host. Proven by a recording transport that logs every invocation: it must
#     stay empty.
#   * a b0apps run must go driver -> board -> checker end to end, not merely check a synthesized file.
#
# The patch is applied to a scratch copy; the repository's frozen tools are untouched.
#
#   cli_selftest.sh <fresh dir>
set -u
set -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/../.." && pwd)
out=${1:?usage: cli_selftest.sh <fresh dir>}
[ -e "$out" ] && { echo "REFUSE: $out exists"; exit 2; }
mkdir -p "$out"

pass=0; fail=0
ok() { pass=$((pass+1)); echo "  ok   : $1"; }
no() { fail=$((fail+1)); echo "  FAIL : $1 -- $2"; }

PROD_LOCK=/var/lock/teaching-fesvr.lock
[ -e "$PROD_LOCK" ] && { echo "REFUSE: $PROD_LOCK exists; not touching it"; exit 2; }
BOARDPID=""; cleanup() {
  [ -n "$BOARDPID" ] && kill "$BOARDPID" 2>/dev/null
  rm -f "$PROD_LOCK"/owner "$PROD_LOCK"/pid "$PROD_LOCK"/exit 2>/dev/null
  rmdir "$PROD_LOCK" 2>/dev/null; return 0; }
trap cleanup EXIT

# ---- the patched copy
mod="$out/mod"; mkdir -p "$mod"
for f in tools/xv6-boot/scripts/xv6_console.py tools/xv6-boot/scripts/check-xv6.py \
         tools/board/scripts/board_run.py tools/board/scripts/board-runner.py; do
  mkdir -p "$mod/$(dirname $f)"; cp "$ROOT/$f" "$mod/$f"
done
# the unpatched siblings the patched files import
for f in tools/board/scripts/transport.py tools/board/scripts/board_gate.py \
         tools/board/scripts/mem-preflight.py tools/xv6-boot/scripts/fakesim.py; do
  cp "$ROOT/$f" "$mod/$f" 2>/dev/null || true
done
patch -p1 -s -d "$mod" -i "$here/xv6-workload-profiles.patch" || { echo "  patch failed"; exit 2; }
ok "the patch applies to a scratch copy"
RUNNER="$mod/tools/board/scripts/board-runner.py"
CHECKER="$mod/tools/xv6-boot/scripts/check-xv6.py"

BIT=2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52
BOOT=$(cat /proc/sys/kernel/random/boot_id)

# ---- a transport that RECORDS every invocation and then refuses to do anything
cat > "$out/recorder.sh" <<EOS
#!/bin/sh
printf '%s\n' "\$*" >> "$out/issued.txt"
exit 1
EOS
chmod +x "$out/recorder.sh"

echo "== 1. an unknown workload is refused before ANYTHING is constructed"
rm -f "$out/issued.txt"
python3 "$RUNNER" "$out/run-bad" --transport-cmd "$out/recorder.sh" --channel multiplexed \
  --host-binary /x/h --kernel /x/k --disk /x/d --evidence-dir /x/e \
  --expect /x/h=$(printf 'a%.0s' $(seq 64)) --bitstream-sha $BIT \
  --workload definitely-not-a-profile > "$out/bad.txt" 2>&1
rc=$?
[ $rc = 2 ] && ok "the production CLI exits 2" || no "the production CLI exits 2" "exit $rc"
grep -q "REFUSE" "$out/bad.txt" && ok "  and refuses rather than raising" \
  || no "  and refuses rather than raising" "$(head -2 $out/bad.txt | tr '\n' ' ')"
grep -q "unknown workload profile" "$out/bad.txt" && ok "  naming the offending profile" \
  || no "  naming the offending profile" "$(head -2 $out/bad.txt | tr '\n' ' ')"
! grep -q "Traceback" "$out/bad.txt" && ok "  with no traceback" || no "  with no traceback" "it raised"
[ ! -s "$out/issued.txt" ] && ok "  ZERO remote or host calls were made" \
  || no "  ZERO remote or host calls were made" "$(wc -l < $out/issued.txt) invocation(s): $(head -1 $out/issued.txt)"
[ ! -d "$PROD_LOCK" ] && ok "  and no lock was taken" || no "  and no lock was taken" "a lock exists"
[ ! -d "$out/run-bad" ] && ok "  and no output directory was created" \
  || no "  and no output directory was created" "it exists"

echo "== 2. the default is still refused nothing and still works: unknown name only"
rm -f "$out/issued.txt"
python3 "$RUNNER" "$out/run-def" --transport-cmd "$out/recorder.sh" --channel multiplexed \
  --host-binary /x/h --kernel /x/k --disk /x/d --evidence-dir /x/e \
  --expect /x/h=$(printf 'a%.0s' $(seq 64)) --bitstream-sha $BIT > "$out/def.txt" 2>&1
grep -q "unknown workload profile" "$out/def.txt" && no "an unnamed run is not refused as unknown" "it was" \
  || ok "an unnamed run is not refused as unknown (it proceeds and fails later, on the fake transport)"

# ---- a real PTY board running the b0 fake host
board_up() {
  ST="$out/$1"; mkdir -p "$ST/root"
  python3 "$ROOT/tools/board/scripts/real_pty_board.py" "$ST" --host-mode normal > "$ST/dev" 2>"$ST/b.log" &
  BOARDPID=$!
  for _ in $(seq 1 50); do [ -s "$ST/dev" ] && break; sleep 0.2; done
  DEV=$(cat "$ST/dev")
  cat > "$ST/root/fesvr-teaching-static" <<EOS
#!/bin/sh
exec env TEACHING_B0_MODE=${2:-ok} TEACHING_FAKE_STATE="$ST" python3 "$here/fake_b0_host.py"
EOS
  chmod +x "$ST/root/fesvr-teaching-static"
  printf 'kernel\n' > "$ST/root/kernel-128mib"; printf 'disk\n' > "$ST/root/fs-run.img"
  H=$(sha256sum "$ST/root/fesvr-teaching-static" | cut -d' ' -f1)
  K=$(sha256sum "$ST/root/kernel-128mib" | cut -d' ' -f1)
  D=$(sha256sum "$ST/root/fs-run.img" | cut -d' ' -f1)
}
board_down() { kill "$BOARDPID" 2>/dev/null; wait "$BOARDPID" 2>/dev/null; BOARDPID=""; }

python3 "$ROOT/tools/board/scripts/make-mem-fixtures.py" "$out/fixtures" >/dev/null
printf '%s\0' "$BOOT" > "$out/fixtures/safe-256/session-id"

RUNRC=0
run_b0() {   # run_b0 <outdir> <mode>; sets RUNRC and leaves ST pointing at the board's state dir
  board_up "board-$2" "$2"
  python3 "$RUNNER" "$1" \
    --transport-cmd "python3 $ROOT/tools/xv6-board-run/scripts/serial-transport.py --device $DEV" \
    --channel exclusive --serial-device "$DEV" \
    --host-binary "$ST/root/fesvr-teaching-static" --kernel "$ST/root/kernel-128mib" \
    --disk "$ST/root/fs-run.img" --evidence-dir "$out/fixtures/safe-256" \
    --expect "$ST/root/fesvr-teaching-static=$H" --expect "$ST/root/kernel-128mib=$K" \
    --expect "$ST/root/fs-run.img=$D" --bitstream-sha $BIT --workload b0apps \
    --stage-timeout 25 --startup-timeout 25 --stop-timeout 15 > "$1.txt" 2>&1
  RUNRC=$?
}

echo "== 3. driver -> board -> checker, end to end"
run_b0 "$out/run-b0" ok; rc=$RUNRC
[ "$rc" = 0 ] && ok "the b0apps run completes through the production CLI" \
  || no "the b0apps run completes through the production CLI" "exit $rc: $(tail -1 $out/run-b0.txt)"
grep -qx '# workload: b0apps' "$out/run-b0/stages.txt" 2>/dev/null && ok "  the record names the workload" \
  || no "  the record names the workload" "$(grep '^# workload' $out/run-b0/stages.txt 2>/dev/null || echo absent)"
[ "$(grep -c '^ok' "$out/run-b0/stages.txt" 2>/dev/null)" = 6 ] && ok "  six stages ok (three boot, three commands)" \
  || no "  six stages ok" "$(grep -c '^ok' $out/run-b0/stages.txt 2>/dev/null) ok"
printf '%s\n' b0compute b0array b0file > "$out/want-stdin.txt"
diff -q "$out/want-stdin.txt" "$ST/host-stdin.txt" >/dev/null 2>&1 \
  && ok "  the host received exactly the three commands, in order" \
  || no "  the host received exactly the three commands, in order" "$(tr '\n' ' ' < $ST/host-stdin.txt)"
python3 "$CHECKER" "$out/run-b0" --require-commands > "$out/check-b0.txt" 2>&1 \
  && ok "  and the patched CHECKER accepts the real transcript" \
  || no "  and the patched CHECKER accepts the real transcript" "$(tail -2 $out/check-b0.txt | tr '\n' ' ')"
board_down

echo "== 4. a real run with a wrong checksum is caught, not merely reported"
run_b0 "$out/run-wrong" wrong-sum; rc=$RUNRC
[ "$rc" != 0 ] && ok "a wrong checksum from the board fails the run" || no "a wrong checksum fails the run" "exit 0"
python3 "$CHECKER" "$out/run-wrong" --require-commands > "$out/check-wrong.txt" 2>&1 \
  && no "  and the checker refuses it" "it accepted" || ok "  and the checker refuses it"
board_down

echo "== 5. duplicate workload headers are refused, not resolved to the first"
cp -r "$out/run-b0" "$out/run-dup"
printf '# workload: default\n' >> "$out/run-dup/stages.txt"
python3 "$CHECKER" "$out/run-dup" --require-commands > "$out/check-dup.txt" 2>&1 \
  && no "two conflicting workload headers are refused" "it accepted" \
  || { grep -q "workload headers" "$out/check-dup.txt" && ok "two conflicting workload headers are refused" \
       || no "two conflicting workload headers are refused" "refused for another reason: $(tail -2 $out/check-dup.txt|tr '\n' ' ')"; }

echo "CLI_PROFILE_SELFTEST pass=$pass fail=$fail"
[ "$fail" = 0 ]
