#!/usr/bin/env python3
"""PIPE-P3b: the four perf probes, pipeline vs another board session: CPI = cycles / instructions per measured window,
median over the samples (<dir>/samples/<probe>.<n>.out, the production probe output: KEY-CYC-<W>=hex, KEY-INS-<W>=hex).
  probe_compare.py <label>=<session dir> ..."""
import sys, os, re, glob, statistics
data = {}
for a in sys.argv[1:]:
    lab, d = a.split("=", 1); data[lab] = {}
    for f in sorted(glob.glob(os.path.join(d, "samples", "*.out"))):
        probe = os.path.basename(f).split(".")[0]
        t = open(f, errors="replace").read().replace("\r", "")
        cyc = dict(re.findall(r"^[A-Z0-9]+-CYC-([A-Z0-9-]+)=([0-9a-f]+)$", t, re.M))
        ins = dict(re.findall(r"^[A-Z0-9]+-INS-([A-Z0-9-]+)=([0-9a-f]+)$", t, re.M))
        for w in cyc:
            if w in ins: data[lab].setdefault((probe, w), []).append(int(cyc[w], 16) / int(ins[w], 16))
labs = list(data); keys = sorted(set().union(*[set(v) for v in data.values()]))
print("| probe | window | " + " | ".join(f"{l} CPI (median, n)" for l in labs) + (" | ratio |" if len(labs) == 2 else " |"))
print("|---|---|" + "---|" * len(labs) + ("---|" if len(labs) == 2 else ""))
for k in keys:
    vals = [data[l].get(k) for l in labs]
    cells = [f"{statistics.median(v):.3f} ({len(v)})" if v else "-" for v in vals]
    ratio = f" {statistics.median(vals[0]) / statistics.median(vals[1]):.3f} |" if len(labs) == 2 and all(vals) else (" - |" if len(labs) == 2 else "")
    print(f"| {k[0]} | {k[1]} | " + " | ".join(cells) + " |" + ratio)
