#!/usr/bin/env bash
# Run this BEFORE the user powers the board down.
#
# It pins the CURRENT boot id to a file. The install and restore sessions then prove a power cycle by
# comparing against that recorded value. Without this, "the boot id changed" has nothing to change from,
# and the cold-cycle gate degenerates into taking someone's word for it.
set -u
cd "$(dirname "$0")"; . ./lib-e1.sh; . ./artefacts.sh
O=$R/riscv-lab/experiments/E1-clock-scaling; mkdir -p $O/state
PIN=$O/state/${1:?usage: e1-precycle.sh <phase: install|restore>}-pin.txt

# Every local artefact, checked BEFORE the user is asked to power anything down. A missing file or a
# wrong hash found at this point costs nothing; found after the power cycle it costs a cold cycle of
# somebody's time and leaves the board holding whichever bitstream it happens to hold.
say "== local artefacts"
bad=0
check() { local f=$1 want=${2:-}
    if [ ! -f "$f" ]; then say "  MISSING : $f"; bad=1; return; fi
    if [ -n "$want" ]; then local g; g=$(sha256sum "$f" | cut -d' ' -f1)
        if [ "$g" != "$want" ]; then say "  WRONG HASH: $f = ${g:0:16}… wanted ${want:0:16}…"; bad=1; return; fi
        say "  ok (hash) : $f"; else say "  ok        : $f"; fi
}
check "$E1_PAYLOAD"        "$E1_PAYLOAD_SHA"
check "$ACCEPTED_PAYLOAD"  "$ACCEPTED_PAYLOAD_SHA"
check "$HOSTBIN"
check "$SEND"
for f in $GATES $PERF_PROBES; do check "$(elf_path $f)"; done
[ $bad -eq 0 ] || die $EX_HASH "local artefacts are not ready; fix these BEFORE any power cycle"
say "  all local artefacts present and the two payloads hash correctly"

say "== the board's timeout builtin (the probes are run bounded)"
# NOT grep -oE 'HAVE|NONE': the shim echoes the command, so both words are already in the output and a
# first-match parse reads the question instead of the answer. Every parse here is "last KEY=value".
t=$(board "echo TMO=\$(command -v timeout >/dev/null && echo yes || echo no)" | sed -n 's/^TMO=//p' | tail -1)
if [ "$t" = yes ]; then say "  the board has timeout; probes will be bounded on the board as well as here"
else say "  the board has NO timeout: set E1_TIMEOUT='' and rely on the host-side bound"; fi

say "== pinning the current boot id"
bid=$(board "cat /proc/sys/kernel/random/boot_id" | grep -oE '^[0-9a-f-]{36}$' | tail -1)
[ -n "$bid" ] || die $EX_PIN "could not read the current boot id; refusing to pin an empty value"
printf '%s\n' "$bid" > "$PIN"
say "pinned pre-cycle boot id for phase '$1': $bid"
say "  -> $PIN"
say "NOW the user may power the board down and up. Nothing else here touches the board."
