#!/usr/bin/env python3
"""PIPE-P2b A negative-control judge: was the CPU-A injection rejected by its OWN named check, and first?
  ajudge.py <prefix> <regex>               the first failure signal of the run (<prefix>.log) must match <regex>
  ajudge.py <prefix> <regex> <score file>  the CPU-A checker's first FAIL line (<score file>) must match <regex>, and
                                           the run itself may have failed only through the program's own exit code
Failure signals, in log order: PIPE ASSERT, PROTO/OBS ERROR, A_OBS_FAIL (the harness's atomic observation monitor),
IRQ LATENCY/PROGRESS ERROR, TOHOST code!=0, TRAP STORM, TIMEOUT. A run killed by the timeout (<prefix>.exit 124), a
missing log, or a checker that found nothing is NOT caught."""
import sys, re, os
SIG = re.compile(r'^(PIPE ASSERT.*|PROTO ERROR.*|OBS ERROR.*|A_OBS_FAIL.*|IRQ LATENCY ERROR.*|PROGRESS ERROR.*|'
                 r'TOHOST code=[1-9]\d*.*|TRAP STORM.*|TIMEOUT.*|argument error.*|ELF load failed.*)$', re.M)
pre, rx = sys.argv[1], sys.argv[2]
score = sys.argv[3] if len(sys.argv) > 3 else None
def out(ok, msg): print(('CAUGHT ' if ok else 'NOT CAUGHT ') + msg); sys.exit(0 if ok else 1)
try:
    log = open(pre + '.log', errors='replace').read(); ec = open(pre + '.exit').read().strip()
except OSError as e: out(False, f'infrastructure: {e}')
if ec == '124': out(False, 'infrastructure: the run was killed by the timeout')
m = SIG.search(log); first = m.group(1) if m else None
if score is None:
    out(first is not None and re.search(rx, first) is not None, f'first signal: {first or "<none: the run passed>"}')
if first is not None and not first.startswith('TOHOST code='):
    out(False, f'the run failed before the checker could judge it: first signal {first}')
try: fails = [l.strip() for l in open(score, errors='replace') if 'FAIL' in l]
except OSError: out(False, f'no checker output {score}')
if not fails: out(False, f'the checker found nothing (run: {first or "passed"})')
out(re.search(rx, fails[0]) is not None, f'first checker failure: {fails[0][:160]} (run: {first or "passed"})')
