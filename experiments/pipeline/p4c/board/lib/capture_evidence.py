#!/usr/bin/env python3
"""Capture THIS boot's memory evidence from the running ARM, in the layout mem-preflight.py requires.

mem-preflight.py checks evidence; it does not collect it. The collection step was missing from the E1
scripts entirely, which Codex caught: the install called it with a --evidence-dir flag the real CLI does
not have, against a directory nothing had filled.

Three files are RAW BYTES from /proc/device-tree, and the console is a text channel, so they cross as
`od -An -tx1 -v` and are reassembled here. Every reply is delimited and the LAST delimited block is
taken: the shim echoes the command, and the echo contains the delimiters too.

Two statuses, kept apart, because they mean different things:

  * the TRANSPORT status -- the shim's own exit. Non-zero means we do not know what the board did.
  * the REMOTE status -- `__E1S__=<n>` echoed inside the block by the board itself.

And reserved-memory is fail-closed. mem-preflight permits a reserved node to be ABSENT; it does not
permit one to exist and be unreadable. An earlier version here used `|| true` and skipped a node whose
bytes did not come back, which silently turns an unreadable reservation into "there isn't one".

  capture_evidence.py --dest <evidence-dir>
"""
import os
import re
import subprocess
import sys

CMD = os.environ.get("E1_BOARD_CMD")
B, E, SMARK = "__E1B__", "__E1E__", "__E1S__"
HEX_ONLY = re.compile(r"^[\s0-9a-f]*$")
BYTE = re.compile(r"[0-9a-f]{2}")


class CaptureFailed(Exception):
    """Something is unknown or unreadable. Never a reason to carry on with less evidence."""


def ask(cmd):
    """Run one command on the board. Returns (body, remote_status). Raises on transport trouble."""
    # The status is captured BEFORE the separating newline is emitted, because `echo` would overwrite
    # $?. The separator exists because a command's output need not end in a newline:
    # /proc/sys/kernel/random/boot_id does not, so the reply came back as
    #   23981968-...-c328b780cbcf__E1S__=0
    # with the marker glued to the data and no line start for an anchored pattern to find.
    full = f"echo {B}; {cmd}; __e1s=$?; echo; echo {SMARK}=$__e1s; echo {E}"
    p = subprocess.run(CMD.split() + [full], capture_output=True, text=True)
    # This console emits NUL bytes. They are not data: the production mem-preflight refuses a capture
    # containing one -- "this capture is corrupt, not merely terminated" -- which is how this was found,
    # correctly, by the tool downstream rather than by anything here. lib-e1.sh strips them at its own
    # transport boundary; this helper talks to the shim directly and has to do the same.
    out = (p.stdout + p.stderr).replace("\x00", "")
    if p.returncode != 0:
        raise CaptureFailed(f"the transport failed (exit {p.returncode}) running: {cmd}\n{out[-200:]}")
    starts = [m.end() for m in re.finditer(re.escape(B), out)]
    if not starts:
        raise CaptureFailed(f"no delimiter in the reply to: {cmd}\n{out[-200:]}")
    tail = out[starts[-1]:]
    end = tail.find(E)
    if end < 0:
        raise CaptureFailed(f"unterminated reply to: {cmd}\n{out[-200:]}")
    block = tail[:end]
    m = None
    for m in re.finditer(rf"{re.escape(SMARK)}=(-?\d+)", block):
        pass            # the LAST one; not anchored, because the marker may be glued to the output
    if m is None:
        raise CaptureFailed(f"the board did not report a status for: {cmd}")
    body = block[:m.start()].strip("\r\n")
    return body, int(m.group(1))


def must(cmd, what):
    body, rc = ask(cmd)
    if rc != 0:
        raise CaptureFailed(f"{what} failed on the board (exit {rc}): {cmd}")
    return body


def bytes_from_od(body, what):
    """Parse `od -An -tx1 -v` output STRICTLY. Anything that is not hex bytes and whitespace is an error,
    not something to sift bytes out of."""
    if not HEX_ONLY.match(body):
        bad = [ln for ln in body.splitlines() if not HEX_ONLY.match(ln)][:1]
        raise CaptureFailed(f"{what}: the reply is not plain od output; first offending line: {bad}")
    toks = body.split()
    if not toks:
        raise CaptureFailed(f"{what}: no bytes came back")
    for t in toks:
        if not BYTE.fullmatch(t):
            raise CaptureFailed(f"{what}: {t!r} is not a byte")
    return bytes(int(t, 16) for t in toks)


TEXT = {
    "session-id": "cat /proc/sys/kernel/random/boot_id",
    "proc-iomem": "cat /proc/iomem",
    "proc-meminfo": "cat /proc/meminfo",
}
BIN = {
    "dt/address-cells": "/proc/device-tree/#address-cells",
    "dt/size-cells": "/proc/device-tree/#size-cells",
    "dt/memory-reg": "/proc/device-tree/memory/reg",
}
RESV = "/proc/device-tree/reserved-memory"


def main(argv):
    if not CMD:
        print("E1_BOARD_CMD is not set", file=sys.stderr)
        return 2
    dest = argv[argv.index("--dest") + 1]
    os.makedirs(os.path.join(dest, "dt"), exist_ok=True)

    for rel, cmd in TEXT.items():
        body = must(cmd, f"reading {rel}")
        if not body.strip():
            raise CaptureFailed(f"{rel} came back empty")
        with open(os.path.join(dest, rel), "w") as f:
            f.write(body.strip() + "\n" if rel == "session-id" else body + "\n")

    for rel, path in BIN.items():
        body = must(f"od -An -tx1 -v '{path}'", f"reading {rel}")
        with open(os.path.join(dest, rel), "wb") as f:
            f.write(bytes_from_od(body, rel))

    # reserved-memory: absent is allowed, unreadable is not.
    present, _ = ask(f"if [ -d {RESV} ]; then echo DIR=present; else echo DIR=absent; fi")
    state = (re.findall(r"^DIR=(present|absent)$", present, re.M) or [None])[-1]
    if state is None:
        raise CaptureFailed("could not determine whether reserved-memory exists")
    if state == "present":
        listing = must(f"ls -1 {RESV}", "listing reserved-memory")
        names = [n.strip() for n in listing.split() if n.strip() and "/" not in n]
        for name in names:
            node = f"{RESV}/{name}"
            has, _ = ask(f"if [ -f {node}/reg ]; then echo REG=yes; else echo REG=no; fi")
            hs = (re.findall(r"^REG=(yes|no)$", has, re.M) or [None])[-1]
            if hs is None:
                raise CaptureFailed(f"could not determine whether {name} has a reg property")
            if hs == "no":
                continue                                  # a node without reg is not a reservation
            body = must(f"od -An -tx1 -v '{node}/reg'", f"reading reserved node {name}")
            blob = bytes_from_od(body, f"reserved node {name}")
            d = os.path.join(dest, "dt", "reserved", name)
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "reg"), "wb") as f:
                f.write(blob)
        print(f"EVIDENCE_CAPTURED {dest} (reserved-memory: {len(names)} node(s))")
    else:
        print(f"EVIDENCE_CAPTURED {dest} (reserved-memory: absent, which the preflight permits)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except CaptureFailed as e:
        print(f"CAPTURE_REFUSED: {e}", file=sys.stderr)
        sys.exit(1)
