#!/usr/bin/env python3
"""Generate B0's baseline table into REPORT.md from the run metrics, so it cannot drift from the data.

It drifted: the table was written by hand at 13 ROIs and stayed there when perf05_size added 7 more, so
the report's headline table described two thirds of the baseline while the manifest said 20. A reader of
the table alone would have had the wrong number.

The table lives between markers in REPORT.md and is rewritten from metrics.json.

  gen_baseline_table.py            rewrite the table
  gen_baseline_table.py --check    fail if the committed table is not what the data produces
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
REPORT = os.path.join(ROOT, "benchmarks/baselines/B0/REPORT.md")
BEGIN = "<!-- BEGIN GENERATED baseline-table -->"
END = "<!-- END GENERATED baseline-table -->"
BOARD = "2026-09-21-board-s3-b0"
SIM = "2026-09-21-sim-boot3"


def load(run):
    p = os.path.join(ROOT, "experiments/B0-measurement/runs", run, "metrics.json")
    m = json.load(open(p))
    return m, {(r["workload"], r["roi"]): r for r in m["results"] if r["roi"] != "_extra"}


def table():
    bm, b = load(BOARD)
    _, s = load(SIM)
    hz = bm["frequency"]["hz"]
    out = [BEGIN,
           "",
           f"Board figures are the median of **5 samples**; the simulator is deterministic and verified so",
           f"over **3 samples**. Spread is `(max - min) / median`. Derived IPS is "
           f"`{hz:,} / CPI` and is **model-derived**, never measured throughput.",
           "",
           "| workload / ROI | board CPI | spread | simulator CPI | derived IPS (board) |",
           "| --- | --- | --- | --- | --- |"]
    for k in sorted(b):
        r = b[k]
        if not r["cpi"]:
            continue
        c = r["cpi"]
        sp = (c["max"] - c["min"]) / c["median"] * 100
        sr = s.get(k)
        simcol = f"{sr['cpi']['median']:.2f}" if sr and sr["cpi"] else "— *not in the sampled sim run*"
        out.append(f"| `{k[0]}` / `{k[1]}` | **{c['median']:.2f}** | {sp:.3f}% | {simcol} | "
                   f"{r['derived_ips']['median']/1e6:.3f} M |")
    nb = sum(1 for k in b if b[k]["cpi"])
    ns = sum(1 for k in b if b[k]["cpi"] and s.get(k) and s[k]["cpi"])
    out += ["",
            f"**{nb} ROIs across {len({k[0] for k in b})} probes on the board; {ns} of them also in the "
            f"sampled simulator run.** Generated from `metrics.json` by "
            f"`benchmarks/tools/gen_baseline_table.py`; `make bench-check` fails if it drifts.",
            "",
            END]
    return "\n".join(out)


def main():
    text = open(REPORT).read()
    if BEGIN not in text or END not in text:
        raise SystemExit(f"REFUSE: markers not found in {REPORT}")
    pre, rest = text.split(BEGIN, 1)
    _, post = rest.split(END, 1)
    new = pre + table() + post
    if "--check" in sys.argv:
        same = new == text
        print("BASELINE_TABLE_" + ("OK" if same else "STALE"))
        return 0 if same else 1
    open(REPORT, "w").write(new)
    print("BASELINE_TABLE_WRITTEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
