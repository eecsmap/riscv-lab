#!/usr/bin/env python3
"""PIPE-P3b: the core clock measured against the PS's clock. Reads <dir>/freq_spin_{short,long}.<i>.out: T0/T1 from
/proc/uptime on the ARM (10 ms resolution, PS timekeeping, independent of the PL clock) around one fesvr run, and the
program's own report of the cycles it spun and the CLINT mtime delta.
  f_i = (cycles_long_i - cycles_short_i) / (dt_long_i - dt_short_i)      (the fixed load/reset overhead cancels)
Prints each pair, the median and range, the resolution bound (2 x 10 ms per pair over ~20 s), and the mtime ratio
cycles / mtime_delta (must be 100 on this SoC). Exit 1 if a file is missing or a value is unreadable.
PIPE-P4c (two-hart freq_spin_dual.S): also exit 1 unless every run reports hart1_id=1 (hart 1 came up and parked)
and every cycles/mtime ratio is within 1 % of 100."""
import sys, os, re, statistics
d = sys.argv[1]; rows = []; ok = True
def rd(v, i):
    t = open(os.path.join(d, f"{v}.{i}.out"), errors="replace").read().replace("\r", "")
    t0 = float(re.findall(r"^T0=([\d.]+)$", t, re.M)[-1]); t1 = float(re.findall(r"^T1=([\d.]+)$", t, re.M)[-1])
    m = re.search(r"FREQ-SPIN cycles=0x([0-9a-f]+) mtime_delta=0x([0-9a-f]+) hart1_id=0x([0-9a-f]+)", t)
    if int(m.group(3), 16) != 1: raise ValueError(f"{v}.{i}: hart1_id={int(m.group(3), 16):#x}, not 1")
    c, mt = int(m.group(1), 16), int(m.group(2), 16)
    if not (mt > 0 and abs(c / mt - 100) <= 1): raise ValueError(f"{v}.{i}: cycles/mtime = {c}/{mt}, not 100 +- 1 %")
    return t1 - t0, c, mt
i = 1
while os.path.exists(os.path.join(d, f"freq_spin_short.{i}.out")):
    try:
        ds, cs, ms = rd("freq_spin_short", i); dl, cl, ml = rd("freq_spin_long", i)
    except Exception as e:
        print(f"FAIL pair {i}: {e}"); ok = False; i += 1; continue
    f = (cl - cs) / (dl - ds); err = 0.02 / (dl - ds)
    rows.append(f)
    print(f"pair {i}: short {ds:.2f} s / {cs} cycles (mtime {ms}, ratio {cs/ms:.3f}); long {dl:.2f} s / {cl} cycles (mtime {ml}, ratio {cl/ml:.3f}); f = {f/1e6:.4f} MHz (+-{err*100:.2f} % from the 10 ms resolution)")
    i += 1
if not rows: print("FAIL no pairs"); sys.exit(1)
print(f"FREQ core clock vs the PS clock: median {statistics.median(rows)/1e6:.4f} MHz, range {min(rows)/1e6:.4f}-{max(rows)/1e6:.4f} MHz over {len(rows)} pairs")
sys.exit(0 if ok else 1)
