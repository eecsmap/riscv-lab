#!/usr/bin/env python3
"""Flatten every run's metrics.json into results/comparisons.csv, and form ratios only where they mean
something.

The CSV is generated, never edited. If a number in it is wrong, the raw record or the generator is wrong.

  gen_comparisons.py [--check]     --check regenerates into a temporary file and diffs, so CI can prove
                                   the committed CSV still matches the raw records.
"""
import csv
import glob
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
RUNS = os.path.join(ROOT, "experiments", "B0-measurement", "runs")

COLUMNS = ["platform", "run_id", "workload", "roi", "status", "samples_successful", "samples_failed",
           "meets_sample_policy", "repeat_kind", "retired_per_sample", "cpi_median", "cpi_min", "cpi_max",
           "cycles_median", "derived_ips_median", "derived_ips_kind", "frequency_hz", "frequency_source",
           "units_cpi", "evidence"]


class ComparisonRefused(Exception):
    """A ratio that would not mean anything."""


def ratio(a, b):
    """CPI ratio b/a. Refuses anything that is not a like-for-like comparison.

    A number divided by another number is always available; whether it means anything is the question
    this function exists to answer. Comparing a board result with a simulator one produces a figure that
    describes neither machine -- the simulator models no PS or DDR path at all -- and comparing different
    workloads produces a figure about their difference in shape.
    """
    if a["platform"] != b["platform"]:
        raise ComparisonRefused(
            f"{a['platform']} against {b['platform']}: these are different machines. The simulator does "
            f"not model the PS or DDR path, so a ratio across them describes neither.")
    if a["workload"] != b["workload"] and a["roi"].split("_")[-1] != b["roi"].split("_")[-1]:
        raise ComparisonRefused(
            f"{a['workload']}/{a['roi']} against {b['workload']}/{b['roi']}: different workload shapes")
    if a["frequency_hz"] != b["frequency_hz"]:
        raise ComparisonRefused("different configured frequencies")
    if not a["cpi_median"] or not b["cpi_median"]:
        raise ComparisonRefused("one side has no successful samples; its metric is null, not zero")
    return float(b["cpi_median"]) / float(a["cpi_median"])


def rows():
    out = []
    for mpath in sorted(glob.glob(os.path.join(RUNS, "*", "metrics.json"))):
        m = json.load(open(mpath))
        for r in m["results"]:
            if r["roi"] == "_extra":
                continue
            cpi, cyc, ips = r.get("cpi"), r.get("cycles"), r.get("derived_ips")
            out.append({
                "platform": r["platform"], "run_id": r["run_id"], "workload": r["workload"],
                "roi": r["roi"], "status": r["status"],
                "samples_successful": r["samples_successful"], "samples_failed": r["samples_failed"],
                "meets_sample_policy": r["meets_sample_policy"], "repeat_kind": r["repeat_kind"],
                "retired_per_sample": r["retired_per_sample"],
                "cpi_median": f"{cpi['median']:.4f}" if cpi else "",
                "cpi_min": f"{cpi['min']:.4f}" if cpi else "",
                "cpi_max": f"{cpi['max']:.4f}" if cpi else "",
                "cycles_median": cyc["median"] if cyc else "",
                "derived_ips_median": f"{ips['median']:.1f}" if ips else "",
                "derived_ips_kind": ips["kind"] if ips else "",
                "frequency_hz": m["frequency"]["hz"], "frequency_source": m["frequency"]["source"],
                "units_cpi": "cycles/instruction",
                "evidence": ";".join(r["evidence"]) if r["evidence"] else "",
            })
    return out


def write(dest):
    data = rows()
    with open(dest, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=COLUMNS)
        w.writeheader()
        for r in data:
            w.writerow(r)
    return len(data)


if __name__ == "__main__":
    dest = os.path.join(ROOT, "results", "comparisons.csv")
    if "--check" in sys.argv:
        with tempfile.NamedTemporaryFile("w+", suffix=".csv", delete=False) as t:
            tmp = t.name
        n = write(tmp)
        same = open(tmp).read() == (open(dest).read() if os.path.exists(dest) else "")
        os.unlink(tmp)
        print(f"COMPARISONS_{'OK' if same else 'STALE'} rows={n}")
        sys.exit(0 if same else 1)
    n = write(dest)
    print(f"COMPARISONS_WRITTEN rows={n} -> results/comparisons.csv")
