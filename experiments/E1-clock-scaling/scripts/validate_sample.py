#!/usr/bin/env python3
"""Decide whether one probe sample is usable, using the PRODUCTION parser.

RC=0 is not a result. probe_parse.parse checks the probe's own verdict, its completion marker, the
recorded exit status and the retired-instruction window declared in the workload descriptor -- which is
what "usable sample" has meant everywhere else in B0, and is what it must mean here too.

  validate_sample.py <sample.out> <probe-id>
"""
import json
import os
import sys

ROOT = "/home/engineer/fpga/riscv-lab"
sys.path.insert(0, os.path.join(ROOT, "benchmarks/tools"))
import probe_parse                                                     # noqa: E402


def main(argv):
    path, probe = argv[0], argv[1]
    desc = os.path.join(ROOT, "benchmarks/workloads", f"{probe}.json")
    if not os.path.exists(desc):
        print(f"REJECT {path}: no workload descriptor for {probe}")
        return 2
    wl = json.load(open(desc))
    try:
        res = probe_parse.parse(open(path, errors="replace").read(), wl)
    except probe_parse.ProbeReject as e:
        print(f"REJECT {path}: {e}")
        return 1
    print(f"USABLE {path}: " + ", ".join(f"{k}={v.get('cycles')}c" for k, v in sorted(res.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
