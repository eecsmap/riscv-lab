#!/usr/bin/env python3
"""MC-M3 judge for one xv6 run directory made by run-xv6.sh (<out>/run is the runner's transcript directory).

Layers, all required:
  1. the production checker (isolated copy of check-xv6.py) with --require-commands: every command of the
     workload owns its own prompt segment, in order, with its output inside that segment; the stage record is
     complete and the run ended deliberately.
  2. per-hart hardware evidence from the host's lines in the console (the simulator main prints them):
     HARTS (retired/traps per hart), HARTS_USER (user-mode commits and scheduler-range commits per hart), the
     PROGRESS samples (EVH ... PROGRESS ... u0= u1= g0= g1=) -- both harts must have reached the scheduler
     (range commits > 0), both must have committed user-mode instructions, and hart 1's user commits must
     GROW across the run (not a one-off).
  3. console sanity: no panic, no duplicated echoed command line, no duplicated B0 checksum line, the block
     device trace (RBOOT BDEV_OP / BDEV_DONE) strictly alternates (one request in flight at a time).
  4. per-command semantics beyond the regexes: m3par's two children each reported once and BEFORE the
     parent's DONE line, which is BEFORE the next prompt; the union of the children's hart masks covers both
     harts (or the run is flagged) ; m3migrate ran on both harts; m3fs both children ok before DONE.

  m3_check.py <outdir> [--n1] [--min-user1 N]     (--n1: single-core run, hart-1 rules off)
"""
import sys, os, re, argparse, subprocess
ap = argparse.ArgumentParser(); ap.add_argument('outdir'); ap.add_argument('--n1', action='store_true')
ap.add_argument('--min-user1', type=int, default=100000, help='hart 1 must have committed at least this many user-mode instructions')
ap.add_argument('--no-commands', action='store_true', help='a boot-only run (workload m3boot): skip the command layer')
ap.add_argument('--no-disk', action='store_true', help='the workload has no disk-writing command; otherwise block-device events are REQUIRED and must close')
a = ap.parse_args(); D = a.outdir; RUN = os.path.join(D, 'run')
HERE = os.path.dirname(os.path.abspath(__file__)); CHECK = os.path.join(HERE, '..', 'tools', 'xv6-boot', 'scripts', 'check-xv6.py')
fails = []
def bad(m): fails.append(m)
def rd(p): return open(p, errors='replace').read() if os.path.exists(p) else ''
con = rd(os.path.join(RUN, 'console.txt')); stages = rd(os.path.join(RUN, 'stages.txt')); runner = rd(os.path.join(D, 'runner.log'))
if not con: bad('no console.txt'); print('FAIL no console'); sys.exit(1)
# ---- 1. the production checker
args = [sys.executable, CHECK, RUN] + ([] if a.no_commands else ['--require-commands'])
r = subprocess.run(args, capture_output=True, text=True); chk = (r.stdout + r.stderr).strip()
if r.returncode != 0: bad('check-xv6.py: ' + chk.replace('\n', ' | ')[:400])
# ---- 2. per-hart hardware evidence
hm = re.search(r'HARTS n=(\d+) retired0=(\d+) traps0=(\d+) cause0=0x[0-9a-f]+ maxawait0=(\d+) awaits0=(\d+) epoch0=(\d+) retired1=(\d+) traps1=(\d+)', con)
um = re.search(r'HARTS_USER user0=(\d+) range0=(\d+) user1=(\d+) range1=(\d+)', con)
if not hm: bad('no HARTS line: per-hart totals missing')
if not um: bad('no HARTS_USER line: per-hart user-mode / scheduler-range totals missing')
H = None
if hm and um:
    n = int(hm.group(1)); ret = [int(hm.group(2)), int(hm.group(7))]; traps = [int(hm.group(3)), int(hm.group(8))]
    user = [int(um.group(1)), int(um.group(3))]; rng = [int(um.group(2)), int(um.group(4))]
    H = dict(n=n, retired=ret, traps=traps, user=user, range=rng)
    want_n = 1 if a.n1 else 2
    if n != want_n: bad(f'HARTS n={n}, expected {want_n}')
    harts = range(want_n)
    for h in harts:
        if ret[h] == 0: bad(f'hart {h} retired nothing')
        if rng[h] == 0: bad(f'hart {h} never committed inside the scheduler() range (never reached the scheduler)')
        if user[h] == 0: bad(f'hart {h} never committed a user-mode instruction')
        if traps[h] < 10: bad(f'hart {h} took only {traps[h]} traps (timer interrupts alone should be many)')
    if not a.n1 and user[1] < a.min_user1: bad(f'hart 1 committed {user[1]} user-mode instructions < {a.min_user1}: it did not do real user work')
    # growth: the PROGRESS samples carry u1 per 20M cycles; hart 1's user count must increase across samples
    if not a.n1:
        # the runner keeps the host's EVH lines in run.log (they are trace lines to it), so read them there
        samples = [int(x) for x in re.findall(r'PROGRESS .* u1=(\d+)', con + rd(os.path.join(RUN, 'run.log')))]
        if len(samples) < 3: bad(f'only {len(samples)} PROGRESS samples with per-hart user counts (need >= 3 to judge growth)')
        grow = sum(1 for i in range(1, len(samples)) if samples[i] > samples[i - 1])
        if len(samples) >= 3 and grow < 2: bad(f'hart 1 user-mode commits did not grow across PROGRESS samples: {samples[:8]}')
        print(f'INFO harts: retired {ret} user {user} sched-range {rng} traps {traps}; hart1 user growth steps {grow}/{max(0, len(samples)-1)}')
    else:
        print(f'INFO n1: retired {ret[0]} user {user[0]} sched-range {rng[0]} traps {traps[0]}')
# ---- 3. console sanity
if re.search(r'panic:', con): bad('kernel panic in the console: ' + re.search(r'panic:[^\n]*', con).group(0)[:120])
if 'unexpected interrupt' in con or 'unexpected scause' in con: bad('the kernel reported an unexpected interrupt/trap')
for cksum in ['B0-COMPUTE-CHECKSUM', 'B0-ARRAY-CHECKSUM', 'B0-FILE-CHECKSUM']:
    c = len(re.findall(cksum, con))
    if c > 1: bad(f'{cksum} printed {c} times (duplicated output or duplicated command)')
ops = re.findall(r'RBOOT\s+\d+\s+(BDEV_OP|BDEV_DONE)', con + rd(os.path.join(RUN, 'run.log')))
# M4 review: the disk trace is REQUIRED for a workload that touches the disk (the file system is read at boot and
# every profile here writes files), must alternate strictly, and must be CLOSED at the end of the run (the last
# event is a completion: no request left open when the host declared the run finished)
if not ops:
    if not (a.no_disk or a.no_commands): bad('block device: no BDEV_OP/BDEV_DONE events at all (the disk trace is missing or the disk was never used)')
else:
    state = 0; viol = 0
    for o in ops:
        if o == 'BDEV_OP':
            if state == 1: viol += 1
            state = 1
        else:
            if state == 0: viol += 1
            state = 0
    if viol: bad(f'block device: {viol} overlapping request/completion pairs (requests from two harts were not serialised)')
    if state != 0: bad('block device: the trace ends with a request still open (the last event is BDEV_OP, no BDEV_DONE): not closed at EOF')
    if ops.count('BDEV_OP') != ops.count('BDEV_DONE'): bad(f'block device: {ops.count("BDEV_OP")} requests but {ops.count("BDEV_DONE")} completions')
    if not viol and state == 0: print(f'INFO disk: {ops.count("BDEV_OP")} block-device operations, strictly alternating request/completion, closed at EOF')
# the echoed command lines: each typed command must appear as an echoed line exactly once (no duplicated input)
typed = re.findall(r"typed: '([^']+)'", runner)
for cmd in set(typed):
    echoed = len(re.findall(r'\$ ' + re.escape(cmd) + r'\s*\n', con))
    if echoed != typed.count(cmd): bad(f'command {cmd!r} typed {typed.count(cmd)}x but echoed {echoed}x (duplicated or lost console input)')
# ---- 4. per-command semantics
def seg(cmd):
    m = re.search(r'\$ ' + re.escape(cmd) + r'\s*\n(.*?)(?=\n\$ |\Z)', con, re.S)
    return m.group(1) if m else None
s = seg('m3par')
if s is not None:
    c0 = re.findall(r'M3-PAR-CHILD0 checksum=([0-9a-f]+) harts=0x([0-9a-f]+)', s); c1 = re.findall(r'M3-PAR-CHILD1 checksum=([0-9a-f]+) harts=0x([0-9a-f]+)', s)
    done = s.find('M3-PAR-DONE')
    if len(c0) != 1 or len(c1) != 1: bad(f'm3par: child reports {len(c0)}/{len(c1)}, expected exactly one each')
    else:
        if c0[0][0] != 'f6d983767e3c5638' or c1[0][0] != '01d86a21f972f3fa': bad(f'm3par: checksums {c0[0][0]} {c1[0][0]} wrong')
        if done < 0 or done < max(s.find('M3-PAR-CHILD0'), s.find('M3-PAR-CHILD1')): bad('m3par: the parent reported before both children did')
        mask = int(c0[0][1], 16) | int(c1[0][1], 16)
        if not a.n1 and mask != 3: bad(f'm3par: the two children together ran on harts 0x{mask:x}, not on both')
        print(f'INFO m3par: children on harts 0x{int(c0[0][1],16):x} and 0x{int(c1[0][1],16):x}')
s = seg('m3migrate')
if s is not None:
    m = re.search(r'M3-MIGRATE-DONE harts=0x([0-9a-f]+) natural=(\d) pinned_ok=(\d) exec_ok=(\d)', s)
    if not m: bad('m3migrate: no DONE line')
    else:
        harts, natural, pinned, execok = int(m.group(1), 16), m.group(2), m.group(3), m.group(4)
        if not a.n1:
            if harts != 3: bad(f'm3migrate: the process ran on harts 0x{harts:x} only (no migration, natural or pinned)')
            if pinned != '1': bad('m3migrate: the controlled migration (pin to the other hart) was not observed by getcpu()')
        else:
            if harts != 1: bad(f'm3migrate: single-core run reports harts 0x{harts:x}')
            if pinned != '0': bad('m3migrate: pin() must be refused on a single-core build')
        if execok != '1': bad('m3migrate: the exec after migration did not complete')
        if s.find('M3-EXEC-AFTER-MIGRATE') < 0 or s.find('M3-EXEC-AFTER-MIGRATE') > s.find('M3-MIGRATE-DONE'): bad('m3migrate: the exec\'d child\'s output is missing or after the parent\'s report')
        print(f'INFO m3migrate: harts 0x{harts:x} natural={natural} pinned_ok={pinned} exec_ok={execok}')
s = seg('m3fs')
if s is not None:
    ch = re.findall(r'M3-FS-CHILD([01]) ok=(\d)', s); done = s.find('M3-FS-DONE')
    if sorted(c for c, _ in ch) != ['0', '1'] or any(o != '1' for _, o in ch): bad(f'm3fs: child reports {ch}')
    elif done < max(s.find('M3-FS-CHILD0'), s.find('M3-FS-CHILD1')): bad('m3fs: the parent reported before both children')
print(('PASS' if not fails else 'FAIL') + f' {D} harts={H}')
for f in fails: print('  FAIL:', f)
sys.exit(1 if fails else 0)
