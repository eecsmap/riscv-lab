#!/usr/bin/env python3
"""PIPE-P3b: boot-test the interactive launcher once, on a throwaway disk copy, then stop it the way the user will.
At the ARM prompt: `cd /root/xv6run && ./xv6-pipe.sh <disk>`; wait for xv6's `$ ` prompt; type `ls`; wait for the
next prompt and require mtimetest, perfcompute and perfarray in the listing; press Ctrl-C once; wait for the
launcher's "lock released" line and the ARM prompt. Every byte is written to <transcript>. The caller holds the
serial lease and nothing else reads the console.   launch-test.py <disk on the board> <transcript>"""
import sys, time, re, serial
disk, tr = sys.argv[1], sys.argv[2]
s = serial.Serial("/dev/ttyUSB1", 115200, timeout=0.05)
log = open(tr, "wb"); buf = b""
def expect(rx, sec):
    global buf
    t = time.time()
    while time.time() - t < sec:
        c = s.read(4096)
        if c: log.write(c); log.flush(); buf += c
        m = re.search(rx, buf, re.S)          # DOTALL: a prompt follows a CR/LF (the first version missed exactly this)
        if m: buf = buf[m.end():]; return True
    return False
def send(b): log.write(b"\n<<SEND " + repr(b).encode() + b">>\n"); s.write(b); s.flush()
ok = True; steps = []
s.reset_input_buffer(); send(b"\n")
steps.append(("ARM prompt", expect(rb"/root/xv6run # $|# $", 10)))
send(f"cd /root/xv6run && ./xv6-pipe.sh {disk}\n".encode())
steps.append(("xv6 shell prompt", expect(rb"init: starting sh.*?\$ ", 180)))
send(b"ls\n")
steps.append(("ls listing and next prompt", expect(rb"ls\r?\n.*?\$ ", 60)))
listing = open(tr, "rb").read().decode(errors="replace")
for cmd in ("mtimetest", "perfcompute", "perfarray"):
    steps.append((f"{cmd} present on the disk", re.search(rf"^{cmd}\s", listing, re.M) is not None))
time.sleep(1); send(b"\x03")
steps.append(("host exited, lock released", expect(rb"lock released", 30)))
steps.append(("ARM prompt again", expect(rb"# $", 10)))
log.close(); s.close()
for name, r in steps: print(f"LAUNCH {'ok  ' if r else 'FAIL'} {name}"); ok = ok and r
print(f"LAUNCH_TEST {'PASS' if ok else 'FAIL'}"); sys.exit(0 if ok else 1)
