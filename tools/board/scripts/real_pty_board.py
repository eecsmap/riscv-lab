#!/usr/bin/env python3
"""A fake board that is a *real* terminal: a real shell, a real controlling PTY, a real child host.

The previous fake intercepted the launch command and simulated a host, writing `exit=0` itself when it saw
a 0x03 byte. That cannot show what actually matters here, because all of it was pretend: whether the
terminal delivers SIGINT at all, whether the shell's foreground process group receives it, whether a host
that ignores it survives, and whether the wrapper lives long enough to record a status. Codex was right
that a fake writing the answer proves nothing about the question.

So this one:

  * opens a PTY and starts `/bin/sh` on the **slave side as its controlling terminal**, via setsid + TIOCSCTTY,
    so ISIG, foreground process groups and job control are the kernel's, not mine;
  * runs the transport's real commands in that shell -- including the real wrapper
    `sh -c 'echo $$ > lock/pid; exec <host> ...'; echo $? > lock/exit`;
  * uses a real child process as the host, `fake_host.py`, which can be told to ignore SIGINT.

What the tests then observe is genuine terminal behaviour. The host's stdin really is this terminal, so
bytes sent while it runs really do reach it, and the count of them is evidence rather than bookkeeping.

  real_pty_board.py <state-dir> [--host-mode normal|deaf|slow-marker]

Prints the slave device path, then serves until killed.
"""
import argparse, fcntl, os, pty, signal, struct, sys, termios, time

ap = argparse.ArgumentParser()
ap.add_argument("state")
ap.add_argument("--host-mode", default="normal", choices=("normal", "deaf", "slow-marker"))
a = ap.parse_args()
os.makedirs(a.state, exist_ok=True)

# Two PTY pairs and a relay between them -- a virtual serial cable with a named end at each side.
#
# A single pair will not do: the shell sits on the slave, so anything that opens that same slave by name
# is on the *shell's* side of the line, not the other end of it. A real serial link has two separate ends,
# and the transport must open one of them the way it opens /dev/ttyUSB1. So:
#
#     shell  <->  shell_slave | shell_master  <-relay->  ext_master | ext_slave  <->  transport
#
shell_master, slave = pty.openpty()
ext_master, ext_slave = pty.openpty()
slave_name = os.ttyname(ext_slave)          # the end the transport opens
master = shell_master

pid = os.fork()
if pid == 0:
    # child: become a session leader, take the slave as the controlling terminal, and exec a real shell
    # Restore the default disposition for the terminal signals before becoming the shell.
    #
    # A shell starting a background job sets SIGINT and SIGQUIT to SIG_IGN in the child, and that
    # disposition survives fork and exec -- Python only installs its own handler when the inherited one is
    # not SIG_IGN. The integration harness launches this fixture with `&`, so the ignore propagated relay ->
    # interactive shell -> wrapper -> host, and the host ignored every interrupt. Measured: SigIgn ...006
    # (bits for SIGINT and SIGQUIT) at all four boundaries in the background case, ...000 in the
    # foreground one. That is a property of how the *fixture* was started, not of the code under test, and
    # this is the boundary to correct it at: a real board's login shell is not somebody's background job.
    signal.signal(signal.SIGINT, signal.SIG_DFL)
    signal.signal(signal.SIGQUIT, signal.SIG_DFL)
    os.setsid()
    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
    os.dup2(slave, 0); os.dup2(slave, 1); os.dup2(slave, 2)
    if slave > 2: os.close(slave)
    os.close(master)
    env = dict(os.environ)
    env["PS1"] = "~ # "
    env["TEACHING_FAKE_STATE"] = a.state
    env["TEACHING_FAKE_HOST_MODE"] = a.host_mode
    env["PATH"] = os.path.dirname(os.path.abspath(__file__)) + ":" + env.get("PATH", "")
    os.execve("/bin/sh", ["/bin/sh", "-i"], env)
    os._exit(127)

os.close(slave)
# ISIG stays ON for the shell's terminal: the whole point is that the kernel really delivers SIGINT to the
# foreground process group when 0x03 arrives.
attrs = termios.tcgetattr(shell_master)
attrs[3] |= termios.ISIG
attrs[3] &= ~termios.ECHO
termios.tcsetattr(shell_master, termios.TCSANOW, attrs)
# The transport's end is a wire: raw, no echo, no signal interpretation of its own.
ext = termios.tcgetattr(ext_slave)
ext[0] = 0; ext[1] = 0
ext[3] &= ~(termios.ECHO | termios.ICANON | termios.ISIG)
termios.tcsetattr(ext_slave, termios.TCSANOW, ext)

print(slave_name, flush=True)
open(os.path.join(a.state, "shell-pid"), "w").write(str(pid))

# The parent does nothing but keep the master open so the PTY survives between connections. Each transport
# invocation opens the slave by name, which is exactly how the serial device is used.
import select
try:
    while True:
        r, _, _ = select.select([shell_master, ext_master], [], [], 0.5)
        for fd_in, fd_out in ((shell_master, ext_master), (ext_master, shell_master)):
            if fd_in in r:
                try: data = os.read(fd_in, 65536)
                except OSError: data = b""
                if data:
                    try: os.write(fd_out, data)
                    except OSError: pass
        if os.waitpid(pid, os.WNOHANG)[0] == pid:
            break
except KeyboardInterrupt:
    pass
finally:
    try: os.kill(pid, signal.SIGKILL)
    except OSError: pass
