#!/usr/bin/env python3
"""Self-test of console-stop.py against a fake console on a pty (no board). Each case: what the fake shows, what it
answers to a newline and to Ctrl-C; expected exit code and whether a Ctrl-C may be sent at all.
  test-console-stop.py [path/to/console-stop.py]"""
import os, pty, sys, time, subprocess, threading, tempfile, tty
CS = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "console-stop.py")
def fake(mode, m, got, stop):
    buf = b""
    while not stop.is_set():
        try: c = os.read(m, 1024)
        except OSError: break
        got.extend(c); buf += c
        if b"\n" in c or b"\r" in c:
            if mode == "arm": os.write(m, b"\r\n/root/xv6run # ")
            elif mode.startswith("xv6"): os.write(m, b"\n$ ")
            elif mode == "busy": os.write(m, b"iteration 12345 still going\n")
            elif mode == "busy-dollar": os.write(m, b"$ 5 of 8 children done, still running\n")   # a '$ ' not at the end is not a prompt
            # silent: nothing
        if b"\x03" in c:
            if mode == "xv6": os.write(m, b"xv6 host exited (status 130); lock released. Relaunch with: ./xv6-pipe.sh\r\n/root/xv6run # ")
            # xv6-hang: the host never exits
def run(mode):
    m, s = pty.openpty(); tty.setraw(s); name = os.ttyname(s); got = bytearray(); stop = threading.Event()
    t = threading.Thread(target=fake, args=(mode, m, got, stop), daemon=True); t.start()
    tr = tempfile.mktemp()
    r = subprocess.run([sys.executable, CS, tr, "--wait", "3", "--device", name], capture_output=True, text=True, timeout=60)
    stop.set(); os.close(s)
    return r.returncode, bytes(got), r.stdout.strip()
cases = [("arm", 0, False), ("xv6", 0, True), ("xv6-hang", 3, True), ("busy", 2, False), ("busy-dollar", 2, False), ("silent", 2, False)]
bad = 0
for mode, want, ctrlc in cases:
    rc, got, out = run(mode); sent = b"\x03" in got; nl = got.count(b"\n") + got.count(b"\r")
    ok = rc == want and sent == ctrlc and nl == 1
    bad += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {mode:9s} rc={rc} (want {want}) ctrl-c={sent} (want {ctrlc}) newlines={nl} (want 1) | {out}")
print("SELFTEST", "PASS" if bad == 0 else f"FAIL {bad}"); sys.exit(1 if bad else 0)
