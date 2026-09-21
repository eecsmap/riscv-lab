#!/usr/bin/env python3
"""The exclusive-channel lifecycle, against a PTY fake that behaves like a real console.

What this is for: the first hardware session failed because `BoardTransport` read the remote pid back with
a *second* command while the host owned the serial console. Every offline fake until now could always run
another command, so nothing caught it. These checks use a one-channel fake and assert the properties that
matter on hardware:

  * no out-of-band command may be issued while the host owns the channel, and **zero** bytes reach the
    host's stdin from this side;
  * an interrupt is a mechanism, not proof: the run is only over when the wrapper's recorded exit status
    is read back, after the channel is free;
  * a host that ignores the interrupt, or a wrapper whose marker is lost, leaves the state uncertain with
    ownership retained and nothing reset;
  * the multiplexed (ssh) path still behaves as before.

  exclusive-selftest.py <fresh dir>
"""
import os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from transport import BoardTransport, TransportError, UncertainState   # noqa: E402

out = sys.argv[1] if len(sys.argv) > 1 else None
if not out: sys.exit("usage: exclusive-selftest.py <fresh dir>")
if os.path.exists(out): sys.exit(f"REFUSE: {out} exists")
os.makedirs(out)

npass = nfail = 0
def ok(w):      global npass; npass += 1; print(f"  ok   : {w}")
def no(w, why): global nfail; nfail += 1; print(f"  FAIL : {w} -- {why}")
def want(c, w, why): ok(w) if c else no(w, why)

def start_board(mode, name):
    """Bring up a PTY fake and return (process, slave device path, state dir)."""
    st = os.path.join(out, name); os.makedirs(st, exist_ok=True)
    p = subprocess.Popen([sys.executable, os.path.join(HERE, "pty_board.py"), st, "--host-mode", mode],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    dev = p.stdout.readline().decode().strip()
    return p, dev, st

def make_tp(dev, st, **kw):
    # The PRODUCTION shim, pointed at this PTY with --device. There used to be a `pty_shim.py` clone here;
    # a near-copy of the framing logic is exactly the thing that can drift away from what actually runs on
    # hardware, and it did -- it had no --status-file, so it could not frame a completion at all.
    shim = os.path.join(HERE, "..", "..", "xv6-board-run", "scripts", "serial-transport.py")
    return BoardTransport(f"{sys.executable} {os.path.abspath(shim)} --device {dev}",
                          "/b/fesvr-teaching-static", "/b/fs-run.img", "/b/kernel-128mib",
                          remote_lock=os.path.join(st, "board.lock"), allow_test_lock=True,
                          remote_boot_id="/proc/sys/kernel/random/boot_id",
                          # the line it locks must be the line the shim opens; the transport now checks
                          # that these two are the same device, so both are stated here
                          channel="exclusive", serial_device=dev, **kw)

print("== 1. a normal run: the host owns the channel, and nothing of ours reaches it")
bp, dev, st = start_board("normal", "normal")
try:
    tp = make_tp(dev, st)
    bid = tp.remote_boot_id()
    want(bid == "9e62de9e-f7f1-4cf4-93f0-060bff64ae3b",
         "a boot id with the board's trailing NUL is read and normalised", f"got {bid!r}")
    tp.claim(); ok("ownership claimed")
    tp.start()
    time.sleep(0.5)
    try:
        tp._run("echo probe")
        no("an out-of-band command is refused while the host owns the channel", "it was issued")
    except TransportError as e:
        ok("an out-of-band command is refused while the host owns the channel")
        want("into TSI" in str(e) or "stdin" in str(e), "  and the refusal says why", str(e)[:80])
    ev = tp.stop(timeout=20)
    want(ev == 0, f"stop() returns the wrapper's recorded exit ({ev})", "no recorded exit")
    want(tp.state == "remote-exit-confirmed", "the state is remote-exit-confirmed", tp.state)
    injected = int(open(os.path.join(st, "injected-count")).read())
    want(injected == 0, f"ZERO diagnostic bytes reached the host's stdin (counted {injected})",
         f"{injected} bytes were injected into the host -- this is what made the target unknown")
    want(tp.release() is True, "ownership released after a confirmed exit", "it was not released")
finally:
    bp.kill()

print("== 2. a host that ignores the interrupt")
bp, dev, st = start_board("deaf", "deaf")
try:
    tp = make_tp(dev, st)
    tp.remote_boot_id(); tp.claim(); tp.start()
    time.sleep(0.5)
    try:
        tp.stop(timeout=3)
        no("an ignored interrupt leaves the state uncertain", "stop() reported success")
    except UncertainState as e:
        ok("an ignored interrupt leaves the state uncertain")
        want(tp.owned, "  ownership is NOT released", "ownership was dropped")
        want(tp.state == "uncertain", "  the state is recorded as uncertain", tp.state)
        want("cold platform restart" in str(e), "  and a cold restart is required", str(e)[:80])
finally:
    bp.kill()

print("== 3. the wrapper's exit marker is lost")
bp, dev, st = start_board("nomarker", "nomarker")
try:
    tp = make_tp(dev, st)
    tp.remote_boot_id(); tp.claim(); tp.start()
    time.sleep(0.5)
    try:
        tp.stop(timeout=10)
        no("a lost exit marker leaves the state uncertain", "stop() reported success")
    except UncertainState as e:
        ok("a lost exit marker leaves the state uncertain")
        want("not proof of termination" in str(e), "  and it says an interrupt is not proof", str(e)[:90])
        want(tp.owned, "  ownership is NOT released", "ownership was dropped")
finally:
    bp.kill()

print("== 4. no reset or PL recovery exists on any of these paths")
import ast, tokenize
def code_only(path):
    tree = ast.parse(open(path).read()); docs = set()
    for n in ast.walk(tree):
        if isinstance(n, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            d = ast.get_docstring(n, clean=False)
            if d is not None: docs.add(d)
    toks = []
    with open(path, "rb") as f:
        for t in tokenize.tokenize(f.readline):
            if t.type == tokenize.COMMENT: continue
            if t.type == tokenize.STRING:
                try:
                    if ast.literal_eval(t.string) in docs: continue
                except (ValueError, SyntaxError): pass
            toks.append(t.string)
    return " ".join(toks).lower()
code = code_only(os.path.join(HERE, "transport.py"))
hits = [w for w in ("system_reset", "devcfg", "fpga_manager", "fpgautil", "reconfig") if w in code]
want(not hits, "the transport's code still contains no reset or PL call", f"found {hits}")

print(f"EXCLUSIVE_SELFTEST pass={npass} fail={nfail}")
sys.exit(1 if nfail else 0)
