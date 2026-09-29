#!/usr/bin/env python3
"""PIPE-P2a uncached-fetch judge: reads a run-nc.sh output directory.
  ncjudge.py <run-nc out dir>        exit 0 = PASS
fix  (every one of the 12 profiles): exit 0 (the program's own mcause/mepc/mtval checks), no core assertion, no
     payload error, every device read a 2-byte parcel, 0 footprint violations, and the device read sequence EQUAL to
     the one derived by hand from nc_prog.S below (offsets relative to 0x4000_0000)
wide (PIPE_FAULT 20, the old whole-word read): caught -- footprint violations in every profile"""
import sys, re, os
EXPECTED = [0x000, 0x002, 0x004, 0x006, 0x008,       # dev0: c, c, 32-bit at +4 (both parcels), c.jr at +8
            0x046, 0x048, 0x04a,                     # dev1: 32-bit at +6 across the word (carry), c.jr
            0x082, 0x084, 0x086, 0x088,              # dev2: 32-bit at +2, c at +6, c.jr at +8
            0x0c0, 0x0c8, 0x0ca, 0x0d0,              # dev3: c.j (+2..+7 never), beq at +8 (+12..+15 never), c.jr
            0x100,                                   # dev4: first parcel answered with error
            0x140, 0x142,                            # dev5: second parcel (inside the word) answered with error
            0x186, 0x188]                            # dev6: second parcel (next word) answered with error
PROFILES = [(rd, rs) for rd in range(3) for rs in range(1, 5)]
out = sys.argv[1]; bad = []
print(f"== uncached instruction-access footprint bench: {out}")
for name in ("fix", "wide"):
    caught = 0
    for rd, rs in PROFILES:
        f = os.path.join(out, name, f"rd{rd}-rs{rs}.log")
        if not os.path.exists(f): bad.append(f"{name}: missing {f}"); continue
        t = open(f, errors="replace").read()
        m = re.search(r"^NC END pf=\d+ rd=\d+ rs=\d+ code=(\d+) cycles=\d+ device_reads=(\d+) non_parcel_reads=(\d+) footprint_violations=(\d+) payload_errors=(\d+)$", t, re.M)
        if not m: bad.append(f"{name} rd{rd}-rs{rs}: no NC END line"); continue
        code, nreads, wide, viol, perr = map(int, m.groups())
        asserts = len(re.findall(r"^PIPE ASSERT", t, re.M))
        seq = [int(a, 16) - 0x40000000 for a in re.findall(r"^NC READ cyc=\d+ addr=([0-9a-f]{8}) ", t, re.M)]
        if name == "fix":
            why = []
            if code != 0: why.append(f"exit {code}")
            if asserts: why.append(f"{asserts} core assertions")
            if perr: why.append(f"{perr} payload errors")
            if wide: why.append(f"{wide} reads wider than a parcel")
            if viol: why.append(f"{viol} footprint violations")
            if seq != EXPECTED: why.append(f"read sequence {[hex(x) for x in seq]} differs from the expected")
            if why: bad.append(f"fix rd{rd}-rs{rs}: " + "; ".join(why))
        elif viol > 0: caught += 1
    if name == "fix": print(f"  fix: {len(PROFILES)} profiles; the expected {len(EXPECTED)} parcel reads in order, 0 violations: {'PASS' if not [b for b in bad if b.startswith('fix')] else 'FAIL'}")
    else:
        print(f"  wide (PIPE_FAULT 20): footprint violations in {caught} of {len(PROFILES)} profiles: {'CAUGHT' if caught == len(PROFILES) else 'NOT CAUGHT'}")
        if caught != len(PROFILES): bad.append(f"wide: caught in only {caught} of {len(PROFILES)} profiles")
for b in bad: print("  FAIL " + b)
print(f"NC_JUDGE {'PASS' if not bad else 'FAIL'}")
sys.exit(1 if bad else 0)
