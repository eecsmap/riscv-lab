#!/usr/bin/env python3
"""PIPE-P4c: test the interactive launcher on a THROWAWAY disk: launch, commands, stop, restart, stop (P3b's
launch-test.py extended with the restart). At the ARM prompt: `cd /root/xv6run && ./xv6-pipe-dual.sh <disk>`; wait for
xv6's `$ ` prompt (and require xv6's "hart 1 starting": both harts up); `ls` (mtimetest, perfcompute, perfarray must
be listed); `echo p4c-persist > p4cmark`; Ctrl-C once -> "lock released" and the ARM prompt; relaunch on the same
disk; `cat p4cmark` must print p4c-persist (the disk persisted across the restart); Ctrl-C once -> "lock released" and
the ARM prompt. Every byte is written to <transcript>. The caller holds the serial lease and nothing else reads the
console.   launch-test.py <disk on the board> <transcript> [--device /dev/ttyUSB1]"""
import sys, time, re, serial
disk, tr = sys.argv[1], sys.argv[2]
dev = sys.argv[sys.argv.index("--device") + 1] if "--device" in sys.argv else "/dev/ttyUSB1"
s = serial.Serial(dev, 115200, timeout=0.05)
log = open(tr, "wb"); buf = b""; seen = b""
def expect(rx, sec):
    global buf, seen
    t = time.time()
    while time.time() - t < sec:
        c = s.read(4096)
        if c: log.write(c); log.flush(); buf += c; seen += c
        m = re.search(rx, buf, re.S)          # DOTALL: a prompt follows a CR/LF
        if m: buf = buf[m.end():]; return True
    return False
def send(b): log.write(b"\n<<SEND " + repr(b).encode() + b">>\n"); s.write(b); s.flush()
steps = []
def boot(n):
    global seen
    seen = b""; send(f"cd /root/xv6run && ./xv6-pipe-dual.sh {disk}\n".encode())
    steps.append((f"launch {n}: xv6 shell prompt", expect(rb"init: starting sh.*?\$ ", 180)))
    steps.append((f"launch {n}: 'hart 1 starting' on the console", b"hart 1 starting" in seen))
def stop(n):
    time.sleep(1); send(b"\x03")
    steps.append((f"stop {n}: host exited, lock released", expect(rb"lock released", 30)))
    steps.append((f"stop {n}: ARM prompt again", expect(rb"# $", 10)))
s.reset_input_buffer(); send(b"\n")
steps.append(("ARM prompt", expect(rb"/root/xv6run # $|# $", 10)))
boot(1)
send(b"ls\n"); steps.append(("ls listing and next prompt", expect(rb"ls\r?\n.*?\$ ", 60)))
listing = open(tr, "rb").read().decode(errors="replace")
for cmd in ("mtimetest", "perfcompute", "perfarray"):
    steps.append((f"{cmd} present on the disk", re.search(rf"^{cmd}\s", listing, re.M) is not None))
send(b"echo p4c-persist > p4cmark\n"); steps.append(("write a file", expect(rb"p4cmark\r?\n.*?\$ ", 30)))
stop(1)
boot(2)
send(b"cat p4cmark\n"); steps.append(("after the restart the file is still there", expect(rb"cat p4cmark\r?\n\s*p4c-persist\r?\n.*?\$ ", 30)))
stop(2)
log.close(); s.close(); ok = True
for name, r in steps: print(f"LAUNCH {'ok  ' if r else 'FAIL'} {name}"); ok = ok and r
print(f"LAUNCH_TEST {'PASS' if ok else 'FAIL'}"); sys.exit(0 if ok else 1)
