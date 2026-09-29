# PIPE-P3b: the single-pipeline board session library. An ISOLATED adaptation of the accepted IPS campaign's
# ips-lib.sh (worktrees/ips-cache/experiments/IPS-campaign/board) and the M5 m5-lib.sh. It sources the PRODUCTION
# E1 library (riscv-lab/experiments/E1-clock-scaling/scripts/lib-e1.sh, artefacts.sh) read-only and unmodified:
# the cold-cycle gate and its pin, the power-removal attestation, leases, memory evidence + production preflight,
# on-board hash verification, the programming check (status AND prog_done), the EIGHT single-hart startup gates
# with exact markers (the production GATES list, unchanged), and the probe sample validation.
# What differs: one variant, `pipe` (payload 5f97d4ab…, bit b687f77f…); the IPS campaign's four perf probes; the
# frequency-reference programs; the xv6 kernels/disks for m4smoke, perf-board and the user's interactive set.
set -u
R=/home/engineer/fpga
P3B=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
E1=$R/riscv-lab/experiments/E1-clock-scaling/scripts
export PERF_PROBES="perf02_sv39 perf03_fetch perf04_where perf06_iws"
# shellcheck disable=SC1090
. "$E1/lib-e1.sh"
. "$E1/artefacts.sh"
P3B_MIN_SAMPLES=${P3B_MIN_SAMPLES:-3}
ART=${P3B_ART:-$P3B/artefacts}                 # the frozen set (not in git; rebuilt by freeze.sh, checked by hash)
PAYLOAD_SHA=5f97d4abf2778c1a443a1df0932527e415a01dd1a63e82c0c1b4875373d1b460
BIT_SHA=b687f77f6b7cc69a251e51f0c5901e646c71de5ee85fe76ec99080b753794aed
USER_DISK=/root/xv6run/fs-user.img              # the user's own writable disk: never overwritten by a benchmark run
RUN_DISK=/root/xv6run/fs-run.img                # the per-run benchmark disk: a fresh copy before every run
p3b_check_artefacts() {
    [ -s "$P3B/artefacts.sha256" ] || die $EX_HASH "$P3B/artefacts.sha256 is missing"
    ( cd "$ART" && sha256sum -c "$P3B/artefacts.sha256" ) > /dev/null 2>&1 || die $EX_HASH "the frozen artefact set in $ART does not match artefacts.sha256 (run freeze.sh)"
    local got; got=$(sha256sum "$ART/pipe.bit.bin" | cut -d' ' -f1)
    [ "$got" = "$PAYLOAD_SHA" ] || die $EX_HASH "pipe.bit.bin hashes $got, not the accepted payload $PAYLOAD_SHA"
    say "  frozen artefact set verified: $(grep -c . "$P3B/artefacts.sha256") artefacts; payload ${PAYLOAD_SHA:0:16}… (bit ${BIT_SHA:0:16}…)"
}
p3b_elf_path() { echo "$ART/$1.elf"; }
p3b_deploy_install() {   # payload, host, the 8 gates, the 4 probes, the two frequency programs
    local S=$1 f
    deploy_verified "$ART/pipe.bit.bin" /root/xv6run/pipe.bit.bin "$S/deploy.log"
    deploy_verified "$ART/fesvr-teaching-static" /root/xv6run/fesvr-teaching-static "$S/deploy.log"
    for f in $GATES $PERF_PROBES freq_spin_short freq_spin_long; do deploy_verified "$(p3b_elf_path "$f")" "/root/xv6run/$f.elf" "$S/deploy.log"; done
    make_executable "/root/xv6run/*.elf /root/xv6run/fesvr-teaching-static"
}
