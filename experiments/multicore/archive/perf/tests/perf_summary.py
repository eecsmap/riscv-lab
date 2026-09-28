#!/usr/bin/env python3
"""MC-PERF summary: medians/ranges/throughput per configuration, S2 = T1/T2 (medians), E2 = S2/2.
  perf_summary.py <single run dir> <dual run dir> [--mtime-hz 400000]
Reads the RESULT lines that perf_check.py wrote to <dir>/check.txt (each must be a PASS record; refuses otherwise)."""
import sys, os, re, statistics, argparse
ap = argparse.ArgumentParser(); ap.add_argument('single'); ap.add_argument('dual'); ap.add_argument('--mtime-hz', type=float, default=400000.0)
a = ap.parse_args()
WORK = {'PERF-COMPUTE': ('iterations', lambda size: 4 * size), 'PERF-ARRAY': ('element updates', lambda size: 4 * size * 16384)}
def load(d):
    t = open(os.path.join(d, 'check.txt')).read()
    if not re.search(r'^PASS ', t, re.M): sys.exit(f'REFUSE: {d}/check.txt is not a PASS record')
    runs = {}
    for tag, size, dm in re.findall(r'^RESULT (PERF-\w+) size=(\d+) dmtime=(\d+)', t, re.M):
        runs.setdefault((tag, int(size)), []).append(int(dm))
    return runs
s1, s2 = load(a.single), load(a.dual)
print(f'| workload | size/child | total work | n | T1 median (range) s | T2 median (range) s | throughput 1-core | throughput 2-core | S2 = T1/T2 | E2 = S2/2 |')
print('|---|---|---|---|---|---|---|---|---|---|')
for key in sorted(s1):
    tag, size = key
    if key not in s2: sys.exit(f'REFUSE: {key} present in single but not in dual')
    d1, d2 = s1[key], s2[key]
    if len(d1) < 3 or len(d2) < 3: sys.exit(f'REFUSE: fewer than 3 repetitions for {key}: {len(d1)}/{len(d2)}')
    t1 = [x / a.mtime_hz for x in d1]; t2 = [x / a.mtime_hz for x in d2]
    m1, m2 = statistics.median(t1), statistics.median(t2); unit, wf = WORK[tag]; w = wf(size)
    S = m1 / m2
    print(f'| {tag} | {size:,} | {w:,} {unit} | {len(d1)}/{len(d2)} | {m1:.3f} ({min(t1):.3f}–{max(t1):.3f}) | {m2:.3f} ({min(t2):.3f}–{max(t2):.3f}) | {w/m1:,.0f} {unit}/s | {w/m2:,.0f} {unit}/s | **{S:.3f}** | {S/2:.3f} |')
    print(f'  raw dmtime units: single {d1}  dual {d2}', file=sys.stderr)
