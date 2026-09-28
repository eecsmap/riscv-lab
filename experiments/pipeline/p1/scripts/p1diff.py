#!/usr/bin/env python3
"""PIPE-P1 differential judge for one program on both implementations.
  p1diff.py [--require-complete] <multi-prefix> <pipe-prefix>      (each prefix has .log .commits .mem .exit)
--require-complete (used for every program that is SUPPOSED to finish, i.e. all of section B): equality is not success.
Both runs must exit 0, both retirement streams must be non-empty, and both logs must show the harness's completion
line (tohost written, the store answered and retired). Two identical timeouts, two identical failures, two empty
streams or a run that never completed are failures, not matches (codex-pipe-p1-runner-gates item 3).
Compared: exit code; the retirement stream (pc, insn, rd, value, len); the data-request stream (address, write,
size, wdata, wmask -- every non-fetch request, cycle numbers removed); the final memory image.
Not compared (legitimately different): fetches, refills, their order and count, and every cycle number.
The pipeline log must also be free of PIPE ASSERT / PROTO ERROR / OBS ERROR / IRQ LATENCY / PROGRESS errors."""
import sys, re, os
args = sys.argv[1:]
strict = '--require-complete' in args
args = [a for a in args if a != '--require-complete']
m, p = args[0], args[1]
def rd(f): return open(f, errors='replace').read() if os.path.exists(f) else None
fails = []
for side, pre in (('multi', m), ('pipe', p)):
    for ext in ('.log', '.commits', '.mem', '.exit'):
        if rd(pre + ext) is None: fails.append(f'{side}: {ext} missing')
if fails: print('DIFF_FAIL', '; '.join(fails)); sys.exit(1)
em, ep = rd(m + '.exit').strip(), rd(p + '.exit').strip()
if em != ep: fails.append(f'exit code multi={em} pipe={ep}')
DONE = re.compile(r'^TOHOST code=0 after \d+ cycles, retired=(\d+) \(store answered and retired\)$', re.M)
if strict:
    for side, pre, ec in (('multi', m, em), ('pipe', p, ep)):
        if ec != '0': fails.append(f'{side}: exit {ec}, a completing program must exit 0')
        if not DONE.search(rd(pre + '.log')): fails.append(f'{side}: no completion line (tohost written, store answered and retired)')
        if not [l for l in rd(pre + '.commits').splitlines() if l and not l.startswith('#')]:
            fails.append(f'{side}: empty retirement stream')
# records only: the first line of a commit file is a '#' header, which is not a retirement (it was counted as one in
# P1 run-1..3 summaries, so their 'retired=' figures were one too high per run)
cm = [l for l in rd(m + '.commits').splitlines() if l and not l.startswith('#')]
cp = [l for l in rd(p + '.commits').splitlines() if l and not l.startswith('#')]
if cm != cp:
    i = next((k for k in range(min(len(cm), len(cp))) if cm[k] != cp[k]), min(len(cm), len(cp)))
    fails.append(f'retirement stream differs at record {i}: multi={cm[i] if i < len(cm) else "<end>"} pipe={cp[i] if i < len(cp) else "<end>"} (lengths {len(cm)}/{len(cp)})')
dq = lambda t: [re.sub(r'cyc=\d+ ', '', l) for l in t.splitlines() if l.startswith('DREQ ')]
dm, dp = dq(rd(m + '.log')), dq(rd(p + '.log'))
if dm != dp:
    i = next((k for k in range(min(len(dm), len(dp))) if dm[k] != dp[k]), min(len(dm), len(dp)))
    fails.append(f'data-request stream differs at {i}: multi={dm[i] if i < len(dm) else "<end>"} pipe={dp[i] if i < len(dp) else "<end>"}')
if rd(m + '.mem') != rd(p + '.mem'): fails.append('final memory image differs')
bad = re.findall(r'^(PIPE ASSERT.*|PROTO ERROR.*|OBS ERROR.*|IRQ LATENCY ERROR.*|PROGRESS ERROR.*)$', rd(p + '.log'), re.M)
if bad: fails.append(f'pipeline log: {bad[0]} (+{len(bad) - 1} more)')
if re.search(r'^(PROTO ERROR|OBS ERROR)', rd(m + '.log'), re.M): fails.append('multicycle log has protocol/observation errors')
n = len(cp)
print(('DIFF_OK' if not fails else 'DIFF_FAIL') + f' exit={ep} retired={n} dreq={len(dp)}' + ('' if not fails else ' :: ' + ' | '.join(fails)))
sys.exit(1 if fails else 0)
