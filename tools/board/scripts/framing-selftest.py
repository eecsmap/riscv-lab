#!/usr/bin/env python3
"""The production framing parser, over every way the stream can be cut.

Imports `framing.Framer` from where `serial-transport.py` imports it -- the same module, not a copy.

The two defects being pinned down:
  * a retained marker prefix must survive any pause, because silence is not evidence that it was console
    text (the old code flushed everything after 150 ms);
  * a status is only a status once its terminator has arrived, because `__X1__=1` followed later by
    `30\\r\\n` is the number 130, and reading it as 1 records a wrong exit as though it were evidence.

  framing-selftest.py
"""
import os, sys

SHIM_DIR = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                        "..", "..", "xv6-board-run", "scripts"))
sys.path.insert(0, SHIM_DIR)
from framing import Framer            # noqa: E402  -- the production parser

npass = nfail = 0
def ok(w):      global npass; npass += 1; print(f"  ok   : {w}")
def no(w, why): global nfail; nfail += 1; print(f"  FAIL : {w} -- {why}")
def want(c, w, why=""): ok(w) if c else no(w, why)

TAG = "__X4242__"


def run(pieces):
    """Feed the parser a list of chunks; return (console text, status)."""
    f = Framer(TAG)
    out = b""
    for p in pieces:
        out += f.feed(p if isinstance(p, bytes) else p.encode())
        if f.status is not None:
            return out, f.status
    return out, None


print("== 1. every split boundary of a complete record")
stream = f"xv6 booting\n$ ls\nREADME\n$ {TAG}=130\r\n".encode()
bad = []
for cut in range(len(stream) + 1):
    out, st = run([stream[:cut], stream[cut:]])
    if st != 130 or b"__X" in out:
        bad.append((cut, st, out[-20:]))
want(not bad, f"a record split at any of {len(stream)+1} points still reads 130 and leaks no marker text",
     f"failed at {bad[:3]}")

print("== 2. byte-at-a-time, the worst case")
out, st = run([bytes([b]) for b in stream])
want(st == 130, "fed one byte at a time, the status is still 130", f"got {st}")
want(b"__X" not in out, "and no fragment of the marker reached the console", f"console tail {out[-30:]!r}")

print("== 3. a pause inside the marker, and inside the number")
# the old code flushed after 150ms of silence; the parser must not care how long the gap is
for label, pieces in (
        ("between tag and '='",    [f"$ {TAG}", f"=130\r\n"]),
        ("inside the tag",         [f"$ __X42", f"42__=130\r\n"]),
        ("inside the number",      [f"$ {TAG}=1", "30\r\n"]),
        ("before the terminator",  [f"$ {TAG}=130", "\r\n"]),
):
    out, st = run(pieces)
    want(st == 130, f"a pause {label} still yields 130", f"got {st}")
    want(b"__X" not in out and b"=1" not in out.replace(b"$ ", b""),
         f"  and nothing of the marker leaked while paused {label}", f"console {out!r}")

print("== 4. THE defect: an unterminated number is not a status")
f = Framer(TAG)
out = f.feed(f"$ {TAG}=1".encode())
want(f.status is None, "'=1' with no terminator does not become a status", f"status {f.status}")
want(b"__X" not in out, "  and it is retained, not emitted", f"emitted {out!r}")
out += f.feed(b"30\r\n")
want(f.status == 130, "  and once the rest arrives the status is 130, not 1", f"got {f.status}")

print("== 5. ordinary output leaves promptly, including a bare prompt")
f = Framer(TAG)
out = f.feed(b"xv6 kernel is booting\n$ ")
want(out == b"xv6 kernel is booting\n$ ",
     "a prompt with no newline is emitted at once, not held", f"emitted {out!r}")
f2 = Framer(TAG)
want(f2.feed(b"README  2 2 2441\n") == b"README  2 2 2441\n", "ordinary lines pass through unchanged")

print("== 6. text that merely resembles the marker")
for label, text in (("a different tag", b"$ __X9999__=7\r\n"),
                    ("the tag in prose", b"the marker is __X4242__ in this line\n")):
    f = Framer(TAG)
    out = f.feed(text)
    if label == "a different tag":
        want(f.status is None, f"{label} is not taken as our status", f"status {f.status}")
        want(out == text, f"  and it is passed through as console text", f"emitted {out!r}")
    else:
        # our tag with no '=' cannot complete; it is retained until something settles it
        out += f.feed(b"\n")
        want(f.status is None, f"{label} is not taken as a status", f"status {f.status}")

print("== 7. retention is bounded")
f = Framer(TAG)
f.feed(b"A" * 100000)
want(len(f.buf) == 0, "ordinary bulk output is not accumulated", f"retained {len(f.buf)} bytes")
f2 = Framer(TAG)
f2.feed(f"{TAG}=".encode() + b"9" * 50)
want(len(f2.buf) <= len(TAG) + 1 + 64, "a pending record retains only the record itself",
     f"retained {len(f2.buf)}")

print("== 8. at end of stream a never-completed prefix is console text after all")
f = Framer(TAG)
held = f.feed(f"$ {TAG}=13".encode())
want(held == b"$ ", "the prefix is held while the stream is open", f"emitted {held!r}")
want(f.flush() == f"{TAG}=13".encode(), "and flush() returns it at EOF", "flush lost it")

print("== 9. the PRODUCTION shim end to end, with a real pause inside the marker")
# Not the parser in isolation: the actual serial-transport.py process, on a PTY, with the bytes delivered
# in pieces separated by more than the 150 ms the old idle flush used.
import pty, subprocess, time, select, tempfile
SHIM = os.path.join(SHIM_DIR, "serial-transport.py")

def shim_case(label, pieces, expect_status, expect_console_has, expect_console_lacks=b"__X"):
    master, slave = pty.openpty()
    statusf = os.path.join(tempfile.mkdtemp(prefix="framing-"), "framed")
    p = subprocess.Popen([sys.executable, SHIM, "--device", os.ttyname(slave),
                          "--status-file", statusf, "true"],
                         stdout=subprocess.PIPE, stdin=subprocess.DEVNULL)
    time.sleep(0.6)
    # drain whatever the shim sent (its stty and the command line)
    while select.select([master], [], [], 0.2)[0]:
        os.read(master, 65536)
    # the shim addresses its marker to its own pid
    tag = f"__X{p.pid}__"
    for piece, gap in pieces:
        os.write(master, piece.replace("TAG", tag).encode())
        time.sleep(gap)
    try:
        out, _ = p.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        p.kill(); out = b""
        no(label, "the shim never framed the record and had to be killed"); return
    rc = p.returncode
    want(rc == expect_status, f"{label}: shim exits {expect_status}", f"exit {rc}")
    want(expect_console_has in out, f"  {label}: console output passed through", f"console {out[-60:]!r}")
    want(expect_console_lacks not in out, f"  {label}: no marker text leaked", f"console {out[-60:]!r}")
    ev = open(statusf).read().strip() if os.path.exists(statusf) else "(absent)"
    want(ev == f"MARKER={expect_status}", f"  {label}: framing evidence records {expect_status}", ev)
    os.close(master)

shim_case("a 400 ms pause inside the number",
          [("hello from the board\n$ TAG=1", 0.4), ("30\r\n", 0.1)],
          130, b"hello from the board")
# The tag is the shim's own pid, so the split must be computed at call time -- an earlier version wrote a
# literal "REST" for the tag's remainder, which of course never completed the marker.
def shim_case_split_tag():
    master, slave = pty.openpty()
    statusf = os.path.join(tempfile.mkdtemp(prefix="framing-"), "framed")
    p = subprocess.Popen([sys.executable, SHIM, "--device", os.ttyname(slave),
                          "--status-file", statusf, "true"],
                         stdout=subprocess.PIPE, stdin=subprocess.DEVNULL)
    time.sleep(0.6)
    while select.select([master], [], [], 0.2)[0]: os.read(master, 65536)
    tag = f"__X{p.pid}__"
    half = len(tag) // 2
    os.write(master, ("output\n$ " + tag[:half]).encode()); time.sleep(0.4)
    os.write(master, (tag[half:] + "=0\r\n").encode())
    try:
        out, _ = p.communicate(timeout=20)
    except subprocess.TimeoutExpired:
        p.kill(); no("a 400 ms pause inside the tag", "never framed"); os.close(master); return
    want(p.returncode == 0, "a 400 ms pause inside the tag: shim exits 0", f"exit {p.returncode}")
    want(b"output" in out, "  a 400 ms pause inside the tag: console passed through", f"{out[-60:]!r}")
    want(b"__X" not in out, "  a 400 ms pause inside the tag: no marker text leaked", f"{out[-60:]!r}")
    ev = open(statusf).read().strip() if os.path.exists(statusf) else "(absent)"
    want(ev == "MARKER=0", "  a 400 ms pause inside the tag: evidence records 0", ev)
    os.close(master)
shim_case_split_tag()

print("== 10. an incomplete marker authorises nothing")
master, slave = pty.openpty()
statusf = os.path.join(tempfile.mkdtemp(prefix="framing-"), "framed")
p = subprocess.Popen([sys.executable, SHIM, "--device", os.ttyname(slave),
                      "--status-file", statusf, "true"],
                     stdout=subprocess.PIPE, stdin=subprocess.DEVNULL)
time.sleep(0.6)
while select.select([master], [], [], 0.2)[0]: os.read(master, 65536)
os.write(master, f"$ __X{p.pid}__=13".encode())      # never terminated
time.sleep(1.0)
alive = p.poll() is None
want(alive, "with an unterminated record the shim does not exit", "it exited")
want(not os.path.exists(statusf), "  and writes no framing evidence",
     "evidence was written for an incomplete record")
p.kill(); p.wait(); os.close(master)

print(f"FRAMING_SELFTEST pass={npass} fail={nfail}")
sys.exit(1 if nfail else 0)
