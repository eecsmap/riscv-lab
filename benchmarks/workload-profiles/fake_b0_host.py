#!/usr/bin/env python3
"""A fake board-side host that serves the three B0 application commands over a console.

Not a copy of fakesim.py: that one is frozen and serves the four-command workload. This serves b0apps,
and nothing else -- a command it does not know gets an xv6-style "not found", so a driver that sent the
wrong thing cannot be mistaken for one that sent the right thing.

Modes, chosen by TEACHING_B0_MODE:
  ok            every checksum correct
  wrong-sum     b0array returns a different checksum
  truncated     b0file's output is cut off mid-line
  hang          b0compute never returns, so the driver's bounded timeout is exercised
"""
import os, sys, time

MODE = os.environ.get("TEACHING_B0_MODE", "ok")
STATE = os.environ.get("TEACHING_FAKE_STATE", ".")
rec = open(os.path.join(STATE, "host-stdin.txt"), "a", buffering=1)

OUT = {
    "b0compute": ["B0-COMPUTE-CHECKSUM=5adf55920bf7696", "B0-COMPUTE-DONE"],
    "b0array":   ["B0-ARRAY-CHECKSUM=88133d5bd386db60", "B0-ARRAY-DONE"],
    "b0file":    ["B0-FILE-CHECKSUM=62e55f5326378000", "B0-FILE-DONE"],
}


def w(s):
    sys.stdout.write(s)
    sys.stdout.flush()


w("\nteaching: ready after 50 ms; status=0x00000011 cpu_restart_safe=1 boot_ready=1\n")
w("\nxv6 kernel is booting\n\n")
w("blkdev: 4000 sectors (1 MB), max request 16 sectors\n")
time.sleep(0.2)
w("init: starting sh\n")
w("$ ")

for line in sys.stdin:
    cmd = line.strip()
    rec.write(cmd + "\n")
    w(cmd + "\n")
    if cmd == "b0compute" and MODE == "hang":
        while True:
            time.sleep(1)
    if cmd in OUT:
        lines = list(OUT[cmd])
        if MODE == "wrong-sum" and cmd == "b0array":
            lines[0] = "B0-ARRAY-CHECKSUM=deadbeefdeadbeef"
        if MODE == "truncated" and cmd == "b0file":
            w("B0-FILE-CHECKS")           # cut off, no newline, no DONE
            w("\n$ ")
            continue
        for l in lines:
            w(l + "\n")
    else:
        w(f"exec {cmd} failed\n")
    w("$ ")
