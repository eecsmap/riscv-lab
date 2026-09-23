#!/usr/bin/env python3
"""Capture THIS boot's memory evidence from the running ARM, in the layout mem-preflight.py requires.

mem-preflight.py checks evidence; it does not collect it. The collection step was missing from the E1
scripts entirely, which Codex caught: the install called it with a --evidence-dir flag the real CLI does
not have, against a directory nothing had filled.

Three files are RAW BYTES from /proc/device-tree, and the console is a text channel, so they cross as
`od -An -tx1 -v` and are reassembled here. Every reply is delimited, and the LAST delimited block is
taken: the shim echoes the command, and the echo contains the delimiters too.

  capture_evidence.py --dest <evidence-dir>
"""
import os
import re
import subprocess
import sys

CMD = os.environ.get("E1_BOARD_CMD")

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
B, E = "__E1B__", "__E1E__"


def ask(cmd):
    """Run one command on the board and return the text between the LAST BEGIN and its END."""
    full = f"echo {B}; {cmd}; echo {E}"
    p = subprocess.run(CMD.split() + [full], capture_output=True, text=True)
    out = p.stdout + p.stderr
    # the last BEGIN is the real one; everything before it includes the echoed command line, which
    # contains both delimiters itself.
    starts = [m.end() for m in re.finditer(re.escape(B), out)]
    if not starts:
        raise RuntimeError(f"no delimiter in the reply to: {cmd}\n{out[-300:]}")
    tail = out[starts[-1]:]
    end = tail.find(E)
    if end < 0:
        raise RuntimeError(f"unterminated reply to: {cmd}\n{out[-300:]}")
    return tail[:end].strip("\r\n"), p.returncode


def main(argv):
    if not CMD:
        print("E1_BOARD_CMD is not set", file=sys.stderr)
        return 2
    dest = argv[argv.index("--dest") + 1]
    os.makedirs(os.path.join(dest, "dt"), exist_ok=True)

    for rel, cmd in TEXT.items():
        body, rc = ask(cmd)
        if rc != 0 or not body.strip():
            print(f"capture failed for {rel} (rc={rc})", file=sys.stderr)
            return 1
        with open(os.path.join(dest, rel), "w") as f:
            f.write(body.strip() + "\n" if rel == "session-id" else body + "\n")

    for rel, path in BIN.items():
        body, rc = ask(f"od -An -tx1 -v '{path}'")
        if rc != 0:
            print(f"capture failed for {rel} (rc={rc})", file=sys.stderr)
            return 1
        hexs = re.findall(r"\b([0-9a-f]{2})\b", body)
        if not hexs:
            print(f"no bytes came back for {rel}", file=sys.stderr)
            return 1
        with open(os.path.join(dest, rel), "wb") as f:
            f.write(bytes(int(h, 16) for h in hexs))

    # reserved-memory nodes are optional; capture whatever is there
    names, rc = ask("ls /proc/device-tree/reserved-memory 2>/dev/null || true")
    for name in [n.strip() for n in names.split() if n.strip() and "/" not in n]:
        body, rc = ask(f"od -An -tx1 -v '/proc/device-tree/reserved-memory/{name}/reg' 2>/dev/null || true")
        hexs = re.findall(r"\b([0-9a-f]{2})\b", body)
        if hexs:
            d = os.path.join(dest, "dt", "reserved", name)
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "reg"), "wb") as f:
                f.write(bytes(int(h, 16) for h in hexs))

    print(f"EVIDENCE_CAPTURED {dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
