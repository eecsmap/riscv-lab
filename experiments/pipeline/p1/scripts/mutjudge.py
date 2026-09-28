#!/usr/bin/env python3
"""PIPE-P1 negative-control judge: did the fault knob fail its INTENDED property, and is that the FIRST failure?
  mutjudge.py first <pipe-prefix> <regex>            the first failure signal in the log must match <regex>
  mutjudge.py fwd <pipe-prefix> <ref-prefix> <dists> the first divergence from the reference retirement stream must be an
                                                     instruction whose source was produced at one of <dists> (e.g. 1 or 2
                                                     or 3+) retirements earlier in the reference stream
Failure signals, in log order: PIPE ASSERT, PROTO/OBS ERROR, IRQ LATENCY/PROGRESS ERROR, TOHOST code!=0, TRAP STORM,
TIMEOUT. A run whose first signal is a TIMEOUT or an infrastructure error is NOT caught as intended."""
import sys, re
SIG = re.compile(r'^(PIPE ASSERT.*|PROTO ERROR.*|OBS ERROR.*|IRQ LATENCY ERROR.*|PROGRESS ERROR.*|TOHOST code=[1-9]\d*.*|TRAP STORM.*|TIMEOUT.*|argument error.*|ELF load failed.*)$', re.M)
def first(log):
    m = SIG.search(open(log, errors='replace').read()); return m.group(1) if m else None
mode = sys.argv[1]
if mode == 'effect':
    # mutjudge.py effect <pipe-prefix> <ref-prefix>: the core logs PIPE FAULT-EFFECT pc=P when the knob changed an operand
    # an instruction really used; the first divergence from the reference must be exactly that instruction P
    pre, ref = sys.argv[2], sys.argv[3]
    eff = [int(x, 16) for x in re.findall(r'^PIPE FAULT-EFFECT knob=\d+ pc=([0-9a-f]+)', open(pre + '.log', errors='replace').read(), re.M)]
    m = bool(eff)
    def cm(f): return [l.split() for l in open(f) if not l.startswith('#')]
    ra, rb = cm(ref + '.commits'), cm(pre + '.commits')
    i = next((k for k in range(min(len(ra), len(rb))) if ra[k] != rb[k]), None)
    if not m or i is None:
        print(f'NOT CAUGHT: effect logged={bool(m)}, divergence={i}'); sys.exit(1)
    # candidates for the instruction that consumed the wrong operand: on a value difference, the record itself; on a pc
    # difference, the record before (a branch/jump that went elsewhere) or the reference's record (an instruction that
    # trapped instead of retiring, e.g. a store whose address was wrong)
    cands = [i] if int(ra[i][0], 16) == int(rb[i][0], 16) else [i - 1, i]
    hit = [c for c in cands if int(ra[c][0], 16) in set(eff)]
    ok = bool(hit)
    c = hit[0] if hit else cands[0]
    print(('CAUGHT' if ok else 'NOT CAUGHT') + f': {len(eff)} fault effect(s) logged, first at pc 0x{eff[0]:x}; first divergence at record {i}; '
          f'consumer {ra[c][0]} ({" ".join(ra[c][1:])}) {"is" if ok else "is NOT"} a logged effect point')
    sys.exit(0 if ok else 1)
if mode == 'first':
    pre, rx = sys.argv[2], sys.argv[3]
    f = first(pre + '.log')
    ok = f is not None and re.search(rx, f) is not None
    print(('CAUGHT' if ok else 'NOT CAUGHT') + f' first signal: {f or "<none: the run passed>"}'); sys.exit(0 if ok else 1)
pre, ref, dists = sys.argv[2], sys.argv[3], sys.argv[4]
def recs(f):
    out = []
    for l in open(f):
        if l.startswith('#'): continue
        p = l.split()
        out.append(dict(pc=int(p[0], 16), insn=int(p[1], 16), rd=(int(p[2][1:]) if p[2] != '-' else None), line=l.strip()))
    return out
a, b = recs(ref + '.commits'), recs(pre + '.commits')
i = next((k for k in range(min(len(a), len(b))) if a[k]['line'] != b[k]['line']), None)
if i is None:
    print(f'NOT CAUGHT: the retirement stream equals the reference ({len(a)}/{len(b)} records); first signal: {first(pre + ".log")}'); sys.exit(1)
c = i if a[i]['pc'] == b[i]['pc'] else i - 1     # a value difference: the instruction itself; a pc difference: the branch before it
ins = a[c]['insn']; op = ins & 0x7f
srcs = []
if op in (0x03, 0x13, 0x1b, 0x67, 0x73): srcs = [(ins >> 15) & 31]
if op in (0x23, 0x63, 0x33, 0x3b): srcs = [(ins >> 15) & 31, (ins >> 20) & 31]
srcs = [s for s in srcs if s != 0]
d = None
for s in srcs:
    for j in range(c - 1, -1, -1):
        if a[j]['rd'] == s: d = c - j if d is None else min(d, c - j); break
want = dists.split(',')
ok = d is not None and (str(d) in want or ('3+' in want and d >= 3))
print(('CAUGHT' if ok else 'NOT CAUGHT') + f': first divergence at record {i}; consumer {a[c]["line"]}; nearest producer distance {d}; expected {dists}')
sys.exit(0 if ok else 1)
