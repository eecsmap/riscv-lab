#!/usr/bin/env python3
"""Generate application-workload metrics for a run, from its stages.txt and console.txt.

Application workloads are not probes: they carry no cycle counters, so the metrics contract gives them
wall time only and leaves cycle metrics null. This extracts, per workload, the wall time between its
stage and the one before it, the checksum the target actually printed, and whether that matches the
profile's expectation -- **case-insensitively**, because xv6's printf uses "0123456789ABCDEF" while the
expectations were computed on the host with C's %lx.

Nothing is transcribed: the first version of these results was assembled by hand, which is exactly the
habit the rest of B0 avoids.

  gen_app_metrics.py <run-dir>
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def main(run):
    man = json.load(open(os.path.join(run, "manifest.json")))
    raw = os.path.join(run, "raw")
    stages = open(os.path.join(raw, "stages.txt")).read()
    console = open(os.path.join(raw, "console.txt")).read()

    rows = [l.split("\t") for l in stages.splitlines() if l and not l.startswith("#")]
    hdr = dict(re.findall(r"^# ([\w ]+): (.*)$", stages, re.M))
    wl_name = hdr.get("workload", "default")

    # The profile's expectations. Preferably from xv6_console, the same source the driver and checker
    # use -- but that only carries PROFILES once the delta is applied, and this has to work in both
    # states, so it falls back to the workload descriptors, which are where the expectations are
    # defined in the first place.
    expected = {}
    sys.path.insert(0, os.path.join(ROOT, "tools/xv6-boot/scripts"))
    try:
        from xv6_console import PROFILES                                 # noqa: E402
        expected = {n: rx for n, _, rx in PROFILES.get(wl_name, [])}
        source = "xv6_console.PROFILES (the delta is applied)"
    except ImportError:
        for wp in sorted(os.listdir(os.path.join(ROOT, "benchmarks/workloads"))):
            if not wp.endswith(".json"):
                continue
            w = json.load(open(os.path.join(ROOT, "benchmarks/workloads", wp)))
            if w.get("kind") == "application" and w.get("expected_output"):
                expected[w["id"]] = "(?i)" + re.escape(w["expected_output"])
        source = "benchmarks/workloads/*.json (the delta is not applied here)"
    print(f"  expectations from {source}")

    out, prev = [], 0.0
    for status, t, name in rows:
        t = float(t)
        if name.startswith("command "):
            wl = name.split(" ", 1)[1]
            rx = expected.get(wl)
            m = re.search(rf"B0-{wl[2:].upper()}-CHECKSUM=([0-9A-Fa-f]+)", console)
            observed = m.group(1) if m else None
            matched = bool(rx and observed is not None and re.search(rx, console, re.M))
            out.append(dict(
                workload=wl,
                status="completed" if status == "ok" else "did-not-finish",
                wall_seconds=round(t - prev, 1),
                cumulative_seconds=t,
                observed_checksum=observed,
                expected_pattern=rx,
                checksum_matches=matched,
                cycles=None, cpi=None,
                metrics_note="cycles and CPI are null by contract: a user program cannot read mcycle "
                             "without kernel changes made for measurement convenience",
                wall_measures="the SIMULATOR, not the target" if man["platform"] == "simulator"
                              else "the host-side command, including console transport"))
        prev = t

    done = [a for a in out if a["status"] == "completed"]
    res = dict(generated_from="manifest.json + raw/ by benchmarks/tools/gen_app_metrics.py",
               expectation_source=source,
               run_id=man["run_id"], platform=man["platform"], status=man["status"],
               workload_profile=wl_name,
               disk_at_start=man["artifacts"].get("disk_at_start_sha256"),
               disk_pristine=man["artifacts"].get("disk_pristine_b0_sha256"),
               disk_was_fresh=(man["artifacts"].get("disk_at_start_sha256")
                               == man["artifacts"].get("disk_pristine_b0_sha256")),
               completed=len(done), defined=len(out),
               all_checksums_match=bool(done) and all(a["checksum_matches"] for a in done),
               applications=out)
    with open(os.path.join(run, "app-metrics.json"), "w") as f:
        json.dump(res, f, indent=2)
        f.write("\n")
    print(f"APP_METRICS_OK {len(done)}/{len(out)} completed; "
          f"checksums {'all match' if res['all_checksums_match'] else 'MISMATCH'}; "
          f"disk {'fresh' if res['disk_was_fresh'] else 'NOT FRESH'}")
    for a in out:
        print(f"  {a['workload']:11} {a['status']:15} {a['wall_seconds']:>9.1f}s  "
              f"{a['observed_checksum'] or '-'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
