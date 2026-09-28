#!/usr/bin/env python3
"""MC-M1 T1.8: the four microbenchmarks' ROI cycles, BEFORE against AFTER, on the same RTL.

Uses the campaign's own extractor (tools/gen_stage_metrics.py: cycles from the probe's counter reads,
retirement checked against the workload descriptor) on a combined run directory, then prints every ROI
with its delta. A non-zero delta is not a failure; it is a fact for REPORT.md, and it must be explained
there. A zero delta everywhere is NOT accepted as the functional regression -- that is what the probe
verdicts and the trace comparison are for.

  roi-compare.py <before-probes-dir> <after-probes-dir> <fresh combined-dir>
"""
import json, os, subprocess, sys

R = "/home/engineer/fpga"
TOOL = f"{R}/worktrees/mc-single-wrapper/experiments/IPS-campaign/tools/gen_stage_metrics.py"

def main():
    b, a, comb = sys.argv[1:4]
    runs = os.path.join(comb, "runs")
    os.makedirs(runs, exist_ok=False)
    for d in (b, a):
        for r in sorted(os.listdir(os.path.join(d, "runs"))):
            os.symlink(os.path.join(d, "runs", r), os.path.join(runs, r))
    out = os.path.join(comb, "metrics.json")
    subprocess.run([sys.executable, TOOL, comb, "--stage", "mc-m1", "--out", out], check=False,
                   stdout=open(os.path.join(comb, "gen_stage_metrics.txt"), "w"), stderr=subprocess.STDOUT)
    m = json.load(open(out))
    rows = m["rows"] if isinstance(m, dict) and "rows" in m else m
    refused = m.get("refused", []) if isinstance(m, dict) else []
    by = {}
    for r in rows:
        by.setdefault((r["workload"], r["roi"]), {})[r["core"]] = r
    print(f"{'workload':12s} {'roi':14s} {'before':>12s} {'after':>12s} {'delta':>8s}  {'cpi b->a'}")
    nd = 0; n = 0
    for (w, roi), cores in sorted(by.items()):
        rb, ra = cores.get("before"), cores.get("after")
        if not rb or not ra:
            print(f"{w:12s} {roi:14s} {'MISSING':>12s} {'(one side refused or absent)'}"); nd += 1; continue
        d = ra["cycles"] - rb["cycles"]; n += 1
        if d != 0: nd += 1
        print(f"{w:12s} {roi:14s} {rb['cycles']:12,d} {ra['cycles']:12,d} {d:+8d}  {rb['cpi']:.2f}->{ra['cpi']:.2f}")
    for x in refused:
        print(f"  refused: {x}")
    print(f"ROI_COMPARE rois={n} nonzero_delta={nd} refused={len(refused)}")

if __name__ == "__main__":
    main()
