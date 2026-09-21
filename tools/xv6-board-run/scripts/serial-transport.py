#!/usr/bin/env python3
"""A transport that satisfies BoardTransport's contract over the serial console.

The contract is: *the prefix is invoked with exactly one further argument, a complete shell command, and
executes it with a shell on the board, passing stdin and stdout through untouched.* `ssh host` satisfies it.
This board has no network at all -- its root filesystem is a RAM initramfs -- so the console is the only
channel, and this is the shim that makes it fit.

It is a shim and not a general terminal: it owns the port for one command, sends it with a unique
end-marker, bridges stdin to the port and the port to stdout, and exits with the status the board reported.
The marker is how a command's end is known, because a console has no other end-of-command signal.

Two things it deliberately does NOT do: it never writes SYSTEM_RESET, and it never touches /dev/xdevcfg.
Programming is a separate, explicit step performed by a person's command, not something a transport can do
as a side effect.

  serial-transport.py [--device DEV] [--status-file F] '<complete shell command>'

`--device` exists so the offline tests drive **this** script -- the production one -- against a PTY, rather
than a near-copy of it that could drift. `--status-file` is how the caller learns whether the end marker
was actually seen: the file is written only in that case, so "the local process exited" and "the remote
command completed" stop being the same fact. They are not the same fact, and treating them as one is what
let diagnostic bytes reach a live host in the first hardware session.
"""
import glob, os, re, select, sys, time
import serial

BY_ID = "/dev/serial/by-id/usb-Digilent*Adept*-if01-port0"

import argparse
ap = argparse.ArgumentParser()
ap.add_argument("command")
ap.add_argument("--device", default=None)
ap.add_argument("--status-file", default=None)
args = ap.parse_args()
cmd = args.command

if args.device:
    port = args.device
else:
    m = sorted(glob.glob(BY_ID))
    if not m:
        sys.exit("no Digilent console found")
    port = os.path.realpath(m[0])
s = serial.Serial(port, 115200, timeout=0.05, xonxoff=True)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from framing import Framer          # the production parser; the tests import this same module

tag = f"__X{os.getpid()}__"
framer = Framer(tag)

# Echo off: the console would otherwise echo every character typed at the target back into the stream,
# and the driver reconstructs the console from exactly this stream.
s.write(b"stty -echo\n"); s.flush(); time.sleep(0.3)
s.reset_input_buffer()
s.write((cmd + f"; echo {tag}=$?\n").encode()); s.flush()

status = None
stdin_open = True
out = sys.stdout.buffer

while status is None:
    r, _, _ = select.select([s.fileno()] + ([sys.stdin.fileno()] if stdin_open else []), [], [], 0.1)
    if s.fileno() in r:
        chunk = s.read(65536)
        if chunk:
            # Emit what cannot be part of a marker, immediately. A prompt ("$ " with no newline) leaves
            # here at once; a marker prefix is held however long the pause, because silence is not evidence
            # that it was console text.
            piece = framer.feed(chunk)
            if piece:
                out.write(piece); out.flush()
            if framer.status is not None:
                status = framer.status
                break
    if stdin_open and sys.stdin.fileno() in r:
        data = os.read(sys.stdin.fileno(), 4096)
        if not data:
            stdin_open = False
        else:
            s.write(data); s.flush()

# Positive framed evidence, and only that. The status file is written **only** when the end marker was
# actually seen, which means the command completed and the shell came back. If this process dies for any
# other reason -- a crash, a disconnected link, a kill -- the file is absent, and the caller must treat the
# channel as still owned by whatever was running.
if status is not None and args.status_file:
    with open(args.status_file, "w") as f:
        f.write(f"MARKER={status}\n")

if status is not None:
    s.write(b"stty echo\n"); s.flush(); time.sleep(0.2)
s.close()
sys.exit(status if status is not None else 1)
