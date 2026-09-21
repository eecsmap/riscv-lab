#!/usr/bin/env bash
# Integration test for scripts/xv6-drive.py and scripts/check-xv6.py against a fake simulator.
# It proves four properties the real (hours-long) run cannot cheaply be used to prove:
#   1. console newlines survive, including empty lines and lines cut in half by an event line;
#   2. output produced at the moment the simulator goes down is still captured (drain to EOF);
#   3. a failed command stops the driver -- the later commands are never typed;
#   4. the checker's verdict follows the *values* of the ending record, not merely its presence.
# It writes only into the directory given as $1, and refuses to touch one that already exists.
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: drive-selftest.sh <fresh output dir>}
[ -e "$out" ] && { echo "refusing to write into existing $out"; exit 2; }
mkdir -p "$out"
DRIVE="$here/xv6-drive.py"; CHECK="$here/check-xv6.py"; FAKE="$here/fakesim.py"
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "  ok   : $1"; }
no()   { fail=$((fail+1)); echo "  FAIL : $1"; }
want() { if eval "$2"; then ok "$1"; else no "$1"; fi; }

run() {  # run <name> <mode>
  local d="$out/$1"; mkdir -p "$d"
  FAKESIM_MODE="$2" FAKESIM_INPUT_LOG="$d/typed.txt" \
    python3 "$DRIVE" "$FAKE" /dev/null /dev/null "$d" --stage-timeout 25 >"$d/drive.out" 2>&1
  echo $? > "$d/drive.rc"
}

echo "== 1. a healthy run"
run good ok
d=$out/good
want "driver exits 0"                    "[ \$(cat $d/drive.rc) = 0 ]"
want "console keeps the banner as its own line"   "grep -qx 'xv6 kernel is booting' $d/console.txt"
want "console keeps an empty line"       "grep -qcx '' $d/console.txt >/dev/null && [ \$(grep -cx '' $d/console.txt) -ge 1 ]"
want "console excludes event text"       "! grep -q 'EVH \|RD2 ' $d/console.txt"
want "tail written at SIGTERM is drained" "grep -q 'SIMTAIL cycles=' $d/console.txt"
want "run.log kept the raw stream"       "grep -q 'EVH ' $d/run.log"
want "driver version recorded"           "grep -qx '# driver: v3' $d/stages.txt"
want "ending is the deliberate stop"     "grep -qx '# stop: deliberate-stop-after-all-commands' $d/stages.txt"
want "all four commands were typed"      "[ \$(wc -l < $d/typed.txt) = 4 ]"
want "ls output is attributed to ls, not to the ls entry inside its own listing" \
     "grep -q 'README' $d/console.txt && grep -qE '^ls +2 ' $d/console.txt && grep -qP '^ok\t.*command ls$' $d/stages.txt"
want "checker accepts it"                "python3 $CHECK $d --require-commands >$d/check.out 2>&1"

echo "== 2. a command that fails"
run badls fail-ls
d=$out/badls
want "driver exits 1"                    "[ \$(cat $d/drive.rc) = 1 ]"
want "only echo and ls were ever typed"  "[ \$(wc -l < $d/typed.txt) = 2 ] && grep -qx 'ls' $d/typed.txt && ! grep -q 'cat README' $d/typed.txt"
want "ending names the failed command"   "grep -qx '# stop: stopped-after-failed-command:ls' $d/stages.txt"
want "checker rejects it"                "! python3 $CHECK $d --require-commands >$d/check.out 2>&1"
want "and says why"                      "grep -q 'command ls' $d/check.out"

echo "== 3. a simulator that dies on its own"
run died exit-midway
d=$out/died
want "driver exits 1"                    "[ \$(cat $d/drive.rc) = 1 ]"
want "output written just before exit is drained" "grep -q 'SIMTAIL died after 2 commands' $d/console.txt"
want "ending reports the unexpected exit" "grep -q '# stop: simulator-exited' $d/stages.txt"
want "checker rejects it"                "! python3 $CHECK $d --require-commands >$d/check.out 2>&1"

echo "== 4. a passing console with a failed ending (the checker must not be fooled)"
for v in 'simulator-exited-on-its-own:0' '' 'something-else' 'stopped-after-failed-command:pipe'; do
  d=$out/ending-$(echo "${v:-empty}" | tr -c 'a-z0-9' '-'); cp -r "$out/good" "$d"
  sed -i "s|^# stop: .*|# stop: $v|" "$d/stages.txt"
  want "rejected: stop='$v' with an otherwise passing console" \
       "! python3 $CHECK $d --require-commands >$d/check.out 2>&1"
done
d=$out/ending-exit-status; cp -r "$out/good" "$d"
sed -i 's|^# simulator exit: .*|# simulator exit: 134|' "$d/stages.txt"
want "rejected: crash exit status with a passing console" "! python3 $CHECK $d --require-commands >$d/check.out 2>&1"
d=$out/ending-sigkill; cp -r "$out/good" "$d"
sed -i 's|^# signalled: .*|# signalled: SIGKILL|' "$d/stages.txt"
want "rejected: the simulator had to be SIGKILLed" "! python3 $CHECK $d --require-commands >$d/check.out 2>&1"
d=$out/ending-old-driver; cp -r "$out/good" "$d"
sed -i 's|^# driver: .*|# driver: v1|' "$d/stages.txt"
want "rejected: transcript from an older driver" "! python3 $CHECK $d --require-commands >$d/check.out 2>&1"
d=$out/ending-deliberate-but-failed; cp -r "$out/good" "$d"
sed -i '0,/^ok\tcommand ls/s||FAILED\tcommand ls|' "$d/stages.txt" 2>/dev/null
sed -i 's|^ok\(.*command ls\)|FAILED\1|' "$d/stages.txt"
want "rejected: labelled a deliberate stop but a stage failed" "! python3 $CHECK $d --require-commands >$d/check.out 2>&1"

echo "DRIVE_SELFTEST pass=$pass fail=$fail"
[ "$fail" = 0 ]
