#!/usr/bin/env python3
"""The board run itself, with the transport handed in.

Split out of `board-runner.py` so that the production entry point and the offline tests exercise **the same
logic**. Review found the previous arrangement wrong in a way that is easy to make and hard to see: the
production CLI carried `--allow-test-lock` and `--remote-boot-id`, so the switches that let a test point at
a fake board were also available to a real `ssh` invocation, and a production run could be aimed at a lock
that excludes nothing. Test-only knobs now exist only in the test entry point, which constructs a transport
and calls `run()` here; the production CLI constructs the production transport and calls the same `run()`.
"""
import os, re, select, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "xv6-boot", "scripts"))
from transport import BoardTransport, TransportError, UncertainState   # noqa: E402
from board_gate import gate, GateError                            # noqa: E402
from xv6_console import (DRIVER_VERSION, EXPECTED, PROMPT, PARTIAL_EVENT_OK,  # noqa: E402
                         command_output, output_matches)


def build_transport(a, expect, test_overrides=None):
    """Construct the board transport from parsed arguments. **The only place that does.**

    This function exists because the two entry points each built their own, and they drifted. The
    production CLI's constructor call lost `channel` and `serial_device` when the test-only options were
    split out of it -- it went on parsing `--channel`, marked required and documented, and silently
    dropped it one line later. The transport then defaulted to multiplexed, and a serial console was
    driven as though a second session existed. Nothing caught it, because every test reached the runner
    through the *other* entry point, which did pass them.

    So the option-to-constructor mapping lives here and both entries call it. A test injects its fake
    board through `test_overrides`, which is additive: it cannot remove or alter the plumbing above it,
    only add the lock and boot-id knobs that must never exist on the production CLI.
    """
    kw = dict(expect=expect, channel=a.channel, serial_device=a.serial_device)
    if test_overrides:
        overlap = set(test_overrides) & set(kw)
        if overlap:
            raise ValueError(f"a test override may not replace production plumbing: {sorted(overlap)}")
        kw.update(test_overrides)
    return BoardTransport(a.transport_cmd, a.host_binary, a.disk, a.kernel, **kw)


def parse_expect(pairs):
    """REMOTE_PATH=SHA256, rejecting a conflict *before* it can be discarded.

    The previous loop was `expect[k] = v`, so a second --expect for the same path silently replaced the
    first and the later conflict check had nothing left to find -- the guarantee was stated and not
    implemented. Identical repeats are accepted; contradictory ones are refused here, before anything is
    built and before any remote command.
    """
    expect = {}
    for e in pairs:
        if "=" not in e:
            raise ValueError(f"--expect {e!r} is not REMOTE_PATH=SHA256")
        k, v = e.split("=", 1)
        v = v.strip()
        if k in expect and expect[k] != v:
            raise ValueError(
                f"--expect gives {k} two different hashes: {expect[k]} and {v}. "
                f"A contradiction is not a preference; say which one is approved.")
        expect[k] = v
    return expect


class ConsolePump:
    """Reads a session's stdout, separates console text from the harness's event lines, and is bounded.

    This is module level, and `run()` uses exactly this, so a test can drive the production implementation
    instead of a copy of it. That distinction is not pedantic: the drain regression that was supposed to
    prove boundedness was a reimplementation living in the test, so it proved only that the copy was
    bounded -- and review found it counting a 34.16 s UNBOUNDED result as success.
    """

    def __init__(self, stdout, poll, emit, event_re):
        self.stdout = stdout
        self.poll = poll
        self.emit = emit
        self.event = event_re
        self.pending = b""
        self.rawlog = None

    def pump(self, deadline, drain=False):
        """Read until `deadline` (monotonic). Returns False once the session has ended and been drained."""
        while True:
            chunk = b""
            r, _, _ = select.select([self.stdout], [], [], 0.2)
            if r:
                chunk = self.stdout.read(65536) or b""
                if chunk:
                    if self.rawlog:
                        self.rawlog.write(chunk.decode("utf-8", "replace")); self.rawlog.flush()
                    self.pending += chunk
                    *lines, self.pending = self.pending.split(b"\n")
                    for ln in lines:
                        t = ln.decode("utf-8", "replace")
                        m = self.event.search(t)
                        if m:
                            frag = t[:m.start()]
                            if frag: self.emit(frag)
                        else:
                            self.emit(t + "\n")
            if self.poll() is not None and not chunk:
                if self.pending:
                    t = self.pending.decode("utf-8", "replace"); self.pending = b""
                    m = self.event.search(t)
                    frag = t[:m.start()] if m else t
                    if frag: self.emit(frag)
                return False
            # Bounded on EVERY path, drain included, on the monotonic clock. This previously read
            # `if not drain and ...`, so a drain never timed out: fine while a session always ends, but on
            # an exclusive channel an uncertain stop leaves it alive on purpose and the runner would hang
            # for ever *after* correctly reporting the uncertainty.
            if time.monotonic() > deadline:
                return True


def run(a, tp, expect):
    """Drive the board and write the transcript. `a` is the parsed arguments; `tp` an started-less
    transport. Returns the process exit code."""
    os.makedirs(a.outdir, exist_ok=True)
    rawlog = open(os.path.join(a.outdir, "run.log"), "w")
    conlog = open(os.path.join(a.outdir, "console.txt"), "w")
    EVENT = re.compile(r"((AT|RD2|EV|EVA|EVH|RD2HOST|RBOOT)\s+\d+\s+\S.*)$")
    console, stages = [], []
    t0 = time.time()

    try:
        roles = {"host binary": a.host_binary, "kernel": a.kernel, "disk at start": a.disk}
        ident = gate(tp, a.evidence_dir, expect, roles=roles)
    except (GateError, TransportError) as e:
        print(f"REFUSE: {e}")
        print("No host was launched.")
        return 2

    try:
        tp.claim()
    except UncertainState as e:
        # The board was touched and its state could not be established. A message on stdout is not a
        # record: the fact has to outlive the process, because the next person to look at this board needs
        # to know that something of ours may still be on it.
        with open(os.path.join(a.outdir, "UNCERTAIN.txt"), "w") as f:
            f.write(f"UNCERTAIN during claim, {time.strftime('%FT%T')}\n\n{e}\n\n"
                    f"lock: {tp.lock}\n"
                    f"No host was launched. Nothing was retried and nothing was cleaned up.\n")
        print(f"UNCERTAIN: {e}")
        print("No host was launched.")
        return 3
    except TransportError as e:
        print(f"REFUSE: {e}")
        print("No host was launched.")
        return 2

    # Canonical identity names, so a board record is the same shape the checker expects and the remote hashes
    # are bound to the roles they play rather than to their basenames.
    remote_h = {k[len("remote path "):]: v for k, v in ident.items() if k.startswith("remote path ")}
    # By full path. The gate has already refused anything missing, so a KeyError here would be a bug rather
    # than a condition -- there is deliberately no "MISSING" default to fall back on.
    ident_out = {
        "bitstream":     a.bitstream_sha,
        "host binary":   remote_h[a.host_binary],
        "kernel":        remote_h[a.kernel],
        "disk at start": remote_h[a.disk],
    }
    notes_out = {
        "memory evidence session": ident["memory evidence session"],
        "memory evidence digest":  ident["memory evidence digest"],
        "board boot id":           ident["board boot id"],
    }
    tp.start(extra_ident=ident_out)

    def emit(text):
        console.append(text); conlog.write(text); conlog.flush()


    _pump = ConsolePump(tp.stdout, tp.poll, emit, EVENT)
    _pump.rawlog = rawlog
    state = _pump.__dict__            # so text() can see the retained bytes
    def pump(deadline, drain=False):
        return _pump.pump(deadline, drain)


    def text():
        tail = _pump.pending.decode("utf-8", "replace")
        m = PARTIAL_EVENT_OK.search(tail)
        if m: tail = tail[:m.start()]
        return "".join(console) + tail


    def wait_for(pattern, what, timeout):
        # Deadlines are monotonic throughout; time.time() appears only in the elapsed figures printed and
        # recorded for a reader. Mixing the two silently "works" because one is far larger than the other,
        # which is a bad reason for anything to work.
        rx = re.compile(pattern)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if rx.search(text()):
                stages.append((what, round(time.time() - t0, 1), "ok"))
                print(f"  [{time.time()-t0:7.1f}s] {what}: seen")
                return True
            if not pump(min(deadline, time.monotonic() + 2.0)):
                break
        stages.append((what, round(time.time() - t0, 1), "TIMEOUT"))
        print(f"  [{time.time()-t0:7.1f}s] {what}: NOT seen within {timeout}s")
        return False


    def send(line):
        tp.stdin.write((line + "\n").encode()); tp.stdin.flush()
        print(f"  [{time.time()-t0:7.1f}s] typed: {line!r}")


    # Bounded phase logging. When a teardown stalls, the question is *where*, and a transcript that stops
    # mid-sentence does not say. Each phase records its start and end with a monotonic elapsed time, to the
    # run directory, flushed immediately, so an externally killed run still shows the phase it died in.
    phaselog = open(os.path.join(a.outdir, "phases.txt"), "w")
    def phase(name):
        phaselog.write(f"{time.monotonic() - m0:8.2f}  {name}\n"); phaselog.flush()
        print(f"  [phase {time.monotonic() - m0:7.2f}s] {name}", flush=True)
    m0 = time.monotonic()
    phase("commands: begin")

    result = {"stopped": "unknown"}
    try:
        ok_boot = wait_for(r"xv6 kernel is booting", "kernel banner", a.startup_timeout)
        wait_for(r"init: starting sh|\$ ", "init started / first prompt", a.stage_timeout)
        ok_shell = wait_for(r"\$ ", "shell prompt", a.stage_timeout)
        if not ok_shell:
            result["stopped"] = "no-shell-prompt"
        else:
            result["stopped"] = "deliberate-stop-after-all-commands"
            done = 0
            for name, cmd, out_rx in EXPECTED:
                before = text().count(PROMPT)
                send(cmd)
                deadline = time.monotonic() + a.stage_timeout
                alive = True
                while text().count(PROMPT) <= before and time.monotonic() < deadline:
                    if not pump(min(deadline, time.monotonic() + 2.0)):
                        alive = False; break
                returned = text().count(PROMPT) > before
                idx, body = command_output(text(), cmd, after=done)
                ok = returned and output_matches(body, out_rx)
                if idx is not None: done = idx + 1
                stages.append((f"command {name}", round(time.time() - t0, 1), "ok" if ok else "FAILED"))
                print(f"  [{time.time()-t0:7.1f}s] command {name}: {'ok' if ok else 'NOT satisfied'}")
                if not ok:
                    result["stopped"] = ("host-exited-during-command:" + name if not alive
                                         else "stopped-after-failed-command:" + name)
                    break
    finally:
        phase("commands: end; teardown begins")
        # Ask the host to stop, and confirm ON THE BOARD that it did. Signalling the local session would only
        # kill the session: the remote process can outlive it and keep its mapping of the adapter. Nothing here
        # releases the restart request or reconfigures the PL -- stopping a host never asserted reset, and a
        # design that may still have a transfer in flight is left held on purpose.
        rc, uncertain = None, None
        phase("teardown: settle pump")
        pump(time.monotonic() + 0.5)
        phase("teardown: stop()")
        try:
            rc = tp.stop(timeout=a.stop_timeout)
            phase(f"teardown: stop() returned {rc}")
            result["remote exit confirmed"] = "yes"
            if result["stopped"] == "unknown":
                result["stopped"] = f"host-exited-on-its-own:{rc}"
        except UncertainState as e:
            uncertain = str(e)
            result["stopped"] = "uncertain-remote-state"
            result["remote exit confirmed"] = "no"
            phase("teardown: stop() -> UNCERTAIN")
        # Bounded. The drain used to loop until the session ended, which is fine when it always does -- but
        # on an exclusive channel an uncertain stop leaves the session alive on purpose, and the runner
        # would then hang for ever after correctly reporting the uncertainty. A run that has decided its
        # verdict must still finish and write its transcript.
        phase("teardown: final drain")
        pump(time.monotonic() + 5, drain=True)
        phase("teardown: drain done")
        if uncertain is None:
            try:
                tp.release()                  # only ever after a confirmed remote exit, and only our own lock
            except UncertainState as e:
                uncertain = str(e)
                result["stopped"] = "uncertain-lock-state"
                phase("teardown: release() -> UNCERTAIN")
        phase("teardown: closing logs")
        rawlog.close(); conlog.close(); phaselog.close()

    bad = [s for s in stages if s[2] != "ok"]
    if uncertain: bad = bad or [("uncertain", 0, "UNCERTAIN")]
    with open(os.path.join(a.outdir, "stages.txt"), "w") as f:
        for name, t, st in stages: f.write(f"{st}\t{t}\t{name}\n")
        f.write(f"# driver: {DRIVER_VERSION}\n# platform: board\n")
        # How the board was actually driven. Session 2's record could not show this: the run was launched
        # with --channel exclusive and driven multiplexed, and nothing anywhere said so. The effective
        # values are read off the transport, not off the arguments, so the record reflects what happened
        # rather than what was asked for.
        f.write(f"# channel: {tp.channel}\n")
        f.write(f"# console device: {tp.serial_device or 'none (multiplexed)'}\n")
        for k, v in tp.identities().items(): f.write(f"# {k} sha256: {v}\n")
        # these are identifiers, not hashes, and are not labelled as though they were
        for k, v in notes_out.items(): f.write(f"# {k}: {v}\n")
        f.write(f"# host exit: {rc if rc is not None else 'UNCONFIRMED'}\n")
        f.write(f"# stop: {result['stopped']}\n")
        f.write(f"# remote exit confirmed: {result.get('remote exit confirmed', 'no')}\n")
        if uncertain:
            f.write("# recovery: cold platform restart required; ownership deliberately NOT released\n")
    if uncertain:
        print("UNCERTAIN: " + uncertain)
    print(f"BOARD_RUN stages={len(stages)} failed={len(bad)} "
          f"host_exit={rc if rc is not None else 'UNCONFIRMED'} ({result['stopped']})")
    return 1 if bad else 0

