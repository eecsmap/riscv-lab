#!/usr/bin/env python3
"""Generate metrics.json for one run, from that run's manifest and its immutable raw records.

Nothing here is transcribed by hand. Every number is computed from a file in raw/, and every sample that
could not be turned into a number is recorded with the reason rather than dropped.

  gen_metrics.py <run-dir>
"""
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from probe_parse import parse, ProbeReject           # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def median_min_max(xs):
    return dict(median=statistics.median(xs), min=min(xs), max=max(xs), n=len(xs))


def main(run_dir):
    man = json.load(open(os.path.join(run_dir, "manifest.json")))
    raw_dir = os.path.join(run_dir, "raw")
    workloads = {}
    for fn in sorted(os.listdir(raw_dir)):
        if not fn.endswith(".out"):
            continue
        base = fn[:-4]
        wl, _, n = base.rpartition(".")
        workloads.setdefault(wl, []).append((int(n), os.path.join(raw_dir, fn)))

    results = []
    for wl, samples in sorted(workloads.items()):
        wdesc = json.load(open(os.path.join(ROOT, "benchmarks", "workloads", wl + ".json")))
        ok, failed = [], []
        for n, path in sorted(samples):
            exec_path = path[:-4] + ".json"
            rec = json.load(open(exec_path)) if os.path.exists(exec_path) else {}
            rel = os.path.relpath(path, ROOT)
            if rec.get("outcome") and rec["outcome"] != "completed":
                failed.append(dict(sample=n, reason=f"harness recorded outcome {rec['outcome']!r}",
                                   evidence=rel))
                continue
            try:
                parsed = parse(open(path, encoding="utf-8", errors="replace").read(), wdesc)
            except ProbeReject as e:
                failed.append(dict(sample=n, reason=str(e), evidence=rel))
                continue
            ok.append(dict(sample=n, values=parsed, evidence=rel,
                           boot_id=rec.get("boot_id"), session=rec.get("session"),
                           wall_seconds=rec.get("wall_seconds")))

        boots = sorted({s["boot_id"] for s in ok if s.get("boot_id")})
        for roi in wdesc["roi"]:
            cpis = [s["values"][roi["name"]]["cpi"] for s in ok]
            cycs = [s["values"][roi["name"]]["cycles"] for s in ok]
            hz = man["frequency"]["hz"]
            row = dict(
                platform=man["platform"], run_id=man["run_id"], workload=wl, roi=roi["name"],
                roi_description=roi["description"],
                units=dict(cycles="cycles", cpi="cycles/instruction", derived_ips="instructions/second"),
                samples_successful=len(ok), samples_failed=len(failed),
                samples_required=man["sample_policy"]["min_samples"],
                meets_sample_policy=len(ok) >= man["sample_policy"]["min_samples"],
                retired_per_sample=roi["expected_retired"],
                boot_ids=boots,
                repeat_kind=("same-session" if len(boots) <= 1 else "across-boots"),
                status=man["status"],
                evidence=[s["evidence"] for s in ok],
                failures=failed,
            )
            if cpis:
                row["cycles"] = median_min_max(cycs)
                row["cpi"] = median_min_max(cpis)
                # derived, not measured: see metrics.md section 4
                row["derived_ips"] = dict(
                    median=hz / statistics.median(cpis), min=hz / max(cpis), max=hz / min(cpis),
                    n=len(cpis), kind="model-derived",
                    formula="configured_hz / CPI",
                    frequency_source=man["frequency"]["source"])
            else:
                row["cycles"] = None
                row["cpi"] = None
                row["derived_ips"] = None
            results.append(row)

        extra = [s["values"].get("_extra") for s in ok if s["values"].get("_extra")]
        if extra:
            results.append(dict(platform=man["platform"], run_id=man["run_id"], workload=wl,
                                roi="_extra", roi_description="probe-specific auxiliary values",
                                units=dict(), samples_successful=len(extra), samples_failed=0,
                                samples_required=man["sample_policy"]["min_samples"],
                                meets_sample_policy=len(extra) >= man["sample_policy"]["min_samples"],
                                status=man["status"], boot_ids=boots,
                                repeat_kind=("same-session" if len(boots) <= 1 else "across-boots"),
                                values=[{k: v for k, v in e.items()} for e in extra],
                                evidence=[s["evidence"] for s in ok], failures=[]))

    out = dict(generated_from="manifest.json + raw/ by benchmarks/tools/gen_metrics.py",
               run_id=man["run_id"], platform=man["platform"], status=man["status"],
               frequency=man["frequency"], results=results)
    dest = os.path.join(run_dir, "metrics.json")
    with open(dest, "w") as f:
        json.dump(out, f, indent=2)
        f.write("\n")
    nok = sum(r["samples_successful"] for r in results if r["roi"] != "_extra")
    nbad = sum(len(r["failures"]) for r in results if r["roi"] != "_extra")
    short = [r for r in results if r["roi"] != "_extra" and not r["meets_sample_policy"]]
    print(f"METRICS_OK {dest}  rows={len(results)}  sample-parses ok={nok} failed={nbad}"
          + (f"  BELOW POLICY: {len(short)} rows" if short else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
