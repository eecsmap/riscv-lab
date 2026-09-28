#!/usr/bin/env python3
"""PIPE-P1 ROI measurement from a +pipe-trace log (CMT lines carry the retirement cycle) and the ELF's symbols.
  perf.py <log> <nm-file> [pass]
ROI k is (roik_b, roik_e]: from the retirement of roik_b (a nop) to the retirement of roik_e. Only the LAST pass
through each ROI is measured (the first pass warms the I-cache). Reports retirements, cycles, cycles per
instruction, and the histogram of cycle intervals between consecutive retirements inside the ROI."""
import sys, re, collections
log, nm = sys.argv[1], sys.argv[2]
sym = {}
for l in open(nm):
    f = l.split()
    if len(f) == 3: sym[f[2]] = int(f[0], 16)
cm = [(int(c), int(p, 16)) for c, p in re.findall(r'^CMT cyc=(\d+) pc=([0-9a-f]+)', open(log).read(), re.M)]
out = []
k = 1
while f'roi{k}_b' in sym:
    b, e = sym[f'roi{k}_b'], sym[f'roi{k}_e']
    windows = []; cur = None
    for cyc, pc in cm:
        if pc == b: cur = [(cyc, pc)]
        elif cur is not None:
            cur.append((cyc, pc))
            if pc == e: windows.append(cur); cur = None
    if windows:
        w = windows[-1]
        n = len(w) - 1; cyc = w[-1][0] - w[0][0]
        iv = collections.Counter(w[i][0] - w[i - 1][0] for i in range(1, len(w)))
        hist = ' '.join(f'{d}:{c}' for d, c in sorted(iv.items()))
        out.append(f'ROI{k} retired={n} cycles={cyc} CPI={cyc / n:.3f} intervals[{hist}]')
    else:
        out.append(f'ROI{k} NOT FOUND in the trace')
    k += 1
print('\n'.join(out))
