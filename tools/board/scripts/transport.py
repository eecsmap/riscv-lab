#!/usr/bin/env python3
"""How the driver reaches the thing it is driving, and who owns it while it does.

The simulation driver spawns a local process. The board host runs on the ARM, behind a session, and the
distance between those two facts is where the dangerous mistakes live. Four of them were found in review
and are answered here rather than documented around:

  * **a local exit is not a remote exit.** Signalling an `ssh` client kills the client. The process on the
    other end can outlive it, keep its `/dev/mem` mapping of the adapter, and still own the restart
    handshake. So the remote side is launched through a wrapper that records its pid and its exit status in
    a remote lock directory, termination is a remote `kill`, and the run is only over when that recorded
    exit status has been read back.
  * **a lock under the output directory is not a lock on the board.** Two runs with different output roots
    got different locks and could launch two hosts on one board. Ownership is claimed *on the board*, in a
    fixed remote directory, and the local claim is keyed by board identity rather than by where the logs
    happen to go.
  * **stopping a host does not assert reset.** It never did. If the transport is lost, or the remote exit
    cannot be confirmed, the target and host state are **unknown**: ownership is not released, the run is
    not labelled a deliberate stop, and the only recovery is a cold platform restart performed by a person.
  * **`NOT-LOCAL` is not an identity.** What matters is the hash of the file the remote side will actually
    open, read on the remote side, not a local file with the same name.

Nothing here releases the restart request or reconfigures the PL. There is no such method.
"""
import hashlib, os, re, shlex, stat, subprocess, sys, time

#: a boot id is a UUID; validating the shape stops a truncated read being compared as an id
SESSION_RE = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
                        r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
#: an ownership token: <pid>-<unix time>-<8 hex>. Extracted from a console stream, like everything else.
OWNER_TOKEN = re.compile(r"\b\d+-\d+-[0-9a-f]{8}\b")
#: the same shape, found anywhere in a console stream rather than anchored
SESSION_TOKEN = re.compile(r"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
                           r"[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b")


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(65536), b""):
            h.update(b)
    return h.hexdigest()


class _Required:
    """Sentinel for an argument that has no default, only an explicit answer."""
    def __repr__(self): return "<required>"


_REQUIRED = _Required()


class TransportError(Exception):
    pass


class UncertainState(TransportError):
    """Raised when the remote state cannot be established. Never caught to 'recover'."""


class _Base:
    platform = None

    def __init__(self):
        self.proc = None
        self._ident = {}

    @property
    def stdout(self): return self.proc.stdout

    @property
    def stdin(self): return self.proc.stdin

    def poll(self): return self.proc.poll() if self.proc else None

    def identities(self): return dict(self._ident)


class LocalTransport(_Base):
    """The simulator, exactly as before. Behaviour is unchanged byte for byte."""
    platform = "simulator"

    def __init__(self, sim, elf, disk, max_cycles, progress):
        super().__init__()
        self.argv = [sim, f"+max-cycles={max_cycles}", f"+blkdev={disk}",
                     f"+rd2_progress={progress}", elf]
        self._ident = {"simulator": sha(sim), "kernel": sha(elf), "disk at start": sha(disk)}

    def start(self, extra_ident=None):
        if extra_ident: self._ident.update(extra_ident)
        self.proc = subprocess.Popen(self.argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, bufsize=0)

    def signal(self, sig):
        if self.proc and self.proc.poll() is None: self.proc.send_signal(sig)

    def wait(self, timeout=None): return self.proc.wait(timeout=timeout)


#: A path that can be embedded in a remote shell command without ambiguity. Rather than trying to quote
#: everything a shell might do, unsupported paths are refused early and loudly.
SAFE_PATH = re.compile(r"^[A-Za-z0-9_@%+=:,./-]+$")


def remote_quote(path):
    """Quote a path for a remote shell, refusing what cannot be carried safely."""
    if not path:
        raise TransportError("an empty remote path")
    if not SAFE_PATH.match(path):
        raise TransportError(
            f"the remote path {path!r} contains characters this transport will not attempt to carry "
            f"through a remote shell (whitespace, quotes or shell metacharacters). Refusing early rather "
            f"than quoting and hoping: deploy to a path made of [A-Za-z0-9_@%+=:,./-].")
    return shlex.quote(path)


class BoardTransport(_Base):
    """The ARM host, owned on the board rather than through a local pipe.

    **The transport contract**, stated because getting it wrong is invisible until it is on hardware:

        the prefix is invoked with exactly ONE further argument, which is a complete shell command, and is
        expected to execute it with a shell on the board.

    `ssh host` satisfies this: ssh joins its command arguments with spaces and hands the result to the
    remote login shell, so passing a single pre-quoted string is the only construction that survives.
    The earlier code passed `prefix + ["sh", "-c", script]`, which works with a fake that preserves argv
    and **breaks under real ssh**, because ssh joins the three words and the remote shell re-parses them --
    the `sh -c` grouping is gone and the script's first word becomes the command. That defect was invisible
    to the old tests for exactly this reason, so the tests now include a shell-joining fake.

    The prefix itself is parsed with shlex, so `--transport-cmd 'ssh -p 2222 pynq'` means what it looks
    like.
    """
    platform = "board"

    #: The one lock that means "this board's adapter is taken". A test may point elsewhere, but only at a
    #: path that is obviously not the production one, so a test override can never silently become a way
    #: past the real lock.
    PRODUCTION_LOCK = "/var/lock/teaching-fesvr.lock"

    def __init__(self, transport_cmd, remote_host_binary, remote_disk, remote_kernel,
                 remote_lock=None, remote_boot_id="/proc/sys/kernel/random/boot_id",
                 expect=None, allow_test_lock=False, channel=_REQUIRED, serial_device=None):
        super().__init__()
        # There is no default, and the reason is on the record. `board-runner.py` parsed --channel, marked
        # it required, documented it -- and never passed it. The constructor's default quietly supplied
        # "multiplexed", so a serial console was driven as though a second session were available: the
        # device was never locked, the pid poll opened a second shim on the live console, and its commands
        # were typed into xv6. A default is what made that omission survivable long enough to reach the
        # board.
        if channel is _REQUIRED:
            raise TransportError(
                "channel was not given, and there is no default. 'exclusive' for a serial console, where "
                "the host owns the line once it starts; 'multiplexed' for ssh, where a second session is "
                "always available. Constructing a transport without answering this is how a console came "
                "to be driven as if it were ssh.")
        if channel not in ("multiplexed", "exclusive"):
            raise TransportError(f"channel must be 'multiplexed' or 'exclusive', not {channel!r}")
        remote_lock = remote_lock or self.PRODUCTION_LOCK
        if remote_lock != self.PRODUCTION_LOCK:
            if not allow_test_lock:
                raise TransportError(
                    f"the device lock is {remote_lock!r}, not the production lock "
                    f"{self.PRODUCTION_LOCK!r}. A run that locks somewhere else is not excluding anything "
                    f"on the real board. Pass allow_test_lock=True only from a test.")
            if not remote_lock.endswith(".lock") or remote_lock.count("/") < 2 or remote_lock in ("/", "/tmp"):
                raise TransportError(f"refusing {remote_lock!r} as a lock path: too broad or unexpected")
        if not transport_cmd:
            raise TransportError("a board run needs an explicit --transport-cmd; there is no default")
        self.prefix = transport_cmd if isinstance(transport_cmd, list) else shlex.split(transport_cmd)
        if not self.prefix:
            raise TransportError("--transport-cmd parsed to nothing")
        self.host_binary = remote_host_binary
        self.disk = remote_disk
        self.kernel = remote_kernel
        self.lock = remote_lock
        self.boot_id_path = remote_boot_id
        self.expect = dict(expect or {})     # path -> sha256 the reviewer approved
        self.boot_id = None
        self.owned = False
        self.remote_pid = None
        self.state = "not-started"
        # How many things can talk to the board at once.
        #   multiplexed -- ssh: another session is always available, so control commands can run while the
        #                  host streams. Everything below has always assumed this.
        #   exclusive   -- a serial console: once the host is launched it owns the tty and there is no
        #                  second channel at all. The first hardware session failed exactly here, because
        #                  start() read the remote pid back with a second command.
        self.channel = channel
        #: resolved and cross-checked here, in the constructor, so an exclusive run without a usable device
        #: cannot reach the point of sending anything anywhere.
        self.serial_device = self._resolve_device(channel, serial_device)
        self._status_file = None
        self._host_owns_channel = False
        self._local_lock_fd = None

    def _resolve_device(self, channel, serial_device):
        """The console device, resolved to a real path and cross-checked, before anything is sent.

        Two independent places name this device: `--serial-device`, which is what gets `flock`ed, and the
        `--device` argument inside `--transport-cmd`, which is what the shim actually opens. Nothing
        compared them, so they were free to name different lines -- and then the lock guards one console
        while the shim writes into another. They must be the same line, and "the same" means after
        symlink resolution, because `/dev/serial/by-id/...` and `/dev/ttyUSB1` are the same port under two
        names.
        """
        if channel != "exclusive":
            if serial_device:
                raise TransportError(
                    f"a console device ({serial_device!r}) was given for a {channel!r} channel. A device "
                    f"is only meaningful when the host owns the line; on a multiplexed channel it would "
                    f"lock something this transport never opens.")
            return None
        if not serial_device:
            raise TransportError(
                "an exclusive channel needs the console device. It is what gets locked against a second "
                "opener, and without it the lock protects nothing: a second process can open the same tty "
                "and write into the host's stdin.")
        dev = os.path.realpath(serial_device)
        if not os.path.exists(dev):
            raise TransportError(f"the console device {serial_device!r} does not exist")
        if not stat.S_ISCHR(os.stat(dev).st_mode):
            raise TransportError(f"{serial_device!r} is not a character device, so it is not a console")
        named = [self.prefix[i + 1] for i, t in enumerate(self.prefix[:-1]) if t == "--device"]
        named += [t.split("=", 1)[1] for t in self.prefix if t.startswith("--device=")]
        if not named:
            raise TransportError(
                f"the transport command {' '.join(self.prefix)!r} does not name a --device, so there is "
                f"nothing to check the locked device against. An exclusive run must point the shim at the "
                f"same line it locks.")
        for n in named:
            if os.path.realpath(n) != dev:
                raise TransportError(
                    f"the locked device is {serial_device!r} ({dev}) but the transport command opens "
                    f"{n!r} ({os.path.realpath(n)}). The lock and the shim must be the same line.")
        return dev

    # -- talking to the board ---------------------------------------------------------------------------
    def _argv(self, script):
        """The prefix plus ONE argument: the complete remote shell command. See the contract above."""
        return self.prefix + [script]

    def _run(self, script, timeout=30):
        """Run a shell fragment on the board and collect it. Not for the host itself.

        On an exclusive channel this refuses outright while the host is running. That is not caution: the
        host owns the tty, so the bytes of this command would be delivered to **its stdin**, and for this
        host that means straight into TSI. That happened during the first hardware session while I was
        diagnosing, and it is why the target's state had to be declared unknown. A refusal here makes that
        impossible rather than unlikely.
        """
        if self.channel == "exclusive" and self._host_owns_channel:
            raise TransportError(
                "refusing an out-of-band command: the host owns this exclusive channel, so these bytes "
                "would be delivered to its stdin (and therefore into TSI). Stop the host first.")
        try:
            p = subprocess.run(self._argv(script), stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired:
            raise TransportError(
                f"a control command did not return within {timeout}s, so the channel has not come back. "
                f"Nothing it might have said can be trusted and nothing further is sent.")
        return p.returncode, p.stdout.decode("utf-8", "replace")

    def remote_boot_id(self):
        rc, outp = self._run(f"cat {remote_quote(self.boot_id_path)}")
        if rc != 0:
            raise TransportError(f"cannot read the board's boot id ({self.boot_id_path}): {outp.strip()!r}")
        # A console carries furniture -- prompts, echoed text, carriage returns -- so the identifier is
        # *extracted* rather than assumed to be the whole stream. Exactly one distinct candidate must
        # appear: none means the read failed, several means something else is talking on this channel.
        #
        # One trailing NUL is a terminator (see mem-preflight.py for where this board's comes from). A NUL
        # anywhere else is corruption on the channel and is refused rather than scrubbed away.
        t = outp.replace("\r", " ")
        if "\x00" in t.strip().rstrip("\x00"):
            raise TransportError(f"the boot id read back contains an embedded NUL: {outp.strip()!r}")
        t = t.replace("\x00", " ")
        found = sorted(set(SESSION_TOKEN.findall(t)))
        if not found:
            raise TransportError(f"no boot-id UUID in what the board sent back: {outp.strip()[:120]!r}")
        if len(found) > 1:
            raise TransportError(f"several different boot ids came back ({found}): another writer is on "
                                 f"this channel, so none of them can be trusted")
        self.boot_id = found[0]
        return self.boot_id

    def remote_hashes(self, paths):
        """sha256 of files **on the board**. A local file of the same name proves nothing about what the
        session will actually open."""
        rc, outp = self._run("sha256sum " + " ".join(remote_quote(p) for p in paths))
        got = {}
        for ln in outp.splitlines():
            parts = ln.split()
            if len(parts) == 2 and len(parts[0]) == 64:
                got[parts[1]] = parts[0]
        missing = [p for p in paths if p not in got]
        if missing:
            raise TransportError(f"these files are not present on the board: {missing} ({outp.strip()!r})")
        return got

    def existing_owners(self):
        """Any process already holding the adapter. Both the teaching host and the stock fesvr-zynq count:
        the stock one pulses SYSTEM_RESET in its constructor.

        Matching must be on the **program being run** -- the first token of the command line -- and not on
        the command line anywhere. A grep for the name matches this runner's own arguments (which of course
        name the host binary) and every process would look like an owner. That is the same self-match that
        once made a `pkill` here kill its own shell.
        """
        rc, outp = self._run(
            "ps -eo pid,args 2>/dev/null | awk 'NR>1 {prog=$2; "
            "  n=split(prog, parts, \"/\"); base=parts[n]; "
            "  if (base ~ /^fesvr-(teaching|zynq)/) print}' || true")
        # A console stream carries prompts and echoed text. An owner line is `<pid> <path...>`; anything
        # else is furniture. Without this a bare prompt counts as an owner and blocks every run -- and the
        # failure would look like "the board is busy", which is exactly the wrong thing to believe.
        owners = []
        for ln in outp.splitlines():
            t = ln.strip()
            parts = t.split()
            if len(parts) >= 2 and parts[0].isdigit() and "fesvr-" in t:
                owners.append(t)
        return owners

    def _claim_local_device(self):
        """Exclusive local ownership of the serial device, in addition to the coord lease.

        The coord lease is a convention between agents; this is an actual kernel-enforced exclusion, so a
        second local process cannot open the same port behind our back."""
        if self.channel != "exclusive" or not self.serial_device:
            return
        import fcntl
        try:
            fd = os.open(self.serial_device, os.O_RDWR)
        except OSError as e:
            raise TransportError(f"cannot open {self.serial_device}: {e}")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            raise TransportError(
                f"{self.serial_device} is already held by another process. On an exclusive channel a "
                f"second opener is a second writer into the same console.")
        self._local_lock_fd = fd

    def _release_local_device(self):
        if self._local_lock_fd is not None:
            os.close(self._local_lock_fd)
            self._local_lock_fd = None

    # -- ownership, claimed on the board ----------------------------------------------------------------
    def claim(self):
        owners = self.existing_owners()
        if owners:
            raise TransportError("a host is already running on this board:\n  " + "\n  ".join(owners) +
                                 "\nTwo hosts would be two owners of the restart handshake and two readers "
                                 "of the same TSI FIFOs.")
        # The local device is claimed FIRST. It used to be claimed last, after the board's lock directory
        # had already been created -- so when the device turned out to be held, the claim raised with the
        # board's lock left behind and `owned` still False. `release()` only ever runs for a claim that
        # succeeded, so nothing could ever clean that up: the next run would find the board "held", and
        # with no manual clearing allowed the only way out was a cold restart. Ordering closes the window
        # instead of adding a cleanup path for it.
        self._claim_local_device()
        rc, outp = self._run(f"mkdir {remote_quote(self.lock)} 2>&1 && echo CLAIMED")
        if "CLAIMED" not in outp:
            self._release_local_device()
            raise TransportError(f"the board's host lock {self.lock} is held: {outp.strip()!r}")
        self.token = f"{os.getpid()}-{int(time.time())}-{os.urandom(4).hex()}"
        rc, outp = self._run(f"printf %s {shlex.quote(self.token)} > "
                             f"{remote_quote(self.lock + '/owner')} && echo OWNED")
        if "OWNED" not in outp:
            # The one case cleanup is permitted in, and nothing wider. The mkdir above succeeded, which
            # proves the directory did not exist and is therefore this call's; start() has not been
            # called, so no host exists under it. This is NOT authority to clear session 2's lock, or any
            # lock whose provenance is unknown, or any lock with contents.
            why = outp.strip()
            removed, detail = self._rmdir_own_empty_lock()
            self._release_local_device()
            if not removed:
                # Reporting this as cleaned up would be a lie, and the previous version told it: it ran
                # `rmdir ... || true` and then said "was removed" unconditionally. The lock is still
                # there; that is the fact, it is not retried, and it is not softened.
                self.state = "uncertain"
                raise UncertainState(
                    f"the board's host lock {self.lock} was created, its owner token could not be written "
                    f"({why!r}), and the directory could NOT be removed either ({detail!r}). It is left "
                    f"exactly as it is: nothing is retried and nothing further is attempted. No host was "
                    f"launched. The lock's disposition must be resolved by a cold platform restart.")
            raise TransportError(
                f"the board's host lock {self.lock} was created but its owner token could not be written "
                f"({why!r}). A lock with no owner cannot be proved ours later, so the empty directory this "
                f"call had just created was removed ({detail!r}) and no host was launched.")
        self.owned = True

    def _rmdir_own_empty_lock(self):
        """Nonrecursive `rmdir` of the empty lock directory this claim has just created.

        Returns `(removed, detail)` and **reports what actually happened**. There is no `|| true` here:
        whether the removal succeeded is the entire point of the call, and swallowing its status is how
        the earlier version came to announce a removal that had not happened.

        `rmdir` is what enforces "the exact empty directory this claim created": it refuses a directory
        with anything in it, so a lock that has acquired contents -- which would mean it is not what this
        call made -- cannot be removed by this path at all. There is no recursive delete anywhere near it.
        """
        try:
            rc, outp = self._run(f"rmdir {remote_quote(self.lock)} && echo RMDIR_OK")
        except TransportError as e:
            return False, f"the cleanup command itself did not return: {e}"
        if "RMDIR_OK" in outp:
            return True, "rmdir reported success"
        return False, outp.strip() or f"rmdir exited {rc} and said nothing"

    def release(self):
        """Give up ownership. Only ever after the remote host's exit status has been read back.

        This used to be `rm -rf $lock`, with $lock coming from a command-line option -- an unrestricted
        recursive delete on the board, aimed by an argument. It now removes the three files it created, by
        name, and then rmdirs the (now empty) directory, so a wrong or over-broad path cannot become a
        recursive delete of something else. The ownership token is checked first: releasing a lock this
        process did not take would be releasing someone else's board.

        Fail closed: if the token does not match, or the cleanup does not complete, ownership is NOT
        dropped and the state stays uncertain.
        """
        if not (self.owned and self.state == "remote-exit-confirmed"):
            return False
        rc, outp = self._run(f"cat {remote_quote(self.lock + '/owner')} 2>/dev/null || true")
        # Extracted, not stripped: a console puts a prompt in front of the value. Comparing the whole
        # stream to the token says "not ours" about a lock that is ours, and then refuses to release it.
        found = sorted(set(OWNER_TOKEN.findall(outp)))
        if found != [self.token]:
            self.state = "uncertain"
            raise UncertainState(
                f"the board's host lock carries {found or outp.strip()!r}, not this run's "
                f"{self.token!r}: it is not ours to release. Ownership is left alone.")
        names = " ".join(remote_quote(self.lock + "/" + n) for n in ("owner", "pid", "exit"))
        rc, outp = self._run(f"rm -f {names} && rmdir {remote_quote(self.lock)} && echo RELEASED")
        if "RELEASED" not in outp:
            self.state = "uncertain"
            raise UncertainState(
                f"the board's host lock {self.lock} could not be cleaned up ({outp.strip()!r}). Ownership "
                f"is NOT dropped: another run must not be allowed to start against a board whose state "
                f"here is unknown. Recovery is a cold platform restart and a manual check of the lock.")
        self.owned = False
        self._release_local_device()
        return True

    # -- lifecycle --------------------------------------------------------------------------------------
    def start(self, extra_ident=None):
        if not self.owned:
            raise TransportError("start() before claim(): ownership is claimed on the board first")
        # The wrapper is the point: it records the remote pid and, when the host finally exits, its real
        # status -- on the board, where it stays true whatever happens to the local session.
        # Record the HOST's pid, not the wrapper shell's. Killing the shell would stop it before it could
        # write the exit status, and the run would look unconfirmed when it had in fact ended cleanly --
        # which is the wrong error to make in the safe direction as well as the unsafe one.
        # Nothing is backgrounded. A background command in a non-interactive shell gets /dev/null for
        # stdin whatever you do to it, so the host would never receive a typed character. Instead an inner
        # shell records its own pid and `exec`s the host, which means the recorded pid IS the host's -- so
        # a later `kill` reaches the host and not a wrapper -- and the outer shell waits for it in the
        # foreground and records the real exit status on the board.
        inner = (f"echo $$ > {remote_quote(self.lock + '/pid')}; "
                 f"exec {remote_quote(self.host_binary)} "
                 f"+blkdev={remote_quote(self.disk)} {remote_quote(self.kernel)}")
        # The trap is not decoration, and a real terminal is what showed why. On SIGINT the shell abandons
        # the whole command list, so with the obvious shape --
        #     sh -c '<wrapper>'; echo $? > exit
        # -- neither the exit file nor the transport's end marker is ever written when the run is stopped
        # the intended way. The framing check would then call every correct stop "uncertain", which is the
        # safe direction but useless. Running it in a subshell with an INT trap makes the status survive:
        # the trap records 130 (128 + SIGINT) and the marker is still emitted afterwards. Verified on a
        # real controlling PTY, both shapes, in exclusive-integration-selftest.sh.
        exitf = remote_quote(self.lock + "/exit")
        body = f"trap 'echo 130 > {exitf}' INT; sh -c {shlex.quote(inner)}; echo $? > {exitf}"
        cmd = f"( {body} )"
        argv = self._argv(cmd)
        if self.channel == "exclusive":
            # Ask the shim to record whether it actually saw the end marker. Its own exit code cannot say
            # this: a crashed shim and a command that returned 1 look identical from here.
            import tempfile
            self._status_file = os.path.join(tempfile.mkdtemp(prefix="teaching-run-"), "framed")
            argv = self.prefix + ["--status-file", self._status_file, cmd]
        self.proc = subprocess.Popen(argv, stdin=subprocess.PIPE,
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, bufsize=0)
        self.state = "running"
        if self.channel == "exclusive":
            # No out-of-band read here. The host now owns the channel, and asking it anything would put
            # the question into its stdin. The wrapper has already written the pid to the lock before
            # exec'ing, so it is there to be read once the channel is free again.
            self._host_owns_channel = True
        else:
            for _ in range(100):
                got = self._control_int("the remote pid", self.lock + "/pid", 1, 2 ** 22)
                if got is not None:
                    self.remote_pid = got; break
                time.sleep(0.1)
        if extra_ident: self._ident.update(extra_ident)

    def _control_read(self, remote_path, timeout=30):
        """One value the board recorded, delivered inside markers this side generated.

        The previous version took *the last integer anywhere in the stream*. On hardware that read the
        `595` out of

            File ".../serial/serialposix.py", line 595, in read

        -- a pyserial traceback produced by our own crashed shim -- and reported it as the board's
        confirmed exit status. A console carries prompts, echoes, and, when something goes wrong, whole
        tracebacks; "the last number in it" is not a protocol.

        So the value is delimited by a per-read nonce. The marker is assembled **on the board** out of two
        halves, because a console echoes the command it was given: if the complete marker appeared in the
        command text, the echo alone would produce a second, bogus reply. Split, the echo contains the
        halves and never the join.

        Returns the raw text between the markers -- empty when the board has not written the record yet.
        Anything ambiguous is an error, never a value.
        """
        n = os.urandom(8).hex()
        head, tail = "CT", "L" + n
        marker = head + tail
        q = remote_quote(remote_path)
        script = (f"__a={head}; __b={tail}; "
                  f"printf '%s%s[' \"$__a\" \"$__b\"; "
                  f"cat {q} 2>/dev/null; "
                  f"printf ']%s%s\\n' \"$__a\" \"$__b\"")
        rc, outp = self._run(script, timeout=timeout)
        if rc != 0:
            raise TransportError(
                f"the control read of {remote_path} failed on the board (rc={rc}): {outp.strip()[:200]!r}. "
                f"A failed control command is not an answer.")
        found = re.findall(re.escape(marker) + r"\[(.*?)\]" + re.escape(marker), outp, re.S)
        if not found:
            raise TransportError(
                f"the board sent back no framed reply for {remote_path}. What came back was "
                f"{outp.strip()[:200]!r}. Without the framing there is no way to tell a value from console "
                f"furniture, so nothing is taken from it.")
        if len(found) > 1:
            raise TransportError(
                f"several framed replies came back for {remote_path} ({found[:3]!r}): something else is "
                f"writing on this channel, so none of them can be trusted.")
        return found[0]

    def _control_int(self, what, remote_path, lo, hi, timeout=30):
        """A control reply that must be a bare integer in a stated range, or nothing at all.

        `None` means the board has not written the record yet -- the one legitimate absence. Every other
        shape is an error: a traceback, a partial write, a number outside the range a pid or a shell
        status can take.
        """
        raw = self._control_read(remote_path, timeout=timeout)
        txt = raw.strip()
        if txt == "":
            return None
        if not re.fullmatch(r"-?\d+", txt):
            raise TransportError(
                f"{what} came back as {txt[:200]!r}, which is not a bare integer. The board writes this "
                f"record with a single `echo`; anything else in it means the record is not what was "
                f"written, and no number is taken out of it.")
        v = int(txt)
        if not (lo <= v <= hi):
            raise TransportError(
                f"{what} came back as {v}, outside the {lo}..{hi} a valid value can take. The record is "
                f"not trusted.")
        return v

    def remote_exit(self):
        """The exit status the wrapper recorded ON THE BOARD, or None if it has not recorded one yet.

        A shell status is 0..255 -- `echo $?` cannot produce anything else, and neither can the INT trap's
        130. A value outside that is not a status and is refused rather than returned.
        """
        return self._control_int("the recorded remote exit status", self.lock + "/exit", 0, 255)

    def _stop_exclusive(self, timeout):
        """Stop the host over the one channel there is, then prove it stopped.

        The interrupt is a *mechanism*, not evidence. Ctrl-C asks the foreground process group to stop; it
        does not establish that the host died, that the wrapper survived to record a status, or that the
        shell came back. The only thing taken as proof is the exit status the wrapper wrote **on the
        board**, read after the channel is free. If that is not there, the state is uncertain and stays
        uncertain.
        """
        if self.proc is None:
            raise TransportError("stop() before start()")
        # 1. in-band interrupt, down the same stream the host reads
        try:
            self.proc.stdin.write(b"\x03")
            self.proc.stdin.flush()
        except (BrokenPipeError, OSError):
            pass                       # the session may already be gone; the check below decides
        # 2. wait for the local session to end. This is NOT the remote exit -- it only frees the channel.
        deadline = time.time() + timeout
        while self.proc.poll() is None and time.time() < deadline:
            time.sleep(0.2)
        if self.proc.poll() is None:
            self.state = "uncertain"
            self._capture_stall("local-session-did-not-end")
            raise UncertainState(
                f"the local session did not end within {timeout}s after an interrupt, so the channel is "
                f"still held and the host cannot be asked anything. The target's state is unknown; "
                f"ownership is NOT released and nothing is reset. Recovery is a cold platform restart.")

        # 3. THE CHANNEL IS ONLY FREE IF THE SHIM SAW THE END MARKER.
        #
        # A local process ending does not mean the remote command finished. A crashed or disconnected shim
        # ends too, while the host on the other side carries on owning the terminal -- and the next command
        # sent "to the shell" would be delivered to that host's stdin. That is precisely how diagnostic
        # bytes reached the target in the first hardware session. So the marker, written by the shim only
        # when it framed the wrapper's completion, is the gate. Without it: no commands, at all.
        framed = None
        if self._status_file and os.path.exists(self._status_file):
            txt = open(self._status_file).read().strip()
            if txt.startswith("MARKER="):
                framed = txt.split("=", 1)[1]
        if framed is None:
            self.state = "uncertain"
            raise UncertainState(
                "the local session ended without framing the command's completion, so there is no evidence "
                "that the shell came back. The host may still own the terminal, and sending anything now "
                "would put it into the host's stdin. No diagnostics are sent, ownership is NOT released "
                "and nothing is reset. Recovery is a cold platform restart.")
        self._host_owns_channel = False
        try:
            self.remote_pid = None
            self.remote_pid = self._control_int("the remote pid", self.lock + "/pid", 1, 2 ** 22)
            ev = self.remote_exit()
        except TransportError as e:
            self.state = "uncertain"
            raise UncertainState(
                f"the channel came back but the board could not be asked for the recorded exit ({e}). "
                f"The host may still hold its mapping of the adapter. Ownership is NOT released.")
        if ev is None:
            self.state = "uncertain"
            raise UncertainState(
                "the local session ended and the channel is free, but the wrapper recorded no exit status "
                "on the board. An interrupt is not proof of termination: without that marker the host may "
                "still be running, so the target's state is unknown. Ownership is NOT released and "
                "nothing is reset. Recovery is a cold platform restart.")
        self.state = "remote-exit-confirmed"
        return ev

    def _capture_stall(self, why):
        """Record, bounded, what the local side looks like when a teardown stalls.

        A stalled teardown that only says "timed out" cannot be diagnosed later. This writes the shim's
        pid, liveness, wait channel and kernel stack where available -- enough to say whether it is blocked
        writing, blocked reading, or gone -- next to the run's own logs. It touches nothing remote: on an
        exclusive channel there is by definition nothing safe to ask.
        """
        try:
            import glob
            out = [f"stall: {why}", f"time: {time.strftime('%FT%T')}"]
            p = self.proc
            out.append(f"shim pid: {p.pid if p else None}  poll: {p.poll() if p else None}")
            if p and p.poll() is None:
                for f in ("wchan", "stat", "status"):
                    try:
                        t = open(f"/proc/{p.pid}/{f}").read()
                        if f == "status":
                            t = "\n".join(l for l in t.splitlines()
                                           if l.split(":")[0] in ("State", "SigBlk", "SigIgn", "SigCgt"))
                        out.append(f"--- /proc/{p.pid}/{f}\n{t.strip()[:400]}")
                    except OSError as e:
                        out.append(f"--- /proc/{p.pid}/{f}: {e}")
                try:
                    out.append("--- /proc/%d/stack\n%s" % (p.pid, open(f"/proc/{p.pid}/stack").read()[:400]))
                except OSError:
                    out.append("--- stack: not readable (needs privilege); wchan above is the substitute")
                # what the shim's children are, if any
                for d in glob.glob(f"/proc/{p.pid}/task/*/children"):
                    try: out.append(f"--- children: {open(d).read().strip()}")
                    except OSError: pass
            out.append(f"status file: {self._status_file} exists={bool(self._status_file) and os.path.exists(self._status_file)}")
            dest = os.environ.get("TEACHING_STALL_LOG")
            text = "\n".join(out) + "\n"
            if dest:
                with open(dest, "a") as f: f.write(text + "\n")
            sys.stderr.write(text)
        except Exception as e:                       # diagnostics must never mask the failure
            sys.stderr.write(f"(stall capture failed: {e})\n")

    def stop(self, timeout=60):
        """Ask the remote host to stop, and confirm on the board that it did.

        Stopping a host does NOT assert reset and this method does not pretend otherwise. If the remote
        exit cannot be confirmed, the state is recorded as uncertain, ownership is NOT released, and the
        caller must treat the target as needing a cold platform restart.
        """
        if self.channel == "exclusive":
            return self._stop_exclusive(timeout)
        if self.remote_pid:
            self._run(f"kill -TERM {int(self.remote_pid)} 2>/dev/null || true")
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                ev = self.remote_exit()
            except TransportError as e:
                self.state = "uncertain"
                raise UncertainState(
                    f"the board could not be asked for the recorded exit status ({e}). A control command "
                    f"that failed is not a confirmation: the host may still be running and may still own "
                    f"its /dev/mem mapping of the adapter. Ownership is NOT released and nothing is reset. "
                    f"Recovery is a cold platform restart.")
            if ev is not None:
                self.state = "remote-exit-confirmed"
                return ev
            time.sleep(0.2)
        self.state = "uncertain"
        raise UncertainState(
            f"the remote host's exit was not confirmed within {timeout}s. Its /dev/mem mapping of the "
            f"adapter may still be live and it may still own the restart handshake. Ownership is NOT "
            f"released and the restart request is NOT touched: stopping a host never asserted reset. "
            f"Recovery is a cold platform restart.")

    def local_session_ended(self):
        return self.proc is not None and self.proc.poll() is not None
