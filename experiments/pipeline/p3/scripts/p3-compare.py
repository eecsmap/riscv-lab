#!/usr/bin/env python3
"""PIPE-P3a: full-system and per-hart resources and routed timing of several builds, read from their Vivado reports.
  p3-compare.py <label>=<reports dir> ...
Per build: the routed timing summary (WNS/TNS/WHS/THS, endpoints), post_route_utilization.rpt totals, and from
post_route_utilization_hier.rpt every TeachingCpuV2 instance (a hart) with its sub-blocks down to three levels, plus
the rest of the design (full minus harts). Hierarchical numbers are attribution after optimisation across boundaries,
not isolated feature costs."""
import re, sys, os
def timing(d):
    t = open(os.path.join(d, "post_route_timing_summary.rpt"), errors="replace").read()
    if "Design Timing Summary" not in t: return None
    for l in t.split("Design Timing Summary", 1)[1].splitlines():
        p = l.split()
        if len(p) >= 8 and re.match(r"^-?\d+\.\d+$", p[0]): return p[:8]
    return None
def util(d):
    t = open(os.path.join(d, "post_route_utilization.rpt"), errors="replace").read()
    g = lambda lab: (re.search(rf"^\|\s*{lab}\s*\|\s*(\d+)", t, re.M) or [None, "?"])[1]
    return {"LUT": g("Slice LUTs"), "LUTRAM": g("LUT as Memory"), "FF": g("Slice Registers"), "BRAM": g("Block RAM Tile"), "DSP": g("DSPs")}
def hier(d):
    rows = []
    for l in open(os.path.join(d, "post_route_utilization_hier.rpt"), errors="replace"):
        if not l.startswith("|") or "Instance" in l: continue
        c = l.split("|")
        if len(c) < 11: continue
        inst = c[1]; depth = (len(inst) - len(inst.lstrip(" "))) // 2
        try: nums = [int(x) for x in c[3:11]]
        except ValueError: continue
        rows.append((depth, inst.strip(), c[2].strip(), nums))
    return rows
out = []; builds = []
for a in sys.argv[1:]:
    lab, d = a.split("=", 1); builds.append(lab)
    tm = timing(d); u = util(d); h = hier(d)
    out.append(f"## {lab}: {d}")
    out.append(f"   routed timing: WNS {tm[0]} ns, TNS {tm[1]}, failing setup endpoints {tm[2]} of {tm[3]}; WHS {tm[4]} ns, THS {tm[5]}, failing hold endpoints {tm[6]} of {tm[7]}" if tm else "   routed timing: NOT FOUND")
    out.append(f"   full system: {u['LUT']} LUT ({u['LUTRAM']} LUTRAM), {u['FF']} FF, {u['BRAM']} BRAM tiles, {u['DSP']} DSP")
    harts = [i for i, r in enumerate(h) if r[2].startswith("TeachingCpuV2")]
    hl = hf = 0
    for i in harts:
        dep = h[i][0]; out.append(f"   hart {h[i][1]} ({h[i][2]}): {h[i][3][0]} LUT ({h[i][3][2]} LUTRAM), {h[i][3][4]} FF, DSP {h[i][3][7]}")
        hl += h[i][3][0]; hf += h[i][3][4]
        for r in h[i + 1:]:
            if r[0] <= dep: break
            if r[0] <= dep + 3: out.append(f"   {'  ' * (r[0] - dep)}{r[1]:28s} {r[2][:24]:24s} {r[3][0]:6d} LUT {r[3][2]:5d} LUTRAM {r[3][4]:6d} FF {r[3][7]:3d} DSP")
    tot = h[0][3] if h else None
    if tot: out.append(f"   everything outside the hart(s): {tot[0] - hl} LUT, {tot[4] - hf} FF")
print("\n".join(out))
