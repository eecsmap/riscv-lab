#!/usr/bin/env python3
"""PIPE-P4a: does each hart's identity match its binding? From a traced run's events.txt (EV ... COMMIT hart=<port>).
The boot ROM reads mhartid at 0x10004 and branches at 0x10008: to 0x10010 when it reads 0 (the hart that wakes the
others), to 0x1000c otherwise. The hart on port / CLINT slot 0 must take 0x10010 and the hart on slot 1 0x1000c, the
first time each runs the ROM. A swapped HART_ID fails exactly this, whatever happens afterwards.
  identity_check.py <run dir>        exit 0 = both harts took the path of their own index"""
import sys, re
ev = open(sys.argv[1] + "/events.txt", errors="replace").read().splitlines()
seq = {0: [], 1: []}
for l in ev:
    m = re.match(r"^EV +\d+ +COMMIT hart=(\d) pc=0x([0-9a-f]+)", l)
    if m and int(m.group(1)) in seq: seq[int(m.group(1))].append(int(m.group(2), 16))
bad = []
for h, want, what in ((0, 0x10010, "mhartid 0"), (1, 0x1000c, "mhartid != 0")):
    s = seq[h]
    i = next((k for k in range(len(s) - 1) if s[k] == 0x10008), None)
    if i is None: bad.append(f"hart {h}: never reached the ROM's mhartid branch at 0x10008"); continue
    got = s[i + 1]
    ok = got == want
    print(f"hart {h} (port/CLINT slot {h}): after the mhartid branch it went to 0x{got:x}, {'the path for ' + what if ok else 'NOT the path for ' + what}")
    if not ok: bad.append(f"hart {h} took the ROM path for {'mhartid != 0' if got == 0x1000c else 'mhartid 0'}: its HART_ID does not match its port/CLINT slot {h}")
for b in bad: print("  FAIL: " + b)
print("IDENTITY " + ("PASS" if not bad else "FAIL")); sys.exit(1 if bad else 0)
