#!/usr/bin/env python3
"""MC-PERF judge for one run directory (<out>/run made by board-runner.py, <out>/runner.log, <out>/verdict.txt).

Refuses (each one is a mutation in perf-check-selftest.sh):
  * the runner did not exit 0 / did not stop deliberately / the production check-xv6 --require-commands fails
  * a PERF-* summary with ok=0, children != 4, or a child line MISSING / absent / duplicated
  * a child checksum that differs from the value this judge recomputes in Python for (benchmark, child, size)
  * a timed region shorter than --min-dmtime mtime units (default 2,000,000 = 5 s at 400 kHz); dmtime != mt1-mt0; mt1 < mt0
  * the mtimetest smoke: reads not monotonic, the child's read outside [p0, p1] (not one shared time base), or ticks*25000 > dmtime+25000
    (the kernel tick can only under-count elapsed mtime; a tick count that exceeds the hardware delta means the two disagree)
  * a perf run whose dmtime/25000 < ticks - 1 (same under-count-only rule, per run)
  Time base: the CLINT mtime = core clock / 100 (400 kHz at 40 MHz); --mtime-hz converts to seconds. The kernel tick is diagnostic only.
  * a benchmark whose size is not the expected one for the profile (--sizes compute=N,array=M)
Prints one RESULT line per benchmark run: ticks, and (if --tick-ms is given) seconds and work/s.
"""
import sys, os, re, argparse, subprocess
ap = argparse.ArgumentParser(); ap.add_argument('outdir'); ap.add_argument('--min-dmtime', type=int, default=2000000, help='minimum timed region in mtime units (2,000,000 = 5 s at 400 kHz)')
ap.add_argument('--sizes', default='compute=2000000,array=128'); ap.add_argument('--mtime-hz', type=float, default=400000.0, help='mtime rate: core clock / 100 (400 kHz at 40 MHz; set to 0 to print raw units only)')
ap.add_argument('--no-mtimetest', action='store_true', help='the profile has no mtimetest command')
ap.add_argument('--n1', action='store_true', help='(informational) single-core run')
a = ap.parse_args(); D = a.outdir; RUN = os.path.join(D, 'run'); HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.join(HERE, '..', 'tools', 'xv6-boot', 'scripts', 'check-xv6.py')
M64 = (1 << 64) - 1
def compute_ref(idx, size):
    x = idx + 1
    for _ in range(size): x = (x * 6364136223846793005 + 1442695040888963407) & M64; x ^= x >> 29
    return x
def array_ref(idx, passes, N=16384, STRIDE=7):
    a_ = [((i * 2654435761) + idx) & M64 for i in range(N)]; s = 0; j = 0
    for _ in range(passes):
        for _ in range(N):
            s = (s + a_[j]) & M64; a_[j] ^= s >> 3; j = (j + STRIDE) % N
    return s
sizes = dict(kv.split('=') for kv in a.sizes.split(',')); want = {'PERF-COMPUTE': int(sizes['compute']), 'PERF-ARRAY': int(sizes['array'])}
fails = []; bad = fails.append
def rd(p): return open(p, errors='replace').read() if os.path.exists(p) else ''
con = rd(os.path.join(RUN, 'console.txt')).replace('\r', ''); runner = rd(os.path.join(D, 'runner.log')); verdict = rd(os.path.join(D, 'verdict.txt'))
if not con: print('FAIL no console'); sys.exit(1)
m = re.search(r'XV6_RC=(\d+)', verdict)
if not m or m.group(1) != '0': bad(f'runner exit: {verdict.strip() or "<none>"}')
r = subprocess.run([sys.executable, CHECK, RUN, '--require-commands'], capture_output=True, text=True)
if r.returncode != 0: bad('check-xv6.py: ' + (r.stdout + r.stderr).strip().replace('\n', ' | ')[:300])
stop = re.search(r'# stop: (\S+)', rd(os.path.join(RUN, 'stages.txt')))
if not stop or stop.group(1) != 'deliberate-stop-after-all-commands': bad(f'run did not end deliberately: {stop.group(1) if stop else "<none>"}')
if re.search(r'panic:', con): bad('kernel panic')
segs = re.findall(r'\$ (perf\w+(?: \d+)?)\s*\n(.*?)(?=\n\$ |\Z)', con, re.S)
if not segs: bad('no perf command segments')
cache = {}
results = []
last_mt = []
for cmd, s in segs:
    hdr = re.findall(r'^(PERF-COMPUTE|PERF-ARRAY) size=(\d+) children=(\d+) mt0=(\d+) mt1=(\d+) dmtime=(\d+) readcost=(\d+) ticks=(\d+) ok=(\d)$', s, re.M)
    if len(hdr) != 1: bad(f'{cmd}: {len(hdr)} summary lines'); continue
    tag, size, ch, mt0, mt1, dm, rc_, ticks, ok = hdr[0]; size, ch, mt0, mt1, dm, rc_, ticks = int(size), int(ch), int(mt0), int(mt1), int(dm), int(rc_), int(ticks)
    if ok != '1': bad(f'{cmd}: ok={ok}')
    if ch != 4: bad(f'{cmd}: children={ch}, expected 4')
    if size != want[tag]: bad(f'{cmd}: size={size}, expected {want[tag]} for this profile')
    if mt1 < mt0: bad(f'{cmd}: mtime went backwards: mt0={mt0} mt1={mt1}')
    if mt1 - mt0 != dm: bad(f'{cmd}: dmtime {dm} inconsistent with mt0={mt0} mt1={mt1}')
    if dm < a.min_dmtime: bad(f'{cmd}: timed region only {dm} mtime units < {a.min_dmtime}: too short')
    if ticks > dm // 25000 + 1: bad(f'{cmd}: kernel ticks {ticks} exceed the hardware delta ({dm} mtime = {dm // 25000} tick intervals): the two time bases disagree')
    if rc_ > 100000: bad(f'{cmd}: one mtime() read cost {rc_} mtime units: not negligible')
    last_mt.append((cmd, mt0, mt1))
    if 'PERF-DONE ok=1' not in s: bad(f'{cmd}: no PERF-DONE ok=1')
    kids = re.findall(rf'^{tag}-CHILD(\d) checksum=([0-9a-fA-F]+|MISSING)$', s, re.M)
    if sorted(k for k, _ in kids) != ['0', '1', '2', '3']: bad(f'{cmd}: child lines {sorted(k for k,_ in kids)}, expected 0..3 exactly once'); continue
    for k, v in kids:
        if v == 'MISSING': bad(f'{cmd}: child {k} result missing'); continue
        key = (tag, int(k), size)
        if key not in cache: cache[key] = compute_ref(int(k), size) if tag == 'PERF-COMPUTE' else array_ref(int(k), size)
        if int(v, 16) != cache[key]: bad(f'{cmd}: child {k} checksum {v} != expected {cache[key]:016x}')
    work = 4 * size * (1 if tag == 'PERF-COMPUTE' else 16384)   # element UPDATES (the per-child initialising pass is extra, not counted)
    line = f'RESULT {tag} size={size} dmtime={dm} readcost={rc_} ticks_diag={ticks}'
    if a.mtime_hz and dm > 0: sec = dm / a.mtime_hz; line += f' seconds={sec:.3f} work_per_s={work / sec:.0f}'   # dm == 0 is already refused above
    results.append(line)
# runs must be ordered in time: each run's mt0 >= the previous run's mt1 (one free-running shared counter)
for (c1, a0, a1), (c2, b0, b1) in zip(last_mt, last_mt[1:]):
    if b0 < a1: bad(f'{c2}: starts at mtime {b0}, before {c1} ended at {a1}: not one monotonic time base')
# the mtimetest smoke (monotonic reads, shared across processes/harts, ticks <= elapsed)
mt = re.search(r'\$ mtimetest\s*\n(.*?)(?=\n\$ |\Z)', con, re.S)
if mt is None:
    if not a.no_mtimetest: bad('no mtimetest segment')
else:
    seg_ = mt.group(1); reads = re.search(r'^MTIME-READS((?: \d+){8})$', seg_, re.M); sh = re.search(r'^MTIME-SHARED p0=(\d+) child=(\d+) p1=(\d+) ticks=(\d+) spin100k=(\d+) x=([0-9a-f]+)$', seg_, re.M)
    if not reads or not sh or 'MTIME-DONE ok=1' not in seg_: bad('mtimetest: lines missing or ok=0')
    else:
        v = [int(t) for t in reads.group(1).split()]
        if any(v[i] < v[i-1] for i in range(1, 8)): bad(f'mtimetest: reads not monotonic: {v}')
        p0, ch, p1, tk, spin = (int(sh.group(i)) for i in range(1, 6))
        if not (p0 <= ch <= p1): bad(f'mtimetest: child read {ch} outside the parent\'s [{p0}, {p1}]: not one shared time base')
        if tk > (p1 - p0) // 25000 + 1: bad(f'mtimetest: ticks {tk} exceed the mtime delta {p1 - p0}')
        if int(sh.group(6), 16) != compute_ref(0, 100000): bad('mtimetest: spin checksum wrong (the spin did not run as written)')
        print(f'INFO mtimetest: 8 reads monotonic, consecutive deltas {[v[i]-v[i-1] for i in range(1,8)]} mtime units; child {ch} within [{p0},{p1}]; spin100k={spin} mtime units ({spin*100} cycles, {spin*100/100000:.0f} cycles/iter)')
for l in results: print(l)
print(('PASS' if not fails else 'FAIL') + f' {D} ({len(segs)} perf runs)')
for f in fails: print('  FAIL:', f)
sys.exit(1 if fails else 0)
