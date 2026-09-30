#!/usr/bin/env python3
"""Self-test of launch-test.py against a fake board console on a pty: a good board passes; a board that loses the
file across the restart, one without hart 1, and one whose host does not exit on Ctrl-C must each FAIL.
  test-launch-test.py [launch-test.py]"""
import os, pty, sys, threading, subprocess, tempfile, tty
LT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "launch-test.py")
def fake(m, mode, stop):
    st = "arm"; files = {}; line = b""
    def w(b): os.write(m, b)
    while not stop.is_set():
        try: c = os.read(m, 1024)
        except OSError: return
        for ch in c:
            ch = bytes([ch])
            if ch == b"\x03":
                if st == "xv6" and mode != "no-exit": w(b"^C\r\nxv6 host exited (status 130); lock released. Relaunch with: ./xv6-pipe-dual.sh\r\n/root/xv6run # "); st = "arm"
                continue
            w(ch if ch != b"\n" else b"\r\n")                      # echo, as both shells do
            if ch != b"\n": line += ch; continue
            cmd = line.decode(); line = b""
            if st == "arm":
                if "xv6-pipe-dual.sh" in cmd:
                    if mode == "no-persist": files.clear()
                    w(b"xv6 on the dual-pipeline system (2 harts)\r\n\nxv6 kernel is booting\n\n" + (b"" if mode == "no-hart1" else b"hart 1 starting\n") + b"init: starting sh\n$ "); st = "xv6"
                else: w(b"/root/xv6run # ")
            else:
                if cmd == "ls": w(b".              1 1 1024\nmtimetest      2 20 30000\nperfcompute    2 21 31000\nperfarray      2 22 32000\n$ ")
                elif cmd.startswith("echo p4c-persist > p4cmark"): files["p4cmark"] = b"p4c-persist\n"; w(b"$ ")
                elif cmd == "cat p4cmark": w(files.get("p4cmark", b"cat: cannot open p4cmark\n") + b"$ ")
                else: w(b"$ ")
def run(mode):
    m, s = pty.openpty(); tty.setraw(s); stop = threading.Event()
    threading.Thread(target=fake, args=(m, mode, stop), daemon=True).start()
    r = subprocess.run([sys.executable, LT, "/root/xv6run/fs-launchtest.img", tempfile.mktemp(), "--device", os.ttyname(s)], capture_output=True, text=True, timeout=300)
    stop.set(); return r.returncode, r.stdout
bad = 0
for mode, want, why in [("good", 0, None), ("no-persist", 1, "after the restart the file is still there"), ("no-hart1", 1, "'hart 1 starting'"), ("no-exit", 1, "host exited, lock released")]:
    rc, out = run(mode); fails = [l for l in out.splitlines() if l.startswith("LAUNCH FAIL")]
    ok = rc == want and (why is None and not fails or why is not None and any(why in l for l in fails))
    bad += not ok; print(f"{'ok  ' if ok else 'FAIL'} {mode:10s} rc={rc} (want {want}) first failures: {fails[:2]}")
print("SELFTEST", "PASS" if bad == 0 else f"FAIL {bad}"); sys.exit(1 if bad else 0)
