# PIPE-P4c: the dual-pipeline board session library. An ISOLATED adaptation of the P3b p3b-lib.sh and the M5 m5-lib.sh.
# It sources its own copy of the E1 library (./lib = a VERBATIM copy of the accepted MC-M5 dual library: the six
# dual-hart startup gates; LIB-DIFF.txt): the cold-cycle gate and its pin, the power-removal attestation, leases,
# memory evidence + production preflight, on-board hash verification, the programming check
# (status AND prog_done), the startup gates with exact markers. Variant `pipedual` only (payload f330769d…,
# bit 646d88b7…, P4b build aa24497). The artefact set, state and sessions live in a FIXED workspace ($P4C_WS), so a
# frozen copy of these scripts (git archive of a commit) reads and writes the same place.
set -u
R=/home/engineer/fpga
P4C=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export PERF_PROBES=""                             # this session measures with xv6 and the frequency reference, not probes
# shellcheck disable=SC1090
. "$P4C/lib/lib-e1.sh"
WS=${P4C_WS:-/home/engineer/fpga/worktrees/pipe-dual/experiments/pipeline/p4c/ws}
ART=$WS/artefacts; STATE=$WS/state
PAYLOAD_SHA=f330769dac6172da32c3b097ae615d7dde878a9cd2a276835686b1e0de5de7dd
BIT_SHA=646d88b73b908ad74b76db818cf9692797b3ce1545297c8582b45dd81a65d69a
USER_DISK=/root/xv6run/fs-user.img              # the user's own writable disk: never overwritten by a benchmark run
RUN_DISK=/root/xv6run/fs-run.img                # the per-run benchmark disk: a fresh copy before every run
p4c_check_artefacts() {
    [ -s "$P4C/artefacts.sha256" ] || die $EX_HASH "$P4C/artefacts.sha256 is missing"
    ( cd "$ART" && sha256sum -c "$P4C/artefacts.sha256" ) > /dev/null 2>&1 || die $EX_HASH "the frozen artefact set in $ART does not match artefacts.sha256 (run freeze.sh)"
    local got; got=$(sha256sum "$ART/pipedual.bit.bin" | cut -d' ' -f1)
    [ "$got" = "$PAYLOAD_SHA" ] || die $EX_HASH "pipedual.bit.bin hashes $got, not the accepted payload $PAYLOAD_SHA"
    say "  frozen artefact set verified: $(grep -c . "$P4C/artefacts.sha256") artefacts; payload ${PAYLOAD_SHA:0:16}… (bit ${BIT_SHA:0:16}…)"
}
# "No host is running" is NOT taken from `pgrep -x fesvr-teaching-static` alone: procps' pgrep cannot match that
# 21-character name (the kernel keeps 15: "fesvr-teaching-"), and the board's pgrep is measured only in install step
# 6b. The /proc/*/comm scan (exact match, so the scanning shell, cat and grep never match themselves), pgrep, and the
# host lock must ALL say "none"; anything else stops the session (Codex, P4c review).
p4c_no_host() {
    board_must "$1" "mkdir -p /var/lock; echo HC=\$(cat /proc/[0-9]*/comm 2>/dev/null | grep -cx fesvr-teaching-); echo HP=\$(pgrep -x fesvr-teaching-static | wc -l); echo HL=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK)"
    local c p l; c=$(field HC); p=$(field HP); l=$(field HL)
    [ "$c" = 0 ] && [ "$p" = 0 ] && [ "$l" = NO_LOCK ] || die $EX_BUSY "a host or the lock is present, or the state is unreadable (comm scan '${c}', pgrep '${p}', lock '${l}'): stopping"
    say "  no host running: comm scan 0, pgrep 0, lock free"
}
p4c_deploy_install() {   # payload, host, the 6 dual gates, the two (two-hart) frequency programs
    local S=$1 f
    deploy_verified "$ART/pipedual.bit.bin" /root/xv6run/pipedual.bit.bin "$S/deploy.log"
    deploy_verified "$ART/fesvr-teaching-static" /root/xv6run/fesvr-teaching-static "$S/deploy.log"
    for f in $GATES freq_spin_short freq_spin_long; do deploy_verified "$ART/$f.elf" "/root/xv6run/$f.elf" "$S/deploy.log"; done
    make_executable "/root/xv6run/*.elf /root/xv6run/fesvr-teaching-static"
}
