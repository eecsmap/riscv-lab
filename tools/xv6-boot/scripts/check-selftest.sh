#!/usr/bin/env bash
# The checker must refuse a run that is missing its key evidence. Two of these cases are Codex's
# counterexample (CODEX_CHECKER_FINDING.md): a transcript whose pipe command produced nothing but where an
# earlier `ls` printed three numbers, and a run with no stage record at all. Those two are synthetic and
# need no passing run; the mutation cases need one and are skipped with a note when none is given.
#   check-selftest.sh <outdir> [good rundir]
set -u; HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?outdir}; GOOD=${2:-}
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists -- give a fresh output directory"; exit 2; }
mkdir -p "$OUT"
fails=0

mkdir_case() { [ -e "$OUT/$1" ] && { echo "  $1: REFUSE, exists"; fails=$((fails+1)); return 1; }; mkdir -p "$OUT/$1"; }

# ---- synthetic negatives, always run
mkdir_case wc-missing-ls-numbers && {
  printf 'xv6 kernel is booting\ninit: starting sh\n$ echo teaching-xv6-hello\nteaching-xv6-hello\n$ ls\nREADME         2 2 2441\n$ cat README\nxv6 is a re-implementation\n$ echo abc | wc\n$ ' > $OUT/wc-missing-ls-numbers/console.txt
  printf 'ok\t1\tkernel banner\nok\t2\tinit started / first prompt\nok\t3\tshell prompt\nok\t4\tcommand echo\nok\t5\tcommand ls\nok\t6\tcommand cat\nok\t7\tcommand pipe\n# driver: v2\n# simulator exit: 0\n# stop: deliberate-stop-after-all-commands\n' > $OUT/wc-missing-ls-numbers/stages.txt
  python3 $HERE/check-xv6.py $OUT/wc-missing-ls-numbers --require-commands > $OUT/wc-missing-ls-numbers.txt 2>&1
  if [ $? -eq 0 ]; then echo "  wc-missing-ls-numbers  NOT REJECTED"; fails=$((fails+1))
  elif grep -q "command pipe" $OUT/wc-missing-ls-numbers.txt; then echo "  wc-missing-ls-numbers  rejected: $(grep -m1 FAIL $OUT/wc-missing-ls-numbers.txt | cut -c1-80)"
  else echo "  wc-missing-ls-numbers  rejected for another reason"; fails=$((fails+1)); fi; }

mkdir_case stages-missing && {
  cp $OUT/wc-missing-ls-numbers/console.txt $OUT/stages-missing/console.txt 2>/dev/null
  printf 'xv6 kernel is booting\ninit: starting sh\n$ echo teaching-xv6-hello\nteaching-xv6-hello\n$ ls\nREADME         2 2 2441\n$ cat README\nxv6 is a re-implementation\n$ echo abc | wc\n      1       1       4\n$ ' > $OUT/stages-missing/console.txt
  python3 $HERE/check-xv6.py $OUT/stages-missing --require-commands > $OUT/stages-missing.txt 2>&1
  if [ $? -eq 0 ]; then echo "  stages-missing         NOT REJECTED"; fails=$((fails+1))
  elif grep -q "no stages.txt" $OUT/stages-missing.txt; then echo "  stages-missing         rejected: $(grep -m1 FAIL $OUT/stages-missing.txt | cut -c1-80)"
  else echo "  stages-missing         rejected for another reason"; fails=$((fails+1)); fi; }

# the same transcript *with* a complete stage record must pass: otherwise the two cases above prove nothing
mkdir_case complete-control && {
  cp $OUT/stages-missing/console.txt $OUT/complete-control/console.txt
  cp $OUT/wc-missing-ls-numbers/stages.txt $OUT/complete-control/stages.txt
  python3 $HERE/check-xv6.py $OUT/complete-control --require-commands > $OUT/complete-control.txt 2>&1
  if [ $? -eq 0 ]; then echo "  complete-control       passes, as it must"
  else echo "  complete-control       FAILED: $(grep -m1 FAIL $OUT/complete-control.txt | cut -c1-90)"; fails=$((fails+1)); fi; }

# ---- mutations of a genuine passing run, when one is given
if [ -n "$GOOD" ]; then
  python3 $HERE/check-xv6.py "$GOOD" --require-commands > $OUT/good.txt 2>&1 || {
    echo "  the given run does not pass, so its mutations prove nothing: $(tail -1 $OUT/good.txt)"; fails=$((fails+1)); }
  mut() { local name=$1 sig=$2 kind=$3
    mkdir_case $name || return
    cp "$GOOD/stages.txt" $OUT/$name/ 2>/dev/null
    python3 - "$GOOD/console.txt" "$OUT/$name/console.txt" "$kind" <<'PY'
import sys
src, dst, kind = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(src, errors='replace').read()
if kind == 'no-banner': t = t.replace('xv6 kernel is booting', '')
if kind == 'no-prompt': t = t.replace('$ ', '')
if kind == 'no-cat-output':
    i = t.find('cat README')
    if i >= 0:
        j = t.find('$ ', i)
        t = t[:i] + 'cat README\n' + (t[j:] if j > 0 else '')
open(dst, 'w').write(t)
PY
    python3 $HERE/check-xv6.py $OUT/$name --require-commands > $OUT/$name.txt 2>&1
    if [ $? -eq 0 ]; then printf "  %-22s NOT REJECTED\n" $name; fails=$((fails+1))
    elif grep -qE "$sig" $OUT/$name.txt; then printf "  %-22s rejected: %s\n" $name "$(grep -m1 FAIL $OUT/$name.txt | cut -c1-70)"
    else printf "  %-22s rejected for another reason\n" $name; fails=$((fails+1)); fi; }
  mut no-banner      "no kernel banner"  no-banner
  mut no-prompt      "no shell prompt"   no-prompt
  mut no-cat-output  "command cat"       no-cat-output
else
  echo "  (no passing run given: the mutation cases are skipped, the synthetic ones above still ran)"
fi
echo "XV6_SELFTEST_DONE fails=$fails"; [ $fails -eq 0 ]
