#!/usr/bin/env python3
"""Send a file to the board over the console, by streaming it into one `base64 -d`.

There is no network on this board and its root filesystem is a RAM initramfs, so the console is the only
channel. The obvious approach -- append a chunk per shell command -- was measured first and is unusable:
the round trip costs about a second whatever the chunk size, and the tty's canonical line limit caps a
command near 512 characters, which works out at roughly 380 bytes/s, or about six hours for this bundle.

So the transfer is one command. `base64 -d > file` reads until end of input; the payload is streamed into
it as ordinary lines and terminated with EOT. Three details make that safe rather than merely fast:

  * **XON/XOFF.** There is no hardware flow control here, and at 115200 a continuous stream will overrun
    the board's input buffer. Software flow control is enabled on both ends. It is safe *because the
    payload is base64*: the alphabet is A-Za-z0-9+/=, which cannot contain XON (0x11) or XOFF (0x13).
    This would be unsound for raw binary, which is part of why the data is base64 at all.
  * **echo off** for the duration. Echoing every byte back doubles the board's work and fills the return
    path with the payload. It is restored afterwards.
  * **verification on the board**: the decoded file's sha256 is read back and compared with the hash
    computed here. A mismatch fails; there is no retry loop.

  send-file.py <local> <remote> [--log L]
"""
import argparse, base64, glob, hashlib, os, re, sys, time
import serial

BY_ID = "/dev/serial/by-id/usb-Digilent*Adept*-if01-port0"
LINE = 128                      # base64 characters per line; well under any canonical line limit

ap = argparse.ArgumentParser()
ap.add_argument("local"); ap.add_argument("remote")
ap.add_argument("--log", default=None)
a = ap.parse_args()

data = open(a.local, "rb").read()
want = hashlib.sha256(data).hexdigest()
b64 = base64.b64encode(data).decode()
m = sorted(glob.glob(BY_ID))
if not m: sys.exit("no Digilent console found")
port = os.path.realpath(m[0])
log = open(a.log, "ab") if a.log else None

s = serial.Serial(port, 115200, timeout=0.5, xonxoff=True)

def note(msg):
    line = f"### {time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)
    if log: log.write((line + "\n").encode()); log.flush()

def run(cmd, timeout=60):
    tag = f"__R{int(time.time()*1000) % 1000000}__"
    s.reset_input_buffer()
    s.write((cmd + f"; echo {tag}=$?\n").encode()); s.flush()
    deadline = time.time() + timeout
    buf = b""
    while time.time() < deadline:
        buf += s.read(4096)
        mm = re.search((tag + r"=(\d+)").encode(), buf)
        if mm:
            if log: log.write(buf); log.flush()
            return int(mm.group(1)), buf.decode("utf-8", "replace")
    if log: log.write(buf); log.flush()
    return None, buf.decode("utf-8", "replace")

note(f"{os.path.basename(a.local)} -> {a.remote}: {len(data)} bytes, sha256 {want[:16]}")
rc, _ = run(f"mkdir -p $(dirname {a.remote})")
if rc != 0: sys.exit(f"REFUSE: cannot create the directory for {a.remote} (exit {rc})")

# echo off and software flow control on, for the duration of the stream
rc, _ = run("stty -echo ixoff")
if rc != 0: note(f"warning: stty returned {rc}; continuing")

s.reset_input_buffer()
s.write(f"base64 -d > {a.remote}\n".encode()); s.flush()
time.sleep(0.5)

t0 = time.time()
sent = 0
try:
    for i in range(0, len(b64), LINE):
        s.write((b64[i:i + LINE] + "\n").encode())
        sent += LINE
        if (i // LINE) % 200 == 0:
            s.flush()
            el = time.time() - t0
            rate = sent / el if el > 0 else 0
            eta = (len(b64) - sent) / rate if rate > 0 else 0
            note(f"{min(sent,len(b64))}/{len(b64)} b64 chars, {rate/1024:.1f} KB/s, eta {eta/60:.1f} min")
    s.write(b"\x04")            # EOT: end of input for base64 -d
    s.flush()
finally:
    time.sleep(1.0)

el = time.time() - t0
note(f"stream finished in {el:.0f}s")
time.sleep(1.0)
rc, _ = run("stty echo", 30)

rc, out = run(f"sha256sum {a.remote}", 240)
mm = re.search(r"\b([0-9a-f]{64})\b", out)
if not mm:
    sys.exit(f"FAIL: no sha256 came back: {out[-300:]!r}")
got = mm.group(1)
if got != want:
    rc2, sz = run(f"wc -c < {a.remote}", 60)
    sys.exit(f"FAIL: the board has {got}, expected {want}. Size on board: {sz.strip()[:80]!r}")
note(f"sha256 verified on the board: {got}")
note(f"SEND_OK {a.remote} {len(data)} bytes in {el:.0f}s ({len(data)/el/1024:.1f} KB/s)")
