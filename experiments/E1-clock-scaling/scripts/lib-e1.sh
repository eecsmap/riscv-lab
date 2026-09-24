#!/usr/bin/env bash
# Shared gates for the E1 install/restore sessions.
#
# Every gate REFUSES rather than improvises, and each has its own exit code so a test can assert WHICH
# gate fired rather than merely that something failed. Nothing here retries; nothing here recovers.
#
# Board access goes through $E1_BOARD_CMD, which defaults to the production serial shim. The entrypoint
# rehearsal substitutes a RECORDING fake, so what is under test is the same path that runs on hardware.
#
# ---------------------------------------------------------------------------------------------------
# Why no gate returns its value through $( ):
#
#   NEWBID=$(verify_cold_cycle ...)     # <- the ORIGINAL form, and it was broken
#
# `die` calls `exit`, and inside a command substitution that exits the SUBSHELL. The parent carried on
# with the refusal message captured as the boot id and went on to program the FPGA. Found in review by
# Codex; demonstrated before fixing. Gates now write their result to a file and are called plainly, so
# `die` ends the session, and every caller still checks the status explicitly.
# ---------------------------------------------------------------------------------------------------

R=/home/engineer/fpga
# `: "${SHIM:=...}"`, not a plain assignment. This is the third place in these scripts where an
# unconditional assignment silently defeated an override (SEND in artefacts.sh was the second), and it
# defeats it in the worst direction: the fallback is the REAL serial device, so the failure mode is a
# test that opens hardware and hangs rather than one that errors.
: "${SHIM:=$R/experiments/teaching-cpu/xv6-board-run/scripts/serial-transport.py}"
: "${E1_BOARD_CMD:=timeout 200 python3 $SHIM}"
# EXPORTED: `: "${VAR:=...}"` creates a shell variable, not an environment one, so capture_evidence.py
# saw nothing whenever the caller had not set it itself -- which is every production run. The rehearsal
# passed it as env and so never exercised the default. Codex reproduced it.
export E1_BOARD_CMD
: "${E1_LOG:=}"
# `${VAR=default}`, NOT `${VAR:=default}`: the colon form substitutes for an empty value too, so
# E1_TIMEOUT='' -- which precycle tells the user to set when the board has no `timeout` -- was silently
# turned back into "timeout ". The advice would not have worked. Found by asserting the command.
: "${E1_TIMEOUT=timeout }"
# Overridable so the ENTRYPOINT rehearsal can drive the real scripts without a board, a coord daemon or
# a file transfer. Defaults are the production paths; the rehearsal substitutes recording stubs.
: "${E1_COORD:=$R/coord}"
: "${SEND:=$R/experiments/teaching-cpu/xv6-board-run/scripts/send-file.py}"
: "${E1_MEMPREFLIGHT:=$R/riscv-lab/tools/board/scripts/mem-preflight.py}"

# exit codes, one per refusal reason
EX_NOT_COLD=10        # the boot id did not change: no reboot at all
EX_UPTIME=11          # boot id changed but uptime is not near zero
EX_DIRTY=12           # /root/xv6run is not empty: not a fresh RAM initramfs
EX_BUSY=13            # a host is running or an ownership lock is present
EX_NO_POWER_RECORD=14 # no user-attested record that power was physically removed
EX_HASH=20            # an artefact hashed wrong ON THE BOARD, or a deploy failed
EX_PROG=21            # programming failed, or did not leave prog_done=1
EX_GATE=30            # a startup probe failed
EX_SAMPLES=40         # fewer usable samples than the policy requires
EX_PIN=50             # no pinned pre-cycle boot id to compare against
EX_LEASE=60           # a lease could not be claimed
EX_MEM=61             # memory evidence could not be captured, or the preflight refused
EX_TRANSPORT=62       # the transport itself failed; the board's state is unknown

say()  { printf '%s\n' "$*" >&2; if [ -n "$E1_LOG" ]; then printf '%s\n' "$*" >> "$E1_LOG"; fi; }
die()  { local c=$1; shift; say "REFUSE($c): $*"; exit "$c"; }

# --- transport -----------------------------------------------------------------------------------
#
# board() writes the reply to $BOARD_OUT and RETURNS the remote status. It never swallows it. Callers
# that care about the status -- which is all of them at a safety boundary -- check it.
BOARD_OUT=""
board() {
    BOARD_OUT=$($E1_BOARD_CMD "$1" 2>&1)
    return $?
}
# board_must: any transport or remote failure ends the session. Used wherever "it did not work" and
# "we do not know whether it worked" must be treated the same way.
board_must() {
    local what=$1 cmd=$2
    if ! board "$cmd"; then
        say "  transport/remote failure during: $what"
        say "  ---- last reply ----"; say "$BOARD_OUT"; say "  --------------------"
        die $EX_TRANSPORT "$what failed; the board's state is not known from here and nothing further may be attempted"
    fi
}
# last KEY=value, never the first: the shim echoes the command and the terminal WRAPS that echo, so a
# line can begin with KEY= and still be the question rather than the answer.
field() { sed -n "s/^$1=//p" <<<"$BOARD_OUT" | tail -1; }

# --- leases: claimed BEFORE any transport call, released only if we own them ----------------------
E1_OWNED_LEASES=""
claim_leases() {
    local l
    for l in "$@"; do
        if "$E1_COORD" claim "$l" >/dev/null 2>&1; then
            E1_OWNED_LEASES="$E1_OWNED_LEASES $l"; say "  claimed lease: $l"
        else
            say "  could not claim lease: $l"
            release_owned_leases
            die $EX_LEASE "the '$l' lease was refused; another holder may be using the board. Not proceeding on a partial claim"
        fi
    done
}
release_owned_leases() {
    local l
    for l in $E1_OWNED_LEASES; do
        "$E1_COORD" release "$l" >/dev/null 2>&1 && say "  released lease: $l" \
            || say "  NOTE: could not release the '$l' lease; it is still recorded as held by us"
    done
    E1_OWNED_LEASES=""
}

# --- gate 1 / gate 8: a reboot happened, AND power was physically removed -------------------------
#
# Codex's correction, and it is right: a pinned boot id proves a NEW LINUX BOOT, not power removal. A
# warm `reboot` also changes the boot id, resets uptime and clears the RAM initramfs, and leaves the PL
# configured. So the boot evidence is necessary and not sufficient, and the power-removal fact is
# ATTESTED BY THE USER and labelled as such -- it is not measured here and is not claimed to be.
verify_power_record() {
    local rec=$1 pinfile=$2
    [ -s "$rec" ] || die $EX_NO_POWER_RECORD "no power-removal record at $rec. Have the user run e1-record-power-cycle.sh AFTER physically removing and restoring power"
    grep -q '^POWER_REMOVED=yes$' "$rec" || die $EX_NO_POWER_RECORD "$rec does not attest that power was removed"
    if [ -f "$pinfile" ] && [ "$rec" -ot "$pinfile" ]; then
        die $EX_NO_POWER_RECORD "$rec is OLDER than the pin; it attests to an earlier cycle, not this one"
    fi
    say "  power removal: ATTESTED by the user at $(sed -n 's/^AT=//p' "$rec" | tail -1) (attested, not measured)"
}

verify_cold_cycle() {
    local pinfile=$1 outfile=$2 maxuptime=${3:-600}
    [ -s "$pinfile" ] || die $EX_PIN "no pinned pre-cycle boot id at $pinfile; run e1-precycle.sh BEFORE powering down"
    local pinned; pinned=$(cat "$pinfile")
    board_must "reading the boot state" "echo BID=\$(cat /proc/sys/kernel/random/boot_id); echo UP=\$(cut -d. -f1 /proc/uptime); echo N=\$(ls -A /root/xv6run 2>/dev/null | wc -l); echo F=\$(pgrep -x fesvr-teaching-static | wc -l); echo L=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK)"
    local bid up n f l
    bid=$(field BID); up=$(field UP); n=$(field N); f=$(field F); l=$(field L)
    say "  boot id now    : ${bid:-<unreadable>}"
    say "  pinned before  : $pinned"
    say "  uptime         : ${up:-?} s;  /root/xv6run entries: ${n:-?};  fesvr: ${f:-?};  lock: ${l:-?}"
    [ -n "$bid" ] || die $EX_NOT_COLD "could not read a boot id; the board's state is unknown, so nothing may proceed"
    [ "$bid" != "$pinned" ] || die $EX_NOT_COLD "the boot id is UNCHANGED. No reboot happened. This is the one thing that may never be assumed"
    [ "${up:-999999}" -le "$maxuptime" ] || die $EX_UPTIME "the boot id changed but uptime is ${up}s (> ${maxuptime}s); that is not the cold platform this step requires"
    [ "${n:-1}" -eq 0 ] || die $EX_DIRTY "/root/xv6run holds ${n} entries; on a real cold boot the RAM initramfs leaves it empty"
    [ "${f:-1}" -eq 0 ] || die $EX_BUSY "a host process is running"
    [ "$l" = "NO_LOCK" ] || die $EX_BUSY "an ownership lock is present; it must not be cleared by hand"
    say "  boot evidence consistent with a cold start (new boot id $bid)"
    printf '%s\n' "$bid" > "$outfile"
}

# --- memory evidence: captured from THIS boot, then checked by the production preflight ------------
capture_memory_evidence() {
    local dest=$1 expect_session=$2
    mkdir -p "$dest/dt"
    E1_BOARD_CMD="$E1_BOARD_CMD" python3 "$(dirname "${BASH_SOURCE[0]}")/capture_evidence.py" --dest "$dest" \
        || die $EX_MEM "could not capture this boot's memory evidence"
    local got; got=$(cat "$dest/session-id" 2>/dev/null | tr -d ' \n')
    [ "$got" = "$expect_session" ] || die $EX_MEM "the captured evidence belongs to session '${got:-<none>}', not the live boot '$expect_session'"
    say "  captured memory evidence for session $got"
}
run_mem_preflight() {
    local dir=$1 session=$2 json=$3
    # positional evidence dir, --expect-session, and the verdict taken from the EXIT STATUS -- not from
    # grepping a log that accumulates across steps.
    if python3 "$E1_MEMPREFLIGHT" "$dir" --expect-session "$session" \
            --json "$json" >>"${E1_LOG:-/dev/null}" 2>&1; then
        say "  MEM_PREFLIGHT passed for session $session"
    else
        die $EX_MEM "the memory preflight refused this boot's evidence; see $json and the session log"
    fi
}

# --- deploy: the real upload path verifies each hash on the board; exec mode is a separate step ----
deploy_verified() {
    local src=$1 dst=$2 log=$3
    [ -f "$src" ] || die $EX_HASH "$src is missing locally"
    python3 $SEND "$src" "$dst" --log "$log" >/dev/null 2>&1 \
        || die $EX_HASH "deploying $src to $dst failed; send-file.py verifies the sha256 on the board and it did not match, or the transfer failed"
    say "  deployed+verified: $dst"
}
make_executable() {
    # send-file.py does not set the mode; the historical procedure chmods as a separate step and so
    # does this. Without it the probes are not runnable and the failure appears much later as "not found".
    board_must "setting executable mode" "chmod +x $* && echo MODE=ok"
    [ "$(field MODE)" = ok ] || die $EX_HASH "could not make the deployed artefacts executable"
    say "  executable mode set"
}

# --- programming: the command's own status, then prog_done. Neither alone is enough ---------------
program_payload() {
    local path=$1
    say "  programming $path"
    # The programming command's exit status is checked FIRST. prog_done is 1 whenever ANY bitstream is
    # loaded, including the one already there, so a failed write followed by a stale prog_done=1 would
    # otherwise read as success.
    board_must "programming the PL" "cat $path > /dev/xdevcfg; echo PROG_RC=\$?"
    local prc; prc=$(field PROG_RC)
    [ "$prc" = "0" ] || die $EX_PROG "the programming command exited ${prc:-<unreadable>}; the PL was not written and its contents are now uncertain"
    board_must "reading prog_done" "echo PD=\$(cat /sys/devices/amba.1/f8007000.devcfg/prog_done)"
    local done_; done_=$(field PD)
    [ "$done_" = "1" ] || die $EX_PROG "prog_done reads '${done_:-<unreadable>}' after programming; the fabric is not configured and NOTHING further may be attempted"
    say "  programming reported rc=0 and prog_done=1"
}

# --- the eight startup gates: exact marker AND confirmed exit. A failure stops the session ---------
GATES="boot01_marker boot02_clint boot03_ddr boot04_badaddr ext01_m ext02_c ext03_a ext04_sv39"
PERF_PROBES="perf03_fetch perf04_where"
marker_for() { awk -v p="$1" '$1==p {print $2}' "$(dirname "${BASH_SOURCE[0]}")/markers.tsv"; }

# The probes are RISC-V TARGET ELFs. They cannot execute on the ARM at all: they run under
# ./fesvr-teaching-static, exactly as the run-2/run-3 board flow does. An earlier version invoked
# ./probe.elf directly -- the mocks accepted it because they matched on ".elf", which is why the
# recording stand-in now REFUSES a target ELF that is not passed to fesvr.
#
# The bound is optional: with E1_TIMEOUT empty the command must still be a command, not a bare number
# left where the program should be.
probe_cmd() {
    local elf=$1 t=$2 pre=""
    [ -n "$E1_TIMEOUT" ] && pre="${E1_TIMEOUT}${t} "
    printf 'cd /root/xv6run && %s./fesvr-teaching-static ./%s.elf 2>&1; echo RC=$?' "$pre" "$elf"
}

run_startup_gates() {
    local outdir=$1 timeout_s=${2:-120} n=0 g
    mkdir -p "$outdir"
    for g in $GATES; do
        local want; want=$(marker_for "$g")
        [ -n "$want" ] || die $EX_GATE "no completion marker recorded for $g; run gen-markers.sh"
        if ! board "$(probe_cmd "$g" "$timeout_s")"; then
            printf '%s\n' "$BOARD_OUT" > "$outdir/$g.out"
            die $EX_GATE "the transport failed while running gate $g; the board's state is unknown"
        fi
        printf '%s\n' "$BOARD_OUT" > "$outdir/$g.out"
        local rc; rc=$(field RC)
        if [ "${rc:-1}" != "0" ]; then
            die $EX_GATE "startup gate $g exited ${rc:-<none>}. The session stops here; it is not skipped and not retried"
        fi
        grep -qF "$want" "$outdir/$g.out" \
            || die $EX_GATE "startup gate $g exited 0 but never printed its completion marker '$want'. An exit status is not a result"
        n=$((n+1)); say "  gate $g: ok ($want)"
    done
    [ "$n" -eq 8 ] || die $EX_GATE "only $n of 8 gates ran"
    say "  STARTUP GATES 8/8"
}

# --- perf samples: validated by the production probe parser, not by RC=0 --------------------------
run_perf_samples() {
    local outdir=$1 want_n=$2 timeout_s=${3:-120} probe n ok
    mkdir -p "$outdir"
    for probe in $PERF_PROBES; do
        ok=0
        for n in $(seq 1 "$want_n"); do
            if ! board "$(probe_cmd "$probe" "$timeout_s")"; then
                printf '%s\n' "$BOARD_OUT" > "$outdir/$probe.$n.out"
                die $EX_TRANSPORT "the transport failed during $probe sample $n; the board's state is unknown"
            fi
            printf '%s\n' "$BOARD_OUT" > "$outdir/$probe.$n.out"
            if python3 "$(dirname "${BASH_SOURCE[0]}")/validate_sample.py" \
                   "$outdir/$probe.$n.out" "$probe" >>"${E1_LOG:-/dev/null}" 2>&1; then
                ok=$((ok+1)); say "  $probe sample $n: usable"
            else
                say "  $probe sample $n: REJECTED by the probe parser (recorded, not retried)"
            fi
        done
        [ "$ok" -ge "$want_n" ] || die $EX_SAMPLES "$probe produced $ok/$want_n usable samples. A shortfall means the MEASUREMENT FAILED; samples are not re-run. Restoration is still required"
        say "  $probe: $ok/$want_n usable"
    done
}

record_adapter_status() {
    local src=$1 dest=$2
    grep -oE 'status=0x[0-9a-fA-F]+ .*' "$src" | head -1 > "$dest" || true
    say "  adapter status recorded: $(cut -c1-70 "$dest" 2>/dev/null)"
}
