#!/usr/bin/env python3
"""A real child process standing in for fesvr-teaching: reads stdin, speaks an xv6-like console.

Real process, real signal disposition. In `deaf` mode it installs a SIGINT handler that ignores the
signal, which is how "the host ignored the interrupt" is tested against the kernel rather than against a
flag in a fake.
"""
import os, signal, sys, time

mode = os.environ.get("TEACHING_FAKE_HOST_MODE", "normal")
# Both dispositions are set EXPLICITLY. Relying on "normal means whatever we inherited" is what let an
# inherited SIG_IGN turn the normal host into a silently deaf one, making the two cases indistinguishable.
if mode == "deaf":
    signal.signal(signal.SIGINT, signal.SIG_IGN)     # the negative case, genuinely deaf
else:
    signal.signal(signal.SIGINT, signal.SIG_DFL)     # the normal case, genuinely interruptible

OUT = {
    "echo teaching-xv6-hello": "teaching-xv6-hello\n",
    "ls": (".              1 1 1024\n..             1 1 1024\nREADME         2 2 2441\n"
           "cat            2 3 36824\nls             2 10 38960\nwc             2 17 37816\n"),
    "cat README": "xv6 is a re-implementation of Dennis Ritchie's and Ken Thompson's Unix\n",
    "echo abc | wc": "      1       1       4\n",
}

sys.stdout.write("teaching: ready after 50 ms; status=0x00000011 boot_ready=1\n")
sys.stdout.write("\nxv6 kernel is booting\n\nblkdev: 4000 sectors (1 MB), max request 16 sectors\n"
                 "init: starting sh\n$ ")
sys.stdout.flush()

# Record everything that reaches this host's stdin. The legitimate traffic is the driver's four commands;
# anything shaped like a shell command means a control byte was delivered to the host instead of to a
# shell, which is the failure this whole exclusive-channel design exists to prevent.
STATE = os.environ.get("TEACHING_FAKE_STATE", ".")
rec = open(os.path.join(STATE, "host-stdin.txt"), "a", buffering=1)

for line in sys.stdin:
    rec.write(line)
    cmd = line.strip()
    sys.stdout.write(cmd + "\n")
    sys.stdout.write(OUT.get(cmd, "sh: command not found\n"))
    sys.stdout.write("$ ")
    sys.stdout.flush()
sys.stdout.write("SIMTAIL done\n"); sys.stdout.flush()
