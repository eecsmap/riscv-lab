#!/usr/bin/env python3
"""PIPE-P2b: the pipeline's xv6 runs next to the multicycle reference on the same kernel and disk.
  xv6compare.py <label>=<run dir> ...        prints one row per run; exit 1 if a run lacks its PASS or its numbers
Per run: the inputs (cmd.txt: simulator, kernel and disk hashes), the judges (check.txt / perf-check.txt must end in
PASS), the host's totals (HARTS retired0 / traps0, HARTS_USER user0, CYCLES total), and for perf-short the fixed-work
regions (RESULT PERF-COMPUTE / PERF-ARRAY dmtime in mtime units = 100 cycles)."""
import sys, re, os
bad = []; rows = []
for arg in sys.argv[1:]:
    label, d = arg.split("=", 1)
    def rd(p):
        try: return open(os.path.join(d, p), errors="replace").read()
        except OSError: bad.append(f"{label}: missing {p}"); return ""
    cmd, con = rd("cmd.txt"), rd("run/console.txt")
    sim = re.search(r"^sim=\S+ \(([0-9a-f]{16})\)", cmd, re.M); ker = re.search(r"^kernel=\S+ \(([0-9a-f]{16})", cmd, re.M)
    dsk = re.search(r"^disk=\S+ \(([0-9a-f]{16})", cmd, re.M); wl = re.search(r"^workload=(\S+)", cmd, re.M)
    judges = ["check.txt"] + (["perf-check.txt"] if wl and wl.group(1) == "perf-short" else [])
    verdicts = []
    for j in judges:
        t = rd(j).strip().splitlines()
        v = t[-1] if t else ""
        verdicts.append(v.split()[0] if v else "none")
        if not v.startswith("PASS"): bad.append(f"{label}: {j} does not end in PASS: {v[:120]}")
    h = re.search(r"HARTS n=(\d+) retired0=(\d+) traps0=(\d+)", con); u = re.search(r"HARTS_USER user0=(\d+) range0=(\d+)", con)
    c = re.search(r"CYCLES total=(\d+)", con)
    if not (h and u and c): bad.append(f"{label}: host totals missing"); continue
    ret, cyc = int(h.group(2)), int(c.group(1))
    perf = dict(re.findall(r"RESULT PERF-(\w+) size=\d+ dmtime=(\d+)", rd("perf-check.txt"))) if "perf-check.txt" in judges else {}
    rows.append((label, wl.group(1) if wl else "?", sim.group(1) if sim else "?", ker.group(1) if ker else "?", dsk.group(1) if dsk else "?",
                 "/".join(verdicts), h.group(1), ret, int(h.group(3)), int(u.group(1)), cyc, cyc / ret, perf))
print("| run | workload | sim | kernel | disk | judges | harts | retired | traps | user commits | cycles | cycles/retired | fixed-work dmtime (mtime units) |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for r in rows:
    pf = ", ".join(f"{k.lower()} {int(v):,}" for k, v in sorted(r[12].items())) or "-"
    print(f"| {r[0]} | {r[1]} | {r[2]} | {r[3]} | {r[4]} | {r[5]} | {r[6]} | {r[7]:,} | {r[8]:,} | {r[9]:,} | {r[10]:,} | {r[11]:.2f} | {pf} |")
for b in bad: print("  FAIL  " + b)
print(f"XV6_COMPARE {'PASS' if not bad else 'FAIL'}")
sys.exit(1 if bad else 0)
