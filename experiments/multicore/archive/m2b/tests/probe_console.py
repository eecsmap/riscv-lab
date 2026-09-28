#!/usr/bin/env python3
"""The ONE place that reads an RD2 probe run: console recovery, marker, cycles, exit, trace evidence.

Both the runner (rd2-probes.sh) and the comparator (compare-probes.py) import this, so there is no
second reading of the same evidence to drift (codex-mc-m1-verification-closeout, item 1).

Why recovery is needed: the RD2 harness interleaves the probe's HTIF characters with its own `AT`,
`RD2`, `RBOOT`, `EV*` lines; the aggregator keeps every non-`EV` line as "console", so in a tracing
configuration a marker's letters are separated by trace text. Recovery strips the trace-line text from
each line and joins what is left -- the method cpu-a/scripts/run-soc-a.sh uses.

The expected success marker per program is a TABLE here, explicit and complete; a run is judged against
the program's own marker, never against "any -OK".

  probe_console.py <rundir> [--json]      prints the facts for one run
"""
import json, os, re, sys

TRACE = re.compile(r'((AT|RD2|EV|EVA|EVH|RD2HOST|RBOOT)\s+\d+\s+\S.*)$')
# PASS / FAIL as whole words: recovery joins split characters without separators, so `\b` alone would
# fail against the harness line that follows -- the recovered text puts that line on its own line below
MARK = re.compile(r'TEACHING-[A-Z0-9-]+-(?:OK|FAIL)|M3-[A-Z0-9-]+-(?:OK|FAIL)|(?<![A-Za-z0-9_-])PASS(?![A-Za-z0-9_-])|(?<![A-Za-z0-9_-])FAIL(?![A-Za-z0-9_-])')
CYCLES = re.compile(r'Completed after (\d+) cycles')

# program -> the marker that program prints on success (from its source); anything ending in -FAIL, or a
# bare FAIL, printed anywhere is a failure even if the success marker also appears
EXPECT = {
    'boot01_marker': 'TEACHING-CPU-M3-OK', 'boot02_clint': 'M3-CLINT-OK', 'boot03_ddr': 'M3-DDR-OK',
    'boot04_badaddr': 'M3-BADADDR-OK',
    'ext01_m': 'TEACHING-EXT-M-OK', 'ext02_c': 'TEACHING-EXT-C-OK', 'ext03_a': 'TEACHING-EXT-A-OK',
    'ext04_sv39': 'TEACHING-EXT-SV39-OK',
    'boot11_sv39': 'M3-SV39-OK', 'boot12_amo': 'M3-AMO-OK', 'hello': 'PASS',
    'perf02_sv39': 'TEACHING-PERF-SV39-OK', 'perf03_fetch': 'TEACHING-PERF-FETCH-OK',
    'perf04_where': 'TEACHING-PERF-WHERE-OK', 'perf06_iws': 'TEACHING-PERF-IWS-OK',
    'tlb01_sfence': 'TEACHING-TLB-SFENCE-OK', 'tlb02_canonical': 'TEACHING-TLB-CANON-OK',
    'cache01_smc': 'TEACHING-CACHE-SMC-OK',
}
SHORT = ['boot01_marker', 'boot02_clint', 'boot03_ddr', 'boot04_badaddr', 'ext01_m', 'ext02_c', 'ext04_sv39',
         'boot11_sv39', 'boot12_amo', 'hello', 'tlb01_sfence', 'tlb02_canonical', 'cache01_smc']
ALL = sorted(EXPECT)


def recover(rundir):
    p = os.path.join(rundir, 'console.txt')
    if not os.path.exists(p): return None
    raw = open(p, errors='replace').read().splitlines()
    # Line-aware join: a line that carried trace text is a FRAGMENT of the probe's output (the aggregator
    # kept only what preceded the trace), so its remainder joins the next without a separator; a line with
    # no trace text is a whole console line and keeps its newline. Joining everything blindly glued
    # adjacent markers into one token (found by checker-selftest case 5).
    parts = []
    for ln in raw:
        rest = TRACE.sub('', ln)
        parts.append(rest if rest != ln else ln + '\n')
    text = ''.join(parts)
    # the harness's own lines are printed after a flush, on their own line; a fragment before them may have
    # lost its newline, so restore that boundary before matching whole-word markers
    return re.sub(r'(?<!\n)(Completed after \d+ cycles|CYCLES total=|AXI ar=|RD2HOST |TRACE_AGGREGATED)', r'\n\1', text)


def facts(rundir, prog):
    """Everything a verdict needs, plus the verdict itself and its reason."""
    text = recover(rundir)
    f = dict(prog=prog, expect=EXPECT.get(prog))
    try: f['exit'] = int(open(os.path.join(rundir, 'exit')).read().strip())
    except (OSError, ValueError): f['exit'] = None
    f['markers'] = MARK.findall(text) if text is not None else []
    m = CYCLES.findall(text) if text is not None else []
    f['cycles'] = int(m[0]) if m else None
    cp = os.path.join(rundir, 'commits.txt')
    f['commits'] = sum(1 for _ in open(cp)) if os.path.exists(cp) else None
    # the verdict: explicit, in this order, first failure names the reason
    reasons = []
    if text is None: reasons.append('no console.txt')
    if f['expect'] is None: reasons.append(f'no expected marker known for {prog}')
    if f['exit'] != 0: reasons.append(f"exit={f['exit']} (0 required)")
    if f['expect'] and f['expect'] not in f['markers']: reasons.append(f"expected marker {f['expect']} absent")
    bad = [x for x in f['markers'] if x.endswith('-FAIL') or x == 'FAIL']
    if bad: reasons.append(f'failure marker present: {bad[0]}')
    if f['cycles'] is None: reasons.append('no completion cycle count')
    f['ok'] = not reasons
    f['reason'] = '; '.join(reasons) if reasons else 'ok'
    return f


def main():
    d = sys.argv[1]; prog = os.path.basename(d.rstrip('/')).split('-', 1)[1]
    f = facts(d, prog)
    if '--json' in sys.argv: print(json.dumps(f)); return
    print(f"prog={f['prog']} ok={int(f['ok'])} exit={f['exit']} marker={f['expect'] if f['ok'] else (f['markers'][0] if f['markers'] else 'none')} "
          f"cycles={f['cycles']} commits={f['commits']} reason={f['reason']}")
    sys.exit(0 if f['ok'] else 1)


if __name__ == '__main__':
    main()
