#!/usr/bin/env python3
"""PIPE-P3b: look at the board's serial console WITHOUT typing a command into it.
Reads passively for --listen seconds, then writes ONE newline (harmless at a busybox prompt and at xv6's `$ `
prompt alike), reads for --after seconds, and prints both byte streams (repr) with timestamps. It never sends
Ctrl-C, never runs a command, never touches /dev/xdevcfg. The caller holds the serial lease.
  console-probe.py [--device /dev/ttyUSB1] [--listen 3] [--after 3] [--no-newline]"""
import argparse, time, serial
ap = argparse.ArgumentParser(); ap.add_argument("--device", default="/dev/ttyUSB1")
ap.add_argument("--listen", type=float, default=3.0); ap.add_argument("--after", type=float, default=3.0)
ap.add_argument("--no-newline", action="store_true")
a = ap.parse_args()
s = serial.Serial(a.device, 115200, timeout=0.05, xonxoff=True)
def rd(sec):
    buf = b""; t = time.time()
    while time.time() - t < sec: buf += s.read(4096)
    return buf
t0 = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
passive = rd(a.listen)
print(f"PROBE start={t0} device={a.device}")
print(f"PROBE passive {len(passive)} bytes: {passive!r}")
if not a.no_newline:
    s.write(b"\n"); s.flush()
    after = rd(a.after)
    print(f"PROBE after-newline {len(after)} bytes: {after!r}")
s.close()
