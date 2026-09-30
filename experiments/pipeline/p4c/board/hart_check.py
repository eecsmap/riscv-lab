#!/usr/bin/env python3
"""PIPE-P4c: the board-visible sign that BOTH harts ran the xv6 kernel in one board run. xv6's main.c: hart 0 prints
"xv6 kernel is booting" and initialises; every other hart prints "hart N starting" ITSELF (after hart 0 set started)
and then enters the scheduler. The single-hart images print no "hart 1 starting" (their consoles are the negative
test). Board runs have no per-hart retirement counters (those exist only in the simulator), so this is the evidence
the console can give; the per-hart gates of the install session (dual01..07) are the rest.
  hart_check.py <console.txt>        exit 0 iff exactly one "hart 1 starting" follows the boot line and no other hart id"""
import sys, re
t = open(sys.argv[1], errors="replace").read().replace("\r", "")
boot = t.find("xv6 kernel is booting"); starts = re.findall(r"^hart (\d+) starting$", t, re.M)
if boot < 0: print("HART_CHECK FAIL no 'xv6 kernel is booting' line"); sys.exit(1)
if starts != ["1"]: print(f"HART_CHECK FAIL 'hart N starting' lines: {starts} (want exactly ['1'])"); sys.exit(1)
if t.find("hart 1 starting") < boot: print("HART_CHECK FAIL 'hart 1 starting' precedes the boot line"); sys.exit(1)
print("HART_CHECK PASS hart 1 started the kernel (console: 'hart 1 starting' after 'xv6 kernel is booting')")
