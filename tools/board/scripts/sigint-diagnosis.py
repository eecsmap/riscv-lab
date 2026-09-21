#!/usr/bin/env python3
"""A controlled comparison of the two fake-board launch ancestries, for the normal-case stop timeout.

The report before this inferred, from the absence of the trap's exit file, that SIGINT was never delivered
-- and then attributed the difference to `board_run`. Neither step was justified: a missing exit file is
equally consistent with the signal arriving and being ignored, and the direct and harness cases were not
controlled, because they started the fake board differently.

So this starts the *same* fixture two ways and measures, rather than infers:

    foreground  -- subprocess.Popen, as the direct tests did
    background  -- `sh -c '... &'`, as the integration harness does

and for each records, at every process boundary that could swallow an interrupt:

  * SigIgn / SigCgt / SigBlk for the relay, the interactive shell, the wrapper and the host
  * session id and foreground process group of the terminal
  * the terminal's ISIG flag and VINTR character
  * whether the interrupt byte actually crossed the relay
  * what followed: host exit, trap fired, marker emitted

  sigint-diagnosis.py <fresh outdir>
"""
import argparse, fcntl, os, signal, struct, subprocess, sys, termios, time

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("outdir")
a = ap.parse_args()
if os.path.exists(a.outdir): sys.exit(f"REFUSE: {a.outdir} exists")
os.makedirs(a.outdir)

SIGINT_BIT = 1 << (signal.SIGINT - 1)      # /proc masks are 1-based by signal number


def sigstate(pid):
    """SigIgn/SigCgt/SigBlk for a pid, and whether SIGINT is ignored."""
    out = {}
    try:
        for ln in open(f"/proc/{pid}/status"):
            k, _, v = ln.partition(":")
            if k in ("Name", "State", "SigIgn", "SigCgt", "SigBlk"):
                out[k] = v.strip()
    except OSError as e:
        return {"error": str(e)}
    try:
        out["SIGINT ignored"] = bool(int(out.get("SigIgn", "0"), 16) & SIGINT_BIT)
        out["SIGINT caught"] = bool(int(out.get("SigCgt", "0"), 16) & SIGINT_BIT)
    except ValueError:
        pass
    return out


def descendants(pid, depth=0, acc=None):
    acc = acc if acc is not None else []
    if depth > 6: return acc
    try:
        kids = open(f"/proc/{pid}/task/{pid}/children").read().split()
    except OSError:
        return acc
    for k in kids:
        acc.append((depth, int(k)))
        descendants(int(k), depth + 1, acc)
    return acc


def termios_state(dev):
    try:
        fd = os.open(dev, os.O_RDWR | os.O_NOCTTY)
    except OSError as e:
        return {"error": str(e)}
    try:
        at = termios.tcgetattr(fd)
        return {"ISIG": bool(at[3] & termios.ISIG),
                "VINTR": hex(at[6][termios.VINTR][0] if isinstance(at[6][termios.VINTR], bytes)
                             else at[6][termios.VINTR]),
                "foreground pgid": os.tcgetpgrp(fd)}
    except Exception as e:
        return {"error": str(e)}
    finally:
        os.close(fd)


def one_case(name, background):
    """Start the fixture, run a host, interrupt it, and record everything."""
    st = os.path.join(a.outdir, name)
    os.makedirs(st, exist_ok=True)
    rep = []
    def say(s):
        rep.append(s); print(f"  {s}", flush=True)

    devfile = os.path.join(st, "dev")
    if background:
        # exactly how the harness does it: a background job of a non-interactive shell
        board = subprocess.Popen(["sh", "-c",
                                  f"python3 {HERE}/real_pty_board.py {st} > {devfile} 2>{st}/board.log &"
                                  f" echo $! > {st}/boardpid; wait"],
                                 stdout=subprocess.DEVNULL)
        for _ in range(60):
            if os.path.exists(devfile) and open(devfile).read().strip(): break
            time.sleep(0.2)
        dev = open(devfile).read().strip()
        relay_pid = int(open(os.path.join(st, "boardpid")).read().strip())
    else:
        board = subprocess.Popen([sys.executable, f"{HERE}/real_pty_board.py", st],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        dev = board.stdout.readline().decode().strip()
        relay_pid = board.pid

    say(f"relay pid {relay_pid}, device {dev}")
    say(f"relay      {sigstate(relay_pid)}")
    spf = os.path.join(st, "shell-pid")
    for _ in range(60):
        if os.path.exists(spf) and open(spf).read().strip(): break
        time.sleep(0.2)
    shell_pid = int(open(spf).read().strip())
    say(f"shell      {sigstate(shell_pid)}")

    # deploy a real host and launch it exactly as the transport does
    os.makedirs(os.path.join(st, "root"), exist_ok=True)
    import shutil
    hostp = os.path.join(st, "root", "fesvr-teaching-static")
    shutil.copy(os.path.join(HERE, "fake_host.py"), hostp); os.chmod(hostp, 0o755)
    for n in ("kernel-128mib", "fs-run.img"):
        open(os.path.join(st, "root", n), "w").write(n + "\n")
    open(os.path.join(st, "boot_id"), "wb").write(b"9e62de9e-f7f1-4cf4-93f0-060bff64ae3b\x00")

    sys.path.insert(0, HERE)
    from transport import BoardTransport, UncertainState
    shim = os.path.abspath(os.path.join(HERE, "..", "..", "xv6-board-run", "scripts", "serial-transport.py"))
    tp = BoardTransport(f"{sys.executable} {shim} --device {dev}",
                        hostp, os.path.join(st, "root", "fs-run.img"),
                        os.path.join(st, "root", "kernel-128mib"),
                        remote_lock=os.path.join(st, "b.lock"), allow_test_lock=True,
                        remote_boot_id=os.path.join(st, "boot_id"),
                        channel="exclusive", serial_device=dev)
    tp.remote_boot_id(); tp.claim(); tp.start()
    time.sleep(2.0)

    say(f"terminal   {termios_state(dev)}")
    kids = descendants(shell_pid)
    say(f"shell descendants: {kids}")
    for depth, pid in kids:
        say(f"  {'  '*depth}pid {pid}  {sigstate(pid)}")
    hostpid = None
    try:
        hostpid = int(open(os.path.join(st, "b.lock", "pid")).read().strip())
        say(f"host (from lock/pid) {hostpid}  {sigstate(hostpid)}")
    except (OSError, ValueError) as e:
        say(f"host pid unavailable: {e}")

    # the interrupt, and whether the byte crossed
    before = os.path.getsize(os.path.join(st, "host-stdin.txt")) if os.path.exists(
        os.path.join(st, "host-stdin.txt")) else 0
    t0 = time.monotonic()
    verdict = ""
    try:
        rc = tp.stop(timeout=12)
        verdict = f"stop() -> {rc} after {time.monotonic()-t0:.1f}s"
    except UncertainState:
        verdict = f"stop() -> UNCERTAIN after {time.monotonic()-t0:.1f}s"
    say(verdict)
    say(f"host still alive: {hostpid is not None and os.path.exists(f'/proc/{hostpid}')}")
    exitf = os.path.join(st, "b.lock", "exit")
    say(f"trap/exit file: {open(exitf).read().strip() if os.path.exists(exitf) else '(absent)'}")
    say(f"framing file: {bool(tp._status_file) and os.path.exists(tp._status_file)}")
    after = os.path.getsize(os.path.join(st, "host-stdin.txt")) if os.path.exists(
        os.path.join(st, "host-stdin.txt")) else 0
    say(f"bytes into host stdin: before={before} after={after} (the 0x03 is NOT stdin data if ISIG is on)")

    try: board.kill()
    except Exception: pass
    for _, pid in kids:
        try: os.kill(pid, signal.SIGKILL)
        except OSError: pass
    open(os.path.join(a.outdir, f"{name}.txt"), "w").write("\n".join(rep) + "\n")
    return verdict


print("== A. foreground: the fixture started by Popen, as the direct tests did")
va = one_case("foreground", background=False)
print("== B. background: the fixture started by a shell with &, as the harness does")
vb = one_case("background", background=True)
print()
print(f"foreground: {va}")
print(f"background: {vb}")
print("SIGINT_DIAGNOSIS done")
