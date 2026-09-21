#!/usr/bin/env python3
"""Unit-level checks on the transport itself.

The board *lifecycle* -- gate, claim, launch, confirmed remote exit, uncertainty -- is exercised end to end
by board-safety-selftest.sh against a fake remote board. What is left here is what that suite cannot show
as sharply: that the simulator path is untouched, that the remote command is built to the stated contract,
and that paths which cannot be carried safely through a remote shell are refused early rather than quoted
and hoped about.

  transport-selftest.py <fresh dir>
"""
import os, shlex, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from transport import (LocalTransport, BoardTransport, TransportError, UncertainState,
                       remote_quote, sha)
HERE = os.path.dirname(os.path.abspath(__file__))

out = sys.argv[1] if len(sys.argv) > 1 else None
if not out: print("usage: transport-selftest.py <fresh dir>"); sys.exit(2)
if os.path.exists(out): print(f"REFUSE: {out} exists"); sys.exit(2)
os.makedirs(out)

npass = nfail = 0
def ok(w):      global npass; npass += 1; print(f"  ok   : {w}")
def no(w, why): global nfail; nfail += 1; print(f"  FAIL : {w} -- {why}")
def want(c, w, why): ok(w) if c else no(w, why)

kernel = os.path.join(out, "kernel"); open(kernel, "w").write("k")
disk   = os.path.join(out, "fs.img"); open(disk, "w").write("d")
sim    = os.path.join(out, "sim");    open(sim, "w").write("s")

print("== 1. the simulator path is unchanged")
lt = LocalTransport(sim, kernel, disk, max_cycles=6000000000, progress=20000000)
want("+max-cycles=6000000000" in lt.argv and "+rd2_progress=20000000" in lt.argv,
     "the simulator still gets its plusargs", "the simulation runs must not be disturbed")
want(lt.platform == "simulator", "its platform is 'simulator'", "records must be distinguishable")
want(set(lt.identities()) == {"simulator", "kernel", "disk at start"},
     "its identity set is the simulator's", "a simulator record must not carry a bitstream")

print("== 2. the transport contract: the prefix takes ONE argument, a complete shell command")
tp = BoardTransport("ssh -p 2222 pynq", "/opt/fesvr-teaching", "/srv/fs-run.img", "/srv/kernel",
                    remote_lock="/tmp/board-test.lock", allow_test_lock=True, channel="multiplexed")
want(tp.prefix == ["ssh", "-p", "2222", "pynq"],
     "the prefix is parsed with shlex, so options survive", f"parsed to {tp.prefix}")
argv = tp._argv("echo hello world")
want(len(argv) == len(tp.prefix) + 1,
     "exactly one argument is appended to the prefix",
     f"{len(argv) - len(tp.prefix)} arguments were appended -- real ssh joins them and the grouping is lost")
want(argv[-1] == "echo hello world", "and it is the command verbatim", f"got {argv[-1]!r}")

print("== 3. remote paths that cannot be carried safely are refused early")
want(remote_quote("/srv/fs-run.img") == "/srv/fs-run.img", "an ordinary path passes through", "it did not")
for bad in ("/srv/my disk.img", "/srv/a'b", '/srv/a"b', "/srv/a;rm -rf /", "/srv/a$(x)", "/srv/a\nb", ""):
    try:
        remote_quote(bad)
        no(f"the unsafe path {bad!r} is refused", "it was accepted")
    except TransportError:
        ok(f"the unsafe path {bad!r} is refused")

print("== 4. the device lock")
try:
    BoardTransport("ssh pynq", "/h", "/d", "/k", channel="multiplexed")   # default: production lock
    ok("the production lock is the default")
except TransportError as e:
    no("the production lock is the default", str(e))
try:
    BoardTransport("ssh pynq", "/h", "/d", "/k", remote_lock="/tmp/other.lock",
                   channel="multiplexed")
    no("a non-production lock needs the test flag", "it was accepted")
except TransportError:
    ok("a non-production lock needs the test flag")

print("== 5. there is still no way to release the reset or reconfigure the PL")
import ast, tokenize

def code_only(path):
    """The source with comments and docstrings removed.

    Asking "does this file contain SYSTEM_RESET" of the raw text is useless here: the module explains at
    length that it must never write it, so the prose answers yes and the check reports a failure that is
    really a success. Docstrings are identified through the AST rather than guessed at from the token
    before them -- guessing got it wrong for every function, because after `def f():` the preceding
    significant token is `:` and not a newline.
    """
    tree = ast.parse(open(path).read())
    docs = set()
    for node in ast.walk(tree):
        if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            d = ast.get_docstring(node, clean=False)
            if d is not None: docs.add(d)
    out = []
    with open(path, "rb") as f:
        for tok in tokenize.tokenize(f.readline):
            if tok.type == tokenize.COMMENT: continue
            if tok.type == tokenize.STRING:
                try:
                    if ast.literal_eval(tok.string) in docs: continue
                except (ValueError, SyntaxError): pass
            out.append(tok.string)
    return " ".join(out).lower()

src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "transport.py")
code = code_only(src)
hits = [w for w in ("system_reset", "devcfg", "fpga_manager", "fpgautil", "reconfig") if w in code]
want(not hits, "the transport's code contains no reset or PL-reconfiguration call",
     f"found {hits} in code")
want("rm -rf" not in code, "and no recursive delete", "a recursive delete aimed by an option is back")


print("== the channel has no default")
try:
    BoardTransport("ssh pynq", "/h", "/d", "/k")
    no("a transport built without a channel is refused", "it was accepted, so a default came back")
except TransportError as e:
    want("channel was not given" in str(e),
         "a transport built without a channel is refused", f"wrong reason: {e}")
try:
    BoardTransport("ssh pynq", "/h", "/d", "/k", channel="exclusive")
    no("an exclusive transport with no device is refused", "it was accepted")
except TransportError as e:
    want("needs the console device" in str(e),
         "an exclusive transport with no device is refused", f"wrong reason: {e}")
try:
    BoardTransport("ssh pynq", "/h", "/d", "/k", channel="multiplexed", serial_device="/dev/tty")
    no("a device on a multiplexed channel is refused", "it was accepted")
except TransportError as e:
    want("only meaningful when the host owns the line" in str(e),
         "a device on a multiplexed channel is refused", f"wrong reason: {e}")


print("== control replies: a number in the stream is not an answer")
# Hardware session 2 recorded `# host exit: 595` and `# remote exit confirmed: yes`. 595 is the line
# number in `File ".../serial/serialposix.py", line 595, in read` -- our own crashed shim's traceback,
# scraped by a rule that took the last integer anywhere in the console stream. These checks pin the
# replacement: a reply is only a reply inside markers this side generated, and only if it is a bare
# integer in the range the value can actually take.
import tempfile as _tf

_ctl = _tf.mkdtemp(prefix="ctl-")

def _prefix_emitting(text, rc=0, tag="e"):
    """A transport prefix that ignores the command it is given and emits `text` instead."""
    pth = os.path.join(_ctl, "emit-%s.sh" % tag)
    with open(pth, "w") as f:
        f.write("#!/bin/sh\ncat <<'XEOF'\n" + text + "\nXEOF\nexit %d\n" % rc)
    os.chmod(pth, 0o755)
    return pth

def _tp(prefix):
    t = BoardTransport(prefix, "/h", "/d", "/k", remote_lock=os.path.join(_ctl, "b.lock"),
                       allow_test_lock=True, channel="multiplexed")
    t.lock = _ctl                      # so lock + '/exit' is a file this test controls
    return t

# the real thing first: a genuine record read back over a console that echoes the whole command, which is
# what a serial console does and what makes "find the value in the stream" hard in the first place
with open(os.path.join(_ctl, "exit"), "w") as f: f.write("130\n")
echoing = os.path.join(_ctl, "echoing.sh")
with open(echoing, "w") as f:
    f.write('#!/bin/sh\nprintf "~ # %s\\n" "$1"\n/bin/sh -c "$1"\nprintf "~ # "\n')
os.chmod(echoing, 0o755)
want(_tp(echoing).remote_exit() == 130,
     "a real record is read back through a console that echoes the whole command", "it was not")

THE_TRACEBACK = "\n".join([
    "Traceback (most recent call last):",
    '  File "/home/engineer/fpga/experiments/teaching-cpu/xv6-board-run/scripts/serial-transport.py", line 66, in <module>',
    "    chunk = s.read(65536)",
    '  File "/usr/lib/python3/dist-packages/serial/serialposix.py", line 595, in read',
    "    raise SerialException(",
    "serial.serialutil.SerialException: device reports readiness to read but returned no data "
    "(device disconnected or multiple access on port?)",
])

for i, (label, text, rc) in enumerate((
        ("the exact serialposix.py traceback from hardware session 2", THE_TRACEBACK, 0),
        ("a traceback whose line number is a VALID exit status", '  File "x.py", line 42, in read', 0),
        ("a bare number with no framing", "130", 0),
        ("an empty stream", "", 0),
        ("console furniture only", "~ # \n~ # ", 0),
)):
    try:
        v = _tp(_prefix_emitting(text, rc, tag=str(i))).remote_exit()
        no("%s is not taken as the remote exit" % label, "it returned %r" % (v,))
    except TransportError:
        ok("%s is not taken as the remote exit" % label)

# a control command that failed on the board is not an answer either
try:
    v = _tp(_prefix_emitting("cat: no such file", 1, tag="rc")).remote_exit()
    no("a control command that failed is not taken as an answer", "it returned %r" % (v,))
except TransportError as e:
    want("failed on the board" in str(e) or "not an answer" in str(e),
         "a control command that failed is not taken as an answer", "wrong reason: %s" % e)

# a second writer on the channel produces two framed replies; neither may be believed
dup = os.path.join(_ctl, "dup.sh")
with open(dup, "w") as f:
    f.write('#!/bin/sh\n/bin/sh -c "$1"\n/bin/sh -c "$1"\n')
os.chmod(dup, 0o755)
try:
    v = _tp(dup).remote_exit()
    no("two framed replies on one channel are refused", "it returned %r" % (v,))
except TransportError as e:
    want("several framed replies" in str(e), "two framed replies on one channel are refused",
         "wrong reason: %s" % e)

# out-of-range values: a shell status is 0..255, because `echo $?` cannot produce anything else
for val, what in (("256", "a status above 255"), ("-1", "a negative status"),
                  ("99999999999", "an absurd number")):
    with open(os.path.join(_ctl, "exit"), "w") as f: f.write(val + "\n")
    try:
        v = _tp(echoing).remote_exit()
        no("%s is refused as an exit status" % what, "it returned %r" % (v,))
    except TransportError:
        ok("%s is refused as an exit status" % what)

# a partially-written or garbled record is not half an answer
with open(os.path.join(_ctl, "exit"), "w") as f: f.write("1 3 0\n")
try:
    v = _tp(echoing).remote_exit()
    no("a record that is not a bare integer is refused", "it returned %r" % (v,))
except TransportError:
    ok("a record that is not a bare integer is refused")

# the one legitimate absence: the board has not written the record yet
os.remove(os.path.join(_ctl, "exit"))
want(_tp(echoing).remote_exit() is None,
     "a record the board has not written yet reads as absent, not as a value", "it did not")


print("== the pre-host lock cleanup: exactly one case, reported as it happens")
# Codex allowed this cleanup only for the empty directory THIS claim just created, before any host start,
# with a nonrecursive rmdir, and required that success and failure both be reported truthfully -- the
# first version ran `rmdir ... || true` and then said "was removed" whether or not it had been.
_cl = _tf.mkdtemp(prefix="claimclean-")

def _board_where_owner_write_fails(tag, poison):
    """A board on which mkdir succeeds and the owner write then cannot.

    `poison` runs right after the mkdir: 'ro' makes the new directory unwritable, 'occupied' also drops a
    file in it first, so the later rmdir has a non-empty directory and must refuse.
    """
    lock = os.path.join(_cl, tag + ".lock")
    pth = os.path.join(_cl, "board-" + tag + ".sh")
    extra = 'touch "$L/intruder"; ' if poison == "occupied" else ""
    with open(pth, "w") as f:
        f.write("#!/bin/sh\n"
                'L="%s"\n' % lock +
                'case "$1" in\n'
                '  *mkdir*) /bin/sh -c "$1"; r=$?; %schmod 555 "$L" 2>/dev/null; exit $r;;\n' % extra +
                '  *) exec /bin/sh -c "$1";;\n'
                'esac\n')
    os.chmod(pth, 0o755)
    t = BoardTransport(pth, "/h", "/d", "/k", remote_lock=lock, allow_test_lock=True,
                       channel="multiplexed")
    return t, lock

# -- the empty directory this claim made: removed, and said to be removed because it was
t, lock = _board_where_owner_write_fails("empty", "ro")
try:
    t.claim()
    no("a claim whose owner write fails does not succeed", "claim() returned normally")
except UncertainState as e:
    no("the empty lock this claim created is removed", "it was left behind: %s" % e)
except TransportError as e:
    want("was removed" in str(e), "the empty lock this claim created is removed",
         "wrong reason: %s" % e)
    want(not os.path.exists(lock), "  and it is really gone from the board",
         "the directory is still there")
    want("rmdir reported success" in str(e), "  and the message reports the removal that happened",
         "the message does not say what the rmdir did: %s" % e)

# -- a directory with something in it is NOT this claim's empty one: refused, and stays
t, lock = _board_where_owner_write_fails("occupied", "occupied")
try:
    t.claim()
    no("a lock that is not empty is not removed", "claim() returned normally")
except UncertainState as e:
    want("could NOT be removed" in str(e), "a lock that acquired contents is NOT removed",
         "wrong reason: %s" % e)
    want(os.path.exists(lock), "  and it is left exactly as it is", "it was removed anyway")
    want("nothing is retried" in str(e), "  and the failure is reported as uncertain, not softened",
         "the message does not say it stopped: %s" % e)
except TransportError as e:
    no("a lock that acquired contents is NOT removed", "reported as a clean refusal: %s" % e)

# The "no recursive delete" property is already checked in section 5, against source with comments and
# docstrings stripped. A plain text search here found `rm -rf` in release()'s docstring -- which exists to
# say the code must never do that -- and reported a failure. That is the same self-match as grepping for
# SYSTEM_RESET in a file documenting that it must not reset; the behavioural checks above are what matter,
# and the non-empty case proves the removal cannot reach anything this claim did not create.

print(f"TRANSPORT_SELFTEST pass={npass} fail={nfail}")
sys.exit(1 if nfail else 0)
