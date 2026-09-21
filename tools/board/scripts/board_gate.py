#!/usr/bin/env python3
"""The gate a board run must pass before a host is launched.

The previous version took a `--memory-evidence` string and checked it was not empty, so any text at all
satisfied a gate that was supposed to be mandatory. This does the four things that string was standing in
for, and a failure at any of them means **no host is launched at all**:

  1. the evidence bundle exists and the memory preflight is **re-run here**, now -- a claimed result from
     somewhere else is not evidence;
  2. the bundle's contents are hashed, so evidence swapped after the preflight ran is detected;
  3. the board's **live** boot id is read through the transport and must equal the bundle's session -- a
     bundle captured before the last power cycle describes a machine that no longer exists;
  4. every deployment file is hashed **on the board** against the approved list, because a local file of
     the same name says nothing about what the session will open.

Order matters and is enforced by construction: the gate runs before `start()`, and `start()` refuses
without a claim.
"""
import hashlib, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))


class GateError(Exception):
    pass


def bundle_digest(path):
    """One hash over the whole evidence bundle, so a file swapped after the preflight ran is visible."""
    h = hashlib.sha256()
    for root, dirs, files in os.walk(path):
        dirs.sort()
        for name in sorted(files):
            p = os.path.join(root, name)
            h.update(os.path.relpath(p, path).encode())
            h.update(open(p, "rb").read())
    return h.hexdigest()


def read_session(path):
    p = os.path.join(path, "session-id")
    if not os.path.isfile(p):
        raise GateError(f"the evidence bundle {path} has no session-id: it cannot be bound to a boot")
    return normalise_id(open(p, "rb").read(), f"the bundle's session-id")


def run_preflight(bundle, expect_session):
    """Re-run the preflight rather than believing a recorded verdict."""
    pre = os.path.join(HERE, "mem-preflight.py")
    p = subprocess.run([sys.executable, pre, bundle, "--expect-session", expect_session],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    out = p.stdout.decode("utf-8", "replace")
    if p.returncode != 0:
        raise GateError(f"the memory preflight refuses this evidence:\n" +
                        "\n".join("    " + l for l in out.splitlines() if "REFUSE" in l))
    return out


import re as _re
SHA256 = _re.compile(r"^[0-9a-f]{64}$")
SESSION_RE = _re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")


def normalise_id(raw, what):
    """One trailing NUL is a terminator; anything else NUL-ish is corruption. See mem-preflight.py for
    where the terminator on this board comes from."""
    if isinstance(raw, str): raw = raw.encode()
    if raw.endswith(b"\x00"): raw = raw[:-1]
    t = raw.decode("utf-8", "replace").strip()
    if "\x00" in t:
        raise GateError(f"{what} contains an embedded NUL byte: corrupt, not merely terminated")
    if not SESSION_RE.match(t):
        raise GateError(f"{what} is {t!r}, which is not a boot-id UUID")
    return t


def check_roles(roles, deploy_expect):
    """Every role must have an approved hash for its EXACT path.

    The previous version required only that the expectation map was non-empty and then matched by
    basename, so a run could start with a MISSING identity, or a same-named file from another directory
    could stand in for the approved one. Roles are bound to full paths here, and the hashes are checked for
    syntax so a typo cannot pass as an approval.
    """
    missing = [f"{role} ({path})" for role, path in roles.items() if path not in deploy_expect]
    if missing:
        raise GateError("no approved hash was supplied for the exact path of: " + ", ".join(missing) +
                        ".\nA role whose file is unverified cannot be part of a transcript anyone can "
                        "believe. --expect takes the full path, not a name.")
    for path, h in deploy_expect.items():
        if not SHA256.match(h or ""):
            raise GateError(f"--expect for {path} is {h!r}, which is not a sha256")
    # the same path approved twice with different hashes is a contradiction, not a preference
    seen = {}
    for path, h in deploy_expect.items():
        key = os.path.realpath(path) if os.path.isabs(path) else path
        if key in seen and seen[key] != h:
            raise GateError(f"{path} is given two different approved hashes: {seen[key]} and {h}")
        seen[key] = h
    # two roles pointing at one file is almost certainly a mistake in the launch command
    bypath = {}
    for role, path in roles.items():
        bypath.setdefault(path, []).append(role)
    dup = {p: r for p, r in bypath.items() if len(r) > 1}
    if dup:
        raise GateError(f"these roles point at the same path: {dup}")


def gate(transport, bundle, deploy_expect, roles=None, log=print):
    """Everything that must be true before a host may be launched. Raises GateError otherwise.

    `deploy_expect` maps a path **on the board** to the sha256 the reviewer approved.
    Returns a dict recorded into the run's identity.
    """
    if not os.path.isdir(bundle):
        raise GateError(f"--evidence-dir {bundle!r} is not a directory. A board run needs a captured "
                        f"evidence bundle, not a string.")

    session = read_session(bundle)
    digest = bundle_digest(bundle)
    log(f"  evidence bundle {bundle}: session {session}, digest {digest[:16]}")

    # 1 + 2: the preflight is re-run here, over these exact bytes
    run_preflight(bundle, session)
    log("  memory preflight: re-run now, accepted")
    if bundle_digest(bundle) != digest:
        raise GateError("the evidence bundle changed while it was being checked")

    # 3: bind to the board that is running *now*
    live = transport.remote_boot_id()
    log(f"  board's live boot id: {live}")
    if live != session:
        raise GateError(
            f"the evidence was captured during boot {session} but the board is running boot {live}. "
            f"It has been power-cycled or rebooted since, so the memory check describes a machine that is "
            f"no longer there. Capture again and re-run the preflight.")

    # 4: the files the session will actually open
    if not deploy_expect:
        raise GateError("no deployment hashes were supplied; a run whose files are unverified is not one "
                        "whose transcript can be believed")
    if roles:
        check_roles(roles, deploy_expect)
        log(f"  roles bound to exact paths: " + ", ".join(f"{r}={p}" for r, p in sorted(roles.items())))
    got = transport.remote_hashes(sorted(deploy_expect))
    wrong = {p: (deploy_expect[p], got[p]) for p in deploy_expect if got[p] != deploy_expect[p]}
    if wrong:
        lines = [f"    {p}\n      approved {w}\n      on board {g}" for p, (w, g) in wrong.items()]
        raise GateError("these deployment files on the board are not the approved ones:\n" + "\n".join(lines))
    log(f"  {len(got)} deployment files hashed on the board, all as approved")

    # keyed by full path, so the caller binds a role to the file it actually named
    return {"memory evidence session": session, "memory evidence digest": digest,
            "board boot id": live, **{f"remote path {p}": h for p, h in got.items()}}
