#!/usr/bin/env bash
# The memory preflight must accept exactly one kind of machine and refuse everything else, with a reason.
# A preflight that only ever passes is worth nothing, so every refusal case below has to refuse *and* has
# to say the right thing.
#
#   mem-preflight-selftest.sh <fresh output dir>
set -u
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: mem-preflight-selftest.sh <fresh dir>}
[ -e "$out" ] && { echo "REFUSE: $out exists"; exit 2; }
mkdir -p "$out"
PRE="$here/mem-preflight.py"
SESSION=6f1d0a3c-2b47-4e18-9f55-1c0de7a94b21
python3 "$here/make-mem-fixtures.py" "$out/fixtures" >/dev/null || exit 2

pass=0; fail=0
ok() { pass=$((pass+1)); printf "  ok   : %s\n" "$1"; }
no() { fail=$((fail+1)); printf "  FAIL : %s -- %s\n" "$1" "$2"; }

accept() {  # accept <case> <description>
  if python3 "$PRE" "$out/fixtures/$1" --expect-session "$SESSION" > "$out/$1.txt" 2>&1; then
    ok "$2"
  else
    no "$2" "it refused: $(grep -m1 REFUSE "$out/$1.txt" | cut -c1-90)"
  fi
}

reject() {  # reject <case> <regex the reason must match> <description>
  if python3 "$PRE" "$out/fixtures/$1" --expect-session "$SESSION" > "$out/$1.txt" 2>&1; then
    no "$3" "it was ACCEPTED"
  elif grep -qE "$2" "$out/$1.txt"; then
    ok "$3"
  else
    no "$3" "refused for another reason: $(grep -m1 REFUSE "$out/$1.txt" | cut -c1-90)"
  fi
}

echo "== the one machine that may proceed"
accept safe-256        "a machine with Linux in the low 256 MiB is accepted"
accept safe-256-2cell  "the same machine described with 2-cell addresses is also accepted"

echo "== everything else is refused, for the right reason"
reject unsafe-512              "overlaps the teaching CPU's window|more than the low half" \
       "512 MiB to Linux is refused -- this is the recorded incident"
reject overlapping-reservation "reserved region .* overlaps"  \
       "a reserved region reaching into the target window is refused"
reject malformed               "not a whole number of|cell widths"  \
       "a reg blob that is not a whole number of tuples is refused"
reject changed-session         "belongs to session|rebooted"  \
       "evidence from a different boot is refused"
reject redacted                "redacted or elided"  \
       "a hand-edited capture is refused"
reject inconsistent            "disagree|inside the teaching"  \
       "a device tree and /proc/iomem that disagree are refused"
reject reserved-name-only      "a name alone is not"  \
       "a reserved-memory name with no reg is refused"

echo "== the NUL boundary: a terminator is tolerated, corruption is not"
accept nul-terminated-session "a boot id with ONE trailing NUL is accepted (this is what the board sends)"
reject nul-embedded-session  "embedded NUL|not a boot-id UUID" \
       "a NUL *inside* the boot id is refused, not scrubbed"
reject nul-in-iomem          "embedded NUL" \
       "a NUL inside /proc/iomem is refused -- corruption must not be normalised away"
reject malformed-session     "not a boot-id UUID" "a session id that is not a UUID is refused"
reject truncated-session     "not a boot-id UUID" "a truncated session id is refused"

echo "== missing evidence is a refusal, not a default"
for f in session-id dt/memory-reg dt/address-cells proc-iomem proc-meminfo; do
  d="$out/fixtures/missing-$(echo $f | tr / -)"
  cp -r "$out/fixtures/safe-256" "$d"; rm -f "$d/$f"
  if python3 "$PRE" "$d" --expect-session "$SESSION" > "$d.txt" 2>&1; then
    no "missing $f is refused" "it was ACCEPTED"
  else ok "missing $f is refused"; fi
done

echo "MEM_PREFLIGHT_SELFTEST pass=$pass fail=$fail"
[ "$fail" = 0 ]
