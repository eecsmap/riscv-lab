#!/usr/bin/env python3
"""Turn a stage run directory into metrics, under the campaign's measurement contract.

Cycles come from the probe's own counter reads, not from the harness's cycle total: the counters bound
the ROI, the harness total includes boot and host handshake. Retirement is checked against the workload
descriptor, so a window that did not run as described is refused rather than reported.

IPS and ROI time are computed at the campaign's 40 MHz, from SIMULATED cycles. That makes them a
property of the simulated memory system, not of the board -- the same probe reads CPI ~19 here and
40.34 on hardware. They are never pooled, and the platform is recorded on every row.

  gen_stage_metrics.py <run-dir> --stage <name> [--out metrics.json]
"""
import argparse
import glob
import json
import os
import re
import sys

HZ = 40_000_000
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
VALUE = re.compile(r"^([A-Z0-9][A-Z0-9-]*)=([0-9a-fA-F]{16})\s*$", re.M)


def descriptors():
    d = {}
    for p in glob.glob(os.path.join(ROOT, "benchmarks/workloads/*.json")) + \
             glob.glob(os.path.join(ROOT, "experiments/IPS-campaign/workloads/*.json")):
        w = json.load(open(p))
        if w.get("kind") == "microbenchmark":
            d[w["id"]] = w
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--stage", required=True)
    ap.add_argument("--out")
    a = ap.parse_args()
    desc = descriptors()

    rows, refused = [], []
    for c in sorted(glob.glob(os.path.join(a.run, "runs", "*", "console-recovered.txt"))):
        core, prog = os.path.basename(os.path.dirname(c)).split("-", 1)
        w = desc.get(prog)
        if not w:
            continue
        text = open(c, errors="replace").read()
        vals = {k: int(v, 16) for k, v in VALUE.findall(text)}
        if w["marker"] not in text:
            refused.append(dict(core=core, workload=prog, reason=f"marker {w['marker']!r} absent"))
            continue
        for roi in w["roi"]:
            cyc = vals.get(roi["cycles_label"])
            ret = vals.get(roi["retired_label"])
            if not cyc or not ret:
                refused.append(dict(core=core, workload=prog, roi=roi["name"],
                                    reason="a counter is missing or zero; null, not repaired"))
                continue
            exp = roi.get("expected_retired")
            if exp is not None and ret != exp:
                refused.append(dict(core=core, workload=prog, roi=roi["name"],
                                    reason=f"retired {ret}, expected {exp}: the window did not run as "
                                           f"described, so its cycle count is about some other program"))
                continue
            rows.append(dict(platform="simulator", stage=a.stage, core=core, workload=prog,
                             roi=roi["name"], cycles=cyc, retired=ret,
                             cpi=cyc / ret, ips_at_40mhz=ret * HZ / cyc, roi_seconds=cyc / HZ))

    # gains, core against core, like for like
    by = {(r["core"], r["workload"], r["roi"]): r for r in rows}
    for r in rows:
        b = by.get(("baseline", r["workload"], r["roi"]))
        r["gain_vs_baseline"] = (b["cycles"] / r["cycles"]) if b and b is not r else (1.0 if b is r else None)

    axi = {}
    for c in sorted(glob.glob(os.path.join(a.run, "runs", "*", "console-recovered.txt"))):
        core, prog = os.path.basename(os.path.dirname(c)).split("-", 1)
        m = re.search(r"^AXI ar=(\d+) r=(\d+)", open(c, errors="replace").read(), re.M)
        if m:
            axi[f"{core}/{prog}"] = dict(ar=int(m.group(1)), r=int(m.group(2)))

    res = dict(
        stage=a.stage, platform="simulator", clock_hz=HZ,
        counters="the probe's own cycle/instret reads, bounding the ROI",
        caution="IPS and roi_seconds are computed at 40 MHz from SIMULATED cycles. The simulated memory "
                "system is not the board's PS DDR -- perf03's 32-bit ROI reads CPI 19.0 here and 40.34 "
                "on hardware -- so these are not board figures and are never pooled with board results.",
        rows=rows, refused=refused, axi_reads=axi)
    dest = a.out or os.path.join(a.run, "metrics.json")
    json.dump(res, open(dest, "w"), indent=2)

    print(f"{'workload':13}{'roi':14}{'core':10}{'cycles':>10}{'retired':>9}{'CPI':>8}"
          f"{'IPS@40MHz':>13}{'gain':>8}")
    for r in sorted(rows, key=lambda r: (r["workload"], r["roi"], r["core"])):
        g = f"{r['gain_vs_baseline']:.3f}" if r["gain_vs_baseline"] else "-"
        print(f"  {r['workload']:12}{r['roi']:13}{r['core']:9}{r['cycles']:>10}{r['retired']:>9}"
              f"{r['cpi']:>8.2f}{r['ips_at_40mhz']:>13,.0f}{g:>8}")
    if refused:
        print(f"  REFUSED {len(refused)}:")
        for x in refused:
            print(f"    {x['core']}/{x['workload']}{'/' + x['roi'] if x.get('roi') else ''}: {x['reason']}")
    print(f"STAGE_METRICS rows={len(rows)} refused={len(refused)} -> {os.path.relpath(dest)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
