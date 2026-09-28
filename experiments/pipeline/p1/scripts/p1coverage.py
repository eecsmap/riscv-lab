#!/usr/bin/env python3
"""PIPE-P1: sum the PIPE COVERAGE counters over every pipeline run of sections A, B and C, each log counted ONCE.
  p1coverage.py <run dir>
(The runner up to ef9706f globbed '[ABC]/*-p.log' AND 'B/*-p.log', so every B run was counted twice.)"""
import sys, re, glob, collections
run = sys.argv[1]
logs = sorted(set(glob.glob(run + '/A/*-p.log') + glob.glob(run + '/B/*-p.log') + glob.glob(run + '/C/*-p.log')))
tot = collections.Counter(); n = 0; per = collections.Counter()
for f in logs:
    m = re.search(r'PIPE COVERAGE (.*)', open(f, errors='replace').read())
    if m:
        n += 1; per[f[len(run) + 1]] += 1
        for k, v in re.findall(r'(\w+)=(\d+)', m.group(1)): tot[k] += int(v)
print(f'== pipeline coverage summed over {n} runs (A {per["A"]}, B {per["B"]}, C {per["C"]}); each log counted once')
for k, v in tot.items(): print(f'  {k} = {v}')
