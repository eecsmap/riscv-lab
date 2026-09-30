#!/usr/bin/env python3
"""PIPE-P4c: bring the board's console to the ARM prompt the accepted way, or refuse. The caller holds the serial lease
and no other reader is attached. Writes ONE newline, then decides from what the console shows:
  ARM shell prompt ('# ' at the end)           -> nothing is running: done (exit 0)
  xv6 shell prompt ('$ ' at the end, idle)     -> ONE Ctrl-C (the documented stop of the launcher / the host), then
                                                  require the host to exit ('lock released' or the ARM prompt) within
                                                  --wait seconds (exit 0), else exit 3
  anything else (a command running, silence)   -> touch nothing more: exit 2, the USER must bring it to a prompt
Every byte in both directions goes to <transcript>.   console-stop.py <transcript> [--wait 30] [--device /dev/ttyUSB1]"""
import sys, time, re, serial
tr = sys.argv[1]; wait = float(sys.argv[sys.argv.index("--wait") + 1]) if "--wait" in sys.argv else 30.0
dev = sys.argv[sys.argv.index("--device") + 1] if "--device" in sys.argv else "/dev/ttyUSB1"
s = serial.Serial(dev, 115200, timeout=0.05, xonxoff=True); log = open(tr, "wb")
def rd(sec):
    b = b""; t = time.time()
    while time.time() - t < sec:
        c = s.read(4096)
        if c: log.write(c); log.flush(); b += c
    return b
def send(x): log.write(b"\n<<SEND " + repr(x).encode() + b">>\n"); s.write(x); s.flush()
passive = rd(2.0); send(b"\n"); out = rd(3.0); tail = out.replace(b"\r", b"").rstrip(b"\n")[-40:]
if re.search(rb"#\s?$", out.replace(b"\r", b"")):
    print(f"CONSOLE ARM prompt, nothing running ({tail!r})"); sys.exit(0)
if re.search(rb"\$\s?$", out.replace(b"\r", b"")):
    print(f"CONSOLE xv6 prompt, idle ({tail!r}): sending one Ctrl-C")
    send(b"\x03"); t = time.time(); b = b""
    while time.time() - t < wait:
        b += rd(0.5)
        if b"lock released" in b or re.search(rb"#\s?$", b.replace(b"\r", b"")):
            rd(1.0); print("CONSOLE the host exited; ARM prompt back"); sys.exit(0)
    print(f"CONSOLE the host did not exit within {wait}s after Ctrl-C (last: {b[-80:]!r})"); sys.exit(3)
print(f"CONSOLE unknown state (passive {len(passive)} bytes, reply {tail!r}): nothing further typed; the USER must bring the console to a prompt"); sys.exit(2)
