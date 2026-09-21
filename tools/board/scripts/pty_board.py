#!/usr/bin/env python3
"""A fake board on a PTY: one channel, one command at a time, and it says no to a second.

Every offline test before this used an ssh-like fake that could always run another command, so the
assumption underneath `BoardTransport` -- that a control command can run while the host streams -- was
never tested. On the real board that assumption is false, and the first hardware session died on it.

This fake is the missing shape. It owns a pseudo-terminal, runs one command at a time, and while a "host"
is running it is **the host that owns the channel**: any further command sent down the line is delivered
to the host's stdin, exactly as a real console does, and is counted. A test can therefore assert that zero
diagnostic bytes reached the host.

Modes for the fake host, chosen by the command the transport sends:
  * normal   -- speaks an xv6-like console and exits on interrupt, recording its status
  * deaf     -- ignores the interrupt entirely; the session never ends on its own
  * nomarker -- exits on interrupt but the wrapper never records an exit status

  pty_board.py <state-dir> [--host-mode normal|deaf|nomarker]

It prints the slave device path on stdout and then serves until killed.
"""
import argparse, os, pty, re, select, signal, subprocess, sys, termios, time

ap = argparse.ArgumentParser()
ap.add_argument("state")
ap.add_argument("--host-mode", default="normal", choices=("normal", "deaf", "nomarker"))
a = ap.parse_args()
os.makedirs(a.state, exist_ok=True)

XV6 = ("\nxv6 kernel is booting\n\nblkdev: 4000 sectors (1 MB), max request 16 sectors\ninit: starting sh\n$ ")
OUTPUT = {
    "echo teaching-xv6-hello": "teaching-xv6-hello\n",
    "ls": ("."+" "*14+"1 1 1024\n.."+" "*13+"1 1 1024\nREADME"+" "*9+"2 2 2441\n"
           "cat"+" "*12+"2 3 36824\nls"+" "*13+"2 10 38960\nwc"+" "*13+"2 17 37816\n"),
    "cat README": "xv6 is a re-implementation of Dennis Ritchie's and Ken Thompson's Unix\n",
    "echo abc | wc": "      1       1       4\n",
}

master, slave = pty.openpty()
print(os.ttyname(slave), flush=True)
# raw-ish: no echo, so the fake behaves like a console with `stty -echo`
attrs = termios.tcgetattr(slave)
attrs[3] &= ~termios.ECHO
termios.tcsetattr(slave, termios.TCSANOW, attrs)

state = {"host": False, "injected": b"", "openers": 0}
def record():
    open(os.path.join(a.state, "injected-bytes"), "wb").write(state["injected"])
    open(os.path.join(a.state, "injected-count"), "w").write(str(len(state["injected"])))
record()

buf = b""
line = b""
def w(s):
    os.write(master, s.encode() if isinstance(s, str) else s)

w("~ # ")
host_lines = 0
while True:
    r, _, _ = select.select([master], [], [], 0.2)
    if not r:
        continue
    try:
        data = os.read(master, 4096)
    except OSError:
        break
    if not data:
        break

    if state["host"]:
        # THE HOST OWNS THE CHANNEL. Everything arriving is the host's stdin -- which is precisely what
        # made the real target's state unknown. Interrupts are the one exception.
        for byte in data:
            b = bytes([byte])
            if b == b"\x03":
                if a.host_mode == "deaf":
                    continue                      # ignores the interrupt; the session never ends
                state["host"] = False
                if a.host_mode != "nomarker":
                    # the wrapper records the status where the transport will look for it: in the lock
                    lk = state.get("lock") or a.state
                    os.makedirs(lk, exist_ok=True)
                    open(os.path.join(lk, "exit"), "w").write("0")
                w(f"\n{state['tag']}=0\r\n~ # ")
                break
            state["injected"] += b
            record()
            # a real shell would echo the target's own output back; emulate the xv6 shell
            s = state.setdefault("hostline", b"")
            if b == b"\n":
                cmd = s.decode("utf-8", "replace").strip()
                state["hostline"] = b""
                w(cmd + "\n")
                w(OUTPUT.get(cmd, "sh: command not found\n"))
                w("$ ")
            else:
                state["hostline"] = s + b
        continue

    line += data
    while b"\n" in line:
        one, line = line.split(b"\n", 1)
        cmd = one.decode("utf-8", "replace").strip()
        if not cmd:
            w("~ # "); continue
        m = re.search(r"(__X\d+__)=\$\?", cmd)
        tag = m.group(1) if m else None
        state["tag"] = tag
        # strip the transport's own end-marker; the rest is a real shell command
        body = re.sub(r";\s*echo __X\d+__=\$\?\s*$", "", cmd)

        if "exec " in body and "fesvr" in body:
            # The host takes the channel. The wrapper writes the pid before exec'ing, exactly as the real
            # one does, so it is there to be read once the channel is free again.
            lk = state.get("lock") or a.state
            os.makedirs(lk, exist_ok=True)
            open(os.path.join(lk, "pid"), "w").write("4321")
            state["host"] = True
            w(XV6)
            break

        if body.strip().startswith("cat ") and "boot_id" in body:
            # this board's /proc file: 36 characters and a NUL, no newline
            w("9e62de9e-f7f1-4cf4-93f0-060bff64ae3b\x00")
            rc = 0
        elif body.strip().startswith("ps "):
            rc = 0                       # no other host is running on this fake board
        elif body.strip().startswith("sha256sum"):
            for path in body.split()[1:]:
                w(f"{'a'*64}  {path}\n")
            rc = 0
        else:
            # Everything else runs in a real shell. The fake is a fake *channel*, not a fake filesystem:
            # emulating mkdir/cat/rm by hand is where the previous version kept going wrong.
            r2 = subprocess.run(body, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            w(r2.stdout.decode("utf-8", "replace"))
            rc = r2.returncode
            mk = re.match(r"\s*mkdir\s+(\S+)", body)
            if mk and rc == 0:
                state["lock"] = mk.group(1)
        if tag:
            w(f"{tag}={rc}\r\n~ # ")
