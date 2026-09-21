#!/usr/bin/env bash
# Freeze the identity of a finished xv6 run: what went in, what came out, and how it ended.
# A run's console is only evidence if the disk it started from, the binaries that produced it, and the
# recorded ending can all be named by hash. Refuses to run while the driver is still writing.
#   archive-run.sh <rundir> <disk image the run used> <initial disk sha256>
set -u
ROOT=/home/engineer/fpga; cd "$ROOT" || exit 2
R=experiments/teaching-cpu/xv6-boot
RUN=${1:?rundir}; DISK=${2:?disk image}; INIT=${3:?initial disk sha256}
name=$(basename "$RUN")
if ps -eo args= | grep -F 'xv6-drive.py' | grep -v grep | grep -qF "$name"; then
  echo "REFUSE: a driver is still writing $name"; exit 3; fi
OUT=$RUN/IDENTITY.md
[ -e "$OUT" ] && { echo "REFUSE: $OUT exists -- archived evidence is not overwritten"; exit 3; }
h() { sha256sum "$1" | cut -d' ' -f1; }
{
  echo "# Identity of $name"
  echo
  echo "Archived $(date -Iseconds). The console in this directory is evidence only together with these."
  echo
  echo '## What went in'
  echo
  echo "| artefact | sha256 |"
  echo "| --- | --- |"
  # Prefer the identities the driver recorded when it started. Hashing the sources now would describe
  # whatever they have since become, not what produced this transcript.
  rec=$(grep -c ' sha256: ' "$RUN/stages.txt" || true)
  if [ "$rec" -gt 0 ]; then
    python3 -c "
import sys
for ln in open(sys.argv[1]):
    if ln.startswith('# ') and ' sha256: ' in ln:
        name, h = ln[2:].rstrip('\n').split(' sha256: ', 1)
        print('| %s | \`%s\` |' % (name, h))
" "$RUN/stages.txt"
    echo "| disk image, pristine (checked independently of the run) | \`$INIT\` |"
  else
    echo "| disk image, as the run started (pristine) | \`$INIT\` |"
    echo "| kernel | \`$(h $R/evidence/kernel-4mib)\` |"
    echo "| simulator | \`$(h $R/sim-boot3/obj_dir/sim)\` |"
    echo
    echo "**This run predates the driver recording its own identity.** The driver and checker sources have"
    echo "been edited since it ran, so their current hashes would not describe what produced this"
    echo "transcript and are deliberately not listed. The driver version is \`$(grep -m1 '^# driver:' "$RUN/stages.txt" | cut -d' ' -f3)\`."
  fi
  echo
  echo '## What came out'
  echo
  echo "| artefact | sha256 |"
  echo "| --- | --- |"
  echo "| disk image, after the run | \`$(h $DISK)\` |"
  echo "| console.txt | \`$(h $RUN/console.txt)\` |"
  echo "| run.log (raw stream, events included) | \`$(h $RUN/run.log)\` |"
  echo "| stages.txt | \`$(h $RUN/stages.txt)\` |"
  now=$(h "$DISK")
  if [ "$now" = "$INIT" ]; then echo; echo "The disk is unchanged from the pristine image."
  else echo; echo "The disk differs from the pristine image, as it must: the run wrote to it."; fi
  echo
  echo '## How it ended'
  echo
  echo '```'
  cat "$RUN/stages.txt"
  echo '```'
  echo
  echo '## The commands, in order, with their own output'
  echo
  echo '```'
  sed -n '/\$ /,$p' "$RUN/console.txt"
  echo '```'
} > "$OUT"
echo "wrote $OUT"
