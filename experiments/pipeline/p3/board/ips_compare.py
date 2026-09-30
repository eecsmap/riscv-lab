#!/usr/bin/env python3
"""PIPE-P3b: board CPI and derived MIPS (40 MHz / CPI) for the IPS campaign's four multicycle stages and the single
pipeline, from the raw probe samples (median of the samples per ROI). Markdown table on stdout.
  ips_compare.py <IPS campaign board dir> <pipeline session dir>"""
import sys, os, re, glob, statistics
I, P = sys.argv[1], sys.argv[2]
sess = {"baseline": glob.glob(I + "/session-baseline-*")[0], "fetch32": glob.glob(I + "/session-fetch32-*")[0],
        "tlb": glob.glob(I + "/session-tlb-*")[0], "cache": glob.glob(I + "/session-cache-*")[0], "pipeline": P}
data = {}
for lab, d in sess.items():
    data[lab] = {}
    for f in glob.glob(os.path.join(d, "samples", "*.out")):
        probe = os.path.basename(f).split(".")[0]
        t = open(f, errors="replace").read().replace("\r", "")
        cyc = dict(re.findall(r"^[A-Z0-9]+-CYC-([A-Z0-9-]+)=([0-9a-f]+)$", t, re.M))
        ins = dict(re.findall(r"^[A-Z0-9]+-INS-([A-Z0-9-]+)=([0-9a-f]+)$", t, re.M))
        for w in cyc:
            if w in ins: data[lab].setdefault((probe, w), []).append(int(cyc[w], 16) / int(ins[w], 16))
labs = list(sess)
print("| ROI | " + " | ".join(labs) + " | pipeline vs cache |")
print("|---|" + "---:|" * (len(labs) + 1))
for k in sorted(data["pipeline"]):
    cpi = {l: statistics.median(data[l][k]) for l in labs if k in data[l]}
    print(f"| {k[0]} {k[1]} | " + " | ".join(f"{cpi[l]:.2f} / {40 / cpi[l]:.2f}" if l in cpi else "-" for l in labs)
          + f" | {cpi['cache'] / cpi['pipeline']:.2f}x |")
print("\nsamples per cell: " + ", ".join(f"{l} {sorted(set(len(v) for v in data[l].values()))}" for l in labs))
print("sessions: " + "; ".join(f"{l} {os.path.basename(d)}" for l, d in sess.items()))
