#!/usr/bin/env python3
"""MC-M1 T1.7: BEFORE against AFTER -- and each side against its own expectation.

Equality alone would pass two runs that fail identically (codex-mc-m1-verification-closeout, item 2).
So every program on BOTH sides must, on its own: exit 0; print ITS expected success marker
(probe_console.EXPECT, an explicit table); print no failure marker anywhere, even after the success
marker; report a completion cycle count. The set of programs must equal the expected set exactly --
nothing missing, nothing extra, never empty. In trace mode each run must carry non-empty COMMIT/TRAP
evidence; a missing trace is a rejection, not a downgrade. The inputs meant to be fixed are checked:
the same frozen programs by whole-file SHA and by load-semantic identity (elf_ident.py), the same cpu
RTL. Then, across the two sides: marker, exit, recovered console text, commit sequence must be equal,
and the cycle delta is reported -- never itself a failure.

  compare-probes.py <before-dir> <after-dir> --expect all|short|"p1 p2 ..." [--trace] [--write-summaries]
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_console as pc  # noqa: E402

HARNESS = re.compile(r'Completed after \d+ cycles|CYCLES total=\d+ host_done_at=\d+ drained=\d|AXI ar=\d+ r=\d+ rlast=\d+ aw=\d+ w=\d+ wlast=\d+ b=\d+|RD2HOST[^A-Z]*|TRACE_AGGREGATED[^ ]* lines=\d+ last_cycle=\d+ console_lines=\d+')


def read_list(d, name):
    p = os.path.join(d, name)
    return open(p).read() if os.path.exists(p) else None


def rtl_and_gen(d):
    rtl = gen = None
    p = os.path.join(d, 'sim', 'inputs.sha256')
    if os.path.exists(p):
        for ln in open(p):
            if 'tcpu_core.v' in ln: rtl = ln[:16]
            if 'RD2Harness.' in ln: gen = ln[:16]
    return rtl, gen


def main():
    args = sys.argv[1:]
    b, a = args[0], args[1]
    trace = '--trace' in args; write = '--write-summaries' in args
    exp = args[args.index('--expect') + 1] if '--expect' in args else 'all'
    expected = pc.ALL if exp == 'all' else pc.SHORT if exp == 'short' else exp.split()
    fails = []
    def fail(msg): fails.append(msg); print('  REJECT: ' + msg)

    # ---- the inputs that must be fixed ------------------------------------------------------------
    for name, what in (('elf.sha256', 'programs (whole-file sha256)'), ('elf-load.sha256', 'programs (load-semantic identity)')):
        xb, xa = read_list(b, name), read_list(a, name)
        if xb is None or xa is None: fail(f'{what}: {name} missing on a side')
        elif xb != xa: fail(f'{what}: differ between before and after')
        else: print(f'{what}: identical ({len(xb.splitlines())} files)')
    rb, ra = rtl_and_gen(b), rtl_and_gen(a)
    if rb[0] is None or rb[0] != ra[0]: fail(f'rtl: tcpu_core.v {rb[0]} vs {ra[0]}')
    else: print(f'rtl:      identical (tcpu_core.v {rb[0]})')
    print(f'generated: {rb[1]} (before) vs {ra[1]} (after) -- the one intended difference')

    # ---- the program set, exactly ------------------------------------------------------------------
    def progs(d):
        lb = None; out = {}
        for r in sorted(os.listdir(os.path.join(d, 'runs'))):
            lab, prog = r.split('-', 1); out[prog] = os.path.join(d, 'runs', r)
        return out
    pb, pa = progs(b), progs(a)
    if not expected: fail('expected program set is empty')
    for side, ps in (('before', pb), ('after', pa)):
        missing = sorted(set(expected) - set(ps)); extra = sorted(set(ps) - set(expected))
        if missing: fail(f'{side}: missing programs {missing}')
        if extra: fail(f'{side}: extra programs {extra}')
    print(f'program set: {len(expected)} expected, before has {len(pb)}, after has {len(pa)}')

    # ---- each side on its own, then across --------------------------------------------------------
    print(f"{'program':16s} {'marker':26s} {'before':8s} {'after':8s} {'console':8s} {'commits':16s} cycles")
    summ = {b: [], a: []}
    for prog in expected:
        if prog not in pb or prog not in pa: continue
        fb, fa = pc.facts(pb[prog], prog), pc.facts(pa[prog], prog)
        summ[b].append(fb); summ[a].append(fa)
        for side, f in (('before', fb), ('after', fa)):
            if not f['ok']: fail(f'{prog} {side}: {f["reason"]}')
            if trace and not f['commits']: fail(f'{prog} {side}: tracing run without COMMIT/TRAP evidence')
        tb, ta = HARNESS.sub('', pc.recover(pb[prog]) or ''), HARNESS.sub('', pc.recover(pa[prog]) or '')
        co = 'same' if tb == ta else 'DIFF'
        if co == 'DIFF': fail(f'{prog}: recovered console differs')
        if trace:
            cb = open(os.path.join(pb[prog], 'commits.txt')).read().splitlines() if fb['commits'] else []
            ca = open(os.path.join(pa[prog], 'commits.txt')).read().splitlines() if fa['commits'] else []
            d = sum(1 for x, y in zip(cb, ca) if x != y) + abs(len(cb) - len(ca))
            cm = f'{len(cb)}/{len(ca)} d={d}'
            if d: fail(f'{prog}: COMMIT/TRAP sequences differ ({d} lines)')
        else: cm = '(untraced)'
        cy = f"{fb['cycles']}->{fa['cycles']}"
        if fb['cycles'] is not None and fa['cycles'] is not None: cy += f" (d={fa['cycles'] - fb['cycles']:+d})"
        print(f"{prog:16s} {fb['expect']:26s} {'ok' if fb['ok'] else 'FAIL':8s} {'ok' if fa['ok'] else 'FAIL':8s} {co:8s} {cm:16s} {cy}")
    if write:
        for d, rows in summ.items():
            with open(os.path.join(d, 'summary-recovered.txt'), 'w') as fh:
                for f in rows: fh.write(f"prog={f['prog']} ok={int(f['ok'])} exit={f['exit']} marker={f['expect'] if f['ok'] else 'FAIL'} cycles={f['cycles']} commits={f['commits']} reason={f['reason']}\n")
    print(f'COMPARE fails={len(fails)}  (cycle deltas are reported, not judged)')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
