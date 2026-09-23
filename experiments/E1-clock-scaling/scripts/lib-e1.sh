#!/usr/bin/env bash
# Shared gates for the E1 install/restore sessions.
#
# Every gate REFUSES rather than improvises, and each has its own exit code so a test can assert WHICH
# gate fired rather than merely that something failed. Nothing here retries; nothing here recovers.
#
# Board access goes through $E1_BOARD_CMD, which defaults to the production serial shim. The rehearsal
# substitutes a scripted fake, so the path under test is the same one that runs on hardware.

R=/home/engineer/fpga
SHIM=$R/experiments/teaching-cpu/xv6-board-run/scripts/serial-transport.py
: "${E1_BOARD_CMD:=timeout 200 python3 $SHIM}"
: "${E1_LOG:=}"

# exit codes, one per refusal reason
EX_NOT_COLD=10        # the boot id did not change: no power cycle happened
EX_UPTIME=11          # boot id changed but uptime is not near zero
EX_DIRTY=12           # /root/xv6run is not empty: not a fresh RAM initramfs
EX_BUSY=13            # a host is running or an ownership lock is present
EX_HASH=20            # an artefact hashed wrong ON THE BOARD
EX_PROG=21            # programming did not leave prog_done=1
EX_GATE=30            # a startup probe failed
EX_SAMPLES=40         # fewer samples than the policy requires
EX_PIN=50             # no pinned pre-cycle boot id to compare against

# progress goes to stderr, never stdout: verify_cold_cycle returns the new boot id ON STDOUT and a
# chatty helper would silently corrupt it inside a command substitution.
say()  { printf '%s\n' "$*" >&2; if [ -n "$E1_LOG" ]; then printf '%s\n' "$*" >> "$E1_LOG"; fi; }
die()  { local c=$1; shift; say "REFUSE($c): $*"; exit "$c"; }

board() { $E1_BOARD_CMD "$1" 2>&1; }

# --- gate 1 / gate 8: a power cycle happened, verified and never assumed -------------------------
#
# The comparison is against a boot id PINNED BEFORE the user powered down, recorded in a file. A boot id
# recited in conversation is not evidence, and neither is a coord note.
verify_cold_cycle() {
    local pinfile=$1 maxuptime=${2:-600}
    [ -s "$pinfile" ] || die $EX_PIN "no pinned pre-cycle boot id at $pinfile; run e1-precycle.sh BEFORE powering down"
    local pinned; pinned=$(cat "$pinfile")
    local out; out=$(board "echo BID=\$(cat /proc/sys/kernel/random/boot_id); echo UP=\$(cut -d. -f1 /proc/uptime); echo N=\$(ls -A /root/xv6run 2>/dev/null | wc -l); echo F=\$(pgrep -x fesvr-teaching-static | wc -l); echo L=\$(test -e /var/lock/teaching-fesvr.lock && echo PRESENT || echo NO_LOCK)")
    local bid up n f l
    bid=$(sed -n 's/^BID=//p' <<<"$out" | tail -1)
    up=$(sed  -n 's/^UP=//p'  <<<"$out" | tail -1)
    n=$(sed   -n 's/^N=//p'   <<<"$out" | tail -1)
    f=$(sed   -n 's/^F=//p'   <<<"$out" | tail -1)
    l=$(sed   -n 's/^L=//p'   <<<"$out" | tail -1)
    say "  boot id now    : ${bid:-<unreadable>}"
    say "  pinned before  : $pinned"
    say "  uptime         : ${up:-?} s;  /root/xv6run entries: ${n:-?};  fesvr: ${f:-?};  lock: ${l:-?}"
    [ -n "$bid" ] || die $EX_NOT_COLD "could not read a boot id; the board's state is unknown, so nothing may proceed"
    [ "$bid" != "$pinned" ] || die $EX_NOT_COLD "the boot id is UNCHANGED. No power cycle happened. This is the one thing that may never be assumed"
    [ "${up:-999999}" -le "$maxuptime" ] || die $EX_UPTIME "the boot id changed but uptime is ${up}s (> ${maxuptime}s); that is not the cold platform this step requires"
    [ "${n:-1}" -eq 0 ] || die $EX_DIRTY "/root/xv6run holds ${n} entries; on a real cold boot the RAM initramfs leaves it empty"
    [ "${f:-1}" -eq 0 ] || die $EX_BUSY "a host process is running"
    [ "$l" = "NO_LOCK" ] || die $EX_BUSY "an ownership lock is present; it must not be cleared by hand"
    say "  COLD CYCLE VERIFIED (new boot id $bid)"
    printf '%s\n' "$bid"
}

# --- gate 3 / gate 9: an artefact hashes right ON THE BOARD, not just here -----------------------
verify_on_board() {
    local path=$1 want=$2
    local got; got=$(board "sha256sum $path | cut -d' ' -f1" | grep -oE '^[0-9a-f]{64}' | tail -1)
    [ "$got" = "$want" ] || die $EX_HASH "$path hashed ${got:-<unreadable>} on the board, expected $want"
    say "  verified on board: $path = ${got:0:16}…"
}

# --- gate 4 / gate 10: programming, and its result read back ------------------------------------
program_payload() {
    local path=$1
    say "  programming $path"
    board "cat $path > /dev/xdevcfg" >/dev/null
    local done_; done_=$(board "cat /sys/devices/amba.1/f8007000.devcfg/prog_done" | grep -oE '^[01]$' | tail -1)
    [ "$done_" = "1" ] || die $EX_PROG "prog_done reads '${done_:-<unreadable>}' after programming; the fabric is not configured and NOTHING further may be attempted"
    say "  prog_done=1"
}

# --- gate 5 / gate 11: the eight startup probes. A failure stops the session ---------------------
# The real invocation is a POSITIONAL elf argument -- "./fesvr-teaching-static ./boot01_marker.elf" --
# as the run-2/run-3 logs record. An earlier draft here wrote "+payload=..." from memory, which would have
# failed on hardware inside the user's power-cycle window. $E1_TIMEOUT is "timeout " when the board has it.
: "${E1_TIMEOUT:=timeout }"
GATES="boot01_marker boot02_clint boot03_ddr boot04_badaddr ext01_m ext02_c ext03_a ext04_sv39"
run_startup_gates() {
    local outdir=$1 timeout_s=${2:-120} n=0
    mkdir -p "$outdir"
    for g in $GATES; do
        local out; out=$(board "cd /root/xv6run && $E1_TIMEOUT$timeout_s ./fesvr-teaching-static ./$g.elf 2>&1; echo RC=\$?")
        printf '%s\n' "$out" > "$outdir/$g.out"
        local rc; rc=$(sed -n 's/^RC=//p' <<<"$out" | tail -1)
        if [ "${rc:-1}" != "0" ]; then
            say "  gate $g: FAILED rc=${rc:-<none>}"
            die $EX_GATE "startup gate $g failed. The session stops here; it is not skipped and not retried"
        fi
        n=$((n+1)); say "  gate $g: ok"
    done
    [ "$n" -eq 8 ] || die $EX_GATE "only $n of 8 gates ran"
    say "  STARTUP GATES 8/8"
}

# --- the adapter status line, read and recorded, never predicted --------------------------------
record_adapter_status() {
    local src=$1 dest=$2
    grep -oE 'status=0x[0-9a-fA-F]+ .*' "$src" | head -1 > "$dest" || true
    say "  adapter status recorded: $(cat "$dest" 2>/dev/null | cut -c1-70)"
}
