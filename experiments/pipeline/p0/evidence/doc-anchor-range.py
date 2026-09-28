#!/usr/bin/env python3
"""Every file:line (and :a-b, :a,b) cited in CONTRACT.md / TESTPLAN.md resolves to a live file and lies in range. A bare
`:N` inherits the last file named before it, which is how a reader resolves it too."""
import re, os, sys
R = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../../..'))
ext = {'FINAL-COMPARISON.md': '/home/engineer/fpga/worktrees/ips-cache/experiments/IPS-campaign/FINAL-COMPARISON.md',
       'E1-clock-scaling/README.md': '/home/engineer/fpga/riscv-lab/experiments/E1-clock-scaling/README.md',
       'm2-3/REPORT.md': '/home/engineer/fpga/experiments/teaching-cpu/m2-3/REPORT.md',
       'TEST_PLAN.md': '/home/engineer/fpga/experiments/teaching-cpu/m2-prep/TEST_PLAN.md',
       'm0/CONTRACT.md': R + '/experiments/multicore/archive/m0/CONTRACT.md'}
live = ['rtl/cpu', 'soc/scala/teaching', 'tests/cpu/tb', 'tools/xv6-boot/scripts', 'experiments/multicore/archive/m1/tests/core-suites']
def resolve(name):
    for k, v in ext.items():
        if name.endswith(k): return v
    for d in live:
        p = os.path.join(R, d, os.path.basename(name))
        if os.path.exists(p): return p
tot = bad = 0
for doc in ['CONTRACT.md', 'TESTPLAN.md']:
    txt = open(os.path.join(R, 'experiments/pipeline/p0', doc)).read(); cur = None
    for m in re.finditer(r'`?([\w./{},*-]+\.(?:v|vh|scala|cpp|sh|py|md))?`?\s*:(\d+)(?:-(\d+))?((?:,\s*\d+(?:-\d+)?)*)', txt):
        if m.group(1): cur = m.group(1)
        if not cur: continue
        nums = [int(m.group(2))] + ([int(m.group(3))] if m.group(3) else []) + [int(x) for x in re.findall(r'\d+', m.group(4) or '')]
        p = resolve(cur); tot += 1
        if not p: bad += 1; print('NOFILE', doc, cur, nums); continue
        n = sum(1 for _ in open(p, errors='replace'))
        good = max(nums) <= n; bad += (not good)
        print('ok   ' if good else 'RANGE', doc, cur, nums, '' if good else f'file has {n}')
print(f'DOC_ANCHORS checked={tot} bad={bad}'); sys.exit(0 if bad == 0 else 1)
