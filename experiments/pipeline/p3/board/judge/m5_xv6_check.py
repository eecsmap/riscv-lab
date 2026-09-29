#!/usr/bin/env python3
"""MC-M5 judge for one dual xv6 BOARD run directory (<X>/run made by board-runner.py, <X>/runner.log).
Derived from m3/tests/m3_check.py. Layers 1, 3 and 4 of that judge apply unchanged; layer 2 (per-hart HARTS /
HARTS_USER counters) does NOT exist on the board: those lines are printed by the simulator main, the board host
has no per-hart counters. The board's dual-core evidence is the six M2b gates of the install session, not this run.
The block-device trace (RBOOT BDEV_*) is printed by the simulator too, so the disk layer is not applied either.
  m5_xv6_check.py <X>"""
import sys, os, re, subprocess
D = sys.argv[1]; RUN = os.path.join(D, 'run'); HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.join(HERE, '..', 'tools', 'xv6-boot', 'scripts', 'check-xv6.py')
fails = []
def bad(m): fails.append(m)
def rd(p): return open(p, errors='replace').read() if os.path.exists(p) else ''
con = rd(os.path.join(RUN, 'console.txt')); runner = rd(os.path.join(D, 'runner.log')); verdict = rd(os.path.join(D, 'verdict.txt'))
if not con: print('FAIL no console'); sys.exit(1)
m = re.search(r'XV6_RC=(\d+)', verdict)
if not m or m.group(1) != '0': bad(f'runner exit: {verdict.strip() or "<none>"}')
r = subprocess.run([sys.executable, CHECK, RUN, '--require-commands'], capture_output=True, text=True); chk = (r.stdout + r.stderr).strip()
if r.returncode != 0: bad('check-xv6.py: ' + chk.replace('\n', ' | ')[:400])
else: print('INFO check-xv6.py --require-commands: ' + chk.splitlines()[-1][:160])
if re.search(r'panic:', con): bad('kernel panic: ' + re.search(r'panic:[^\n]*', con).group(0)[:120])
if 'unexpected interrupt' in con or 'unexpected scause' in con: bad('the kernel reported an unexpected interrupt/trap')
for cksum in ['B0-COMPUTE-CHECKSUM', 'B0-ARRAY-CHECKSUM', 'B0-FILE-CHECKSUM']:
    c = len(re.findall(cksum, con))
    if c > 1: bad(f'{cksum} printed {c} times')
typed = re.findall(r"typed: '([^']+)'", runner)
if not typed: bad('the runner typed nothing')
for cmd in set(typed):
    echoed = len(re.findall(r'\$ ' + re.escape(cmd) + r'\s*\n', con))
    if echoed != typed.count(cmd): bad(f'command {cmd!r} typed {typed.count(cmd)}x but echoed {echoed}x')
def seg(cmd):
    m = re.search(r'\$ ' + re.escape(cmd) + r'\s*\n(.*?)(?=\n\$ |\Z)', con, re.S); return m.group(1) if m else None
s = seg('m3par2')
if s is None: bad('m3par2 has no segment')
else:
    c0 = re.findall(r'M4-PAR-CHILD0 checksum=([0-9a-f]+)', s); c1 = re.findall(r'M4-PAR-CHILD1 checksum=([0-9a-f]+)', s); done = s.find('M4-PAR-DONE')
    if len(c0) != 1 or len(c1) != 1: bad(f'm3par2: child reports {len(c0)}/{len(c1)}, expected exactly one each')
    else:
        if c0[0] != 'f6d983767e3c5638' or c1[0] != '01d86a21f972f3fa': bad(f'm3par2: checksums {c0[0]} {c1[0]} wrong')
        if done < 0 or done < max(s.find('M4-PAR-CHILD0'), s.find('M4-PAR-CHILD1')): bad('m3par2: the parent reported before both children')
s = seg('m3fs')
if s is None: bad('m3fs has no segment')
else:
    ch = re.findall(r'M3-FS-CHILD([01]) ok=(\d)', s); done = s.find('M3-FS-DONE')
    if sorted(c for c, _ in ch) != ['0', '1'] or any(o != '1' for _, o in ch): bad(f'm3fs: child reports {ch}')
    elif done < max(s.find('M3-FS-CHILD0'), s.find('M3-FS-CHILD1')): bad('m3fs: the parent reported before both children')
s = seg('b0compute')
if s is None or 'B0-COMPUTE-CHECKSUM=5adf55920bf7696' not in (s or '').lower().replace('b0-compute-checksum', 'B0-COMPUTE-CHECKSUM'): bad('b0compute: checksum line missing')
stop = re.search(r'# stop: (\S+)', rd(os.path.join(RUN, 'stages.txt')))
if not stop or stop.group(1) != 'deliberate-stop-after-all-commands': bad(f'run did not end deliberately: {stop.group(1) if stop else "<no stop record>"}')
print(('PASS' if not fails else 'FAIL') + f' {D}')
for f in fails: print('  FAIL:', f)
sys.exit(1 if fails else 0)
