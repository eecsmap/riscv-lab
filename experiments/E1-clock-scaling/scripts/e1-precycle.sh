#!/usr/bin/env bash
# Run this BEFORE the user powers the board down.
#
# Checks every local artefact first -- a missing file found here costs nothing, found after the power
# cycle it costs a cold cycle of somebody's time -- then pins the CURRENT boot id to a file.
#
# Leases are claimed BEFORE any transport call, including this one.
set -euo pipefail
cd "$(dirname "$0")"; . ./lib-e1.sh; . ./artefacts.sh
O=${E1_OUT:-$R/riscv-lab/experiments/E1-clock-scaling}; mkdir -p $O/state
phase=${1:?usage: e1-precycle.sh <install|restore>}
PIN=$O/state/$phase-pin.txt
trap release_owned_leases EXIT

say "== local artefacts"
bad=0
check() { local f=$1 want=${2:-} g
    if [ ! -f "$f" ]; then say "  MISSING : $f"; bad=1; return 0; fi
    if [ -n "$want" ]; then g=$(sha256sum "$f" | cut -d' ' -f1)
        if [ "$g" != "$want" ]; then say "  WRONG HASH: $f = ${g:0:16}… wanted ${want:0:16}…"; bad=1; return 0; fi
        say "  ok (hash) : $f"; else say "  ok        : $f"; fi
}
check "$E1_PAYLOAD"        "$E1_PAYLOAD_SHA"
check "$ACCEPTED_PAYLOAD"  "$ACCEPTED_PAYLOAD_SHA"
check "$HOSTBIN"           "$HOSTBIN_SHA"
check "$SEND"
[ -s markers.tsv ] || { say "  MISSING : markers.tsv (run gen-markers.sh)"; bad=1; }

say "== probe identities, against the recorded ones"
# Codex: "unchanged host/probe identities". markers.tsv records each probe's sha256 alongside its
# completion marker, both read out of the ELF itself, so a rebuilt probe shows up here rather than on
# the board.
for f in $GATES $PERF_PROBES; do
    want=$(awk -v p="$f" '$1==p {print $3}' markers.tsv)
    if [ -z "$want" ]; then say "  NO RECORD : $f is not in markers.tsv"; bad=1; continue; fi
    check "$(elf_path "$f")" "$want"
done
[ $bad -eq 0 ] || die $EX_HASH "local artefacts are not ready; fix these BEFORE any power cycle"
say "  all local artefacts present and the two payloads hash correctly"

say "== leases, before any transport"
claim_leases board serial

say "== the board's timeout builtin (the probes are run bounded)"
board_must "probing for timeout" "echo TMO=\$(command -v timeout >/dev/null && echo yes || echo no)"
# RECORDED, not just reported. This board has no `timeout` builtin, so the default
# E1_TIMEOUT="timeout " would build `timeout 120 ./fesvr-teaching-static ...` and every probe would die
# with "timeout: not found" -- inside the user's power-cycle window, where remembering to set a variable
# is the wrong place for this to live.
TMO=$(field TMO)
printf '%s\n' "${TMO:-unknown}" > "$O/state/$phase-timeout.txt"
if [ "$TMO" = yes ]; then say "  the board HAS timeout; probes are bounded on the board as well as here"
elif [ "$TMO" = no ]; then say "  the board has NO timeout; recorded, and the session will rely on the host-side bound"
else die $EX_TRANSPORT "could not determine whether the board has 'timeout' (got '${TMO:-<none>}')"; fi
say "  -> $O/state/$phase-timeout.txt"

say "== pinning the current boot id"
board_must "reading the boot id" "cat /proc/sys/kernel/random/boot_id"
bid=$(tr -d '\r' <<<"$BOARD_OUT" | grep -oE '^[0-9a-f-]{36}$' | tail -1 || true)
[ -n "$bid" ] || die $EX_PIN "could not read the current boot id; refusing to pin an empty value"
printf '%s\n' "$bid" > "$PIN"
say "pinned pre-cycle boot id for phase '$phase': $bid"
say "  -> $PIN"
say ""
say "NOW: the user physically removes power, restores it, and runs:"
say "    ./e1-record-power-cycle.sh $phase"
say "Then run e1-$( [ "$phase" = install ] && echo install || echo restore ).sh"
