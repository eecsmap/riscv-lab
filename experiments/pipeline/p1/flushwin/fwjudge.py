#!/usr/bin/env python3
"""PIPE-P1 flush-window judge. Reads a run-fw.sh output directory and decides each variant against its expectation.
  fwjudge.py <run-fw out dir> <name>=<expectation>...      exit 0 = every variant met its expectation

Expectations:
  clean          no FW ERROR and no core assertion in any run; every run exits 0 with the reference checksum (ref.txt;
                 without it, one checksum across all runs); every window the variant can have was covered
  caught:<prop>  at least one run fails; in every failing run <prop> is the ONLY failing bench property and the core's
                 own 'PIPE ASSERT <prop>' fires too; every run still exits 0 with the reference checksum (the property
                 catches the defect, not the program's output)
  report         judged by nothing: counts are printed (the pre-fix core, kept as evidence)
"""
import sys, re, glob, os, collections

PROFILES = [(rd, rs) for rd in range(3) for rs in range(1, 6)]
WINDOWS = ["final", "first", "alloc", "offered", "handshake", "error"]
NEED = {True: WINDOWS, False: ["final", "alloc", "offered", "handshake"]}   # with / without the I-cache

out = sys.argv[1]; exp = dict(a.split("=", 1) for a in sys.argv[2:])
ref = None
if os.path.exists(os.path.join(out, "ref.txt")):
    m = re.search(r"REF exit=0 sum=([0-9a-f]{16}) TOHOST code=0 ", open(os.path.join(out, "ref.txt")).read())
    ref = m.group(1) if m else "INVALID"
bad_all = []
print(f"== flush-window bench: {out}; reference checksum (multicycle core): {ref}")
for name, want in exp.items():
    bad = []; cov = collections.Counter(); runs = 0; sums = set(); codes = collections.Counter()
    fail_runs = 0; props = collections.Counter(); asserts = collections.Counter(); icache = None; other_props = set(); lacking = []
    prop = want.split(":", 1)[1] if want.startswith("caught:") else None
    for rd, rs in PROFILES:
        f = os.path.join(out, name, f"rd{rd}-rs{rs}.log")
        if not os.path.exists(f): bad.append(f"missing {f}"); continue
        txt = open(f, errors="replace").read()
        if not re.search(r"^FW TOTAL runs=\d+ errors=\d+$", txt, re.M): bad.append(f"rd{rd}-rs{rs}: no FW TOTAL line"); continue
        m = re.search(r"^FW COVER icache=(\d+) pf=(\d+) .*?final=(\S+) first=(\S+) alloc=(\S+) offered=(\S+) handshake=(\S+) error=(\S+) ", txt, re.M)
        if not m: bad.append(f"rd{rd}-rs{rs}: no FW COVER line"); continue
        icache = int(m.group(1)) != 0
        for w, v in zip(WINDOWS, m.groups()[2:]): cov[w] += sum(int(x) for x in v.split("/"))
        # attribute each run's lines (errors and core assertions come before its FW RUN line)
        cur_err, cur_ast = set(), set()
        for line in txt.splitlines():
            e = re.match(r"FW ERROR pt=\d+ .*? cyc=\d+ ([\w-]+):", line)
            if e: cur_err.add(e.group(1)); continue
            a = re.match(r"PIPE ASSERT ([\w-]+)", line)
            if a: cur_ast.add(a.group(1)); continue
            r = re.match(r"FW RUN pt=(\d+) rd=\d+ rs=\d+ code=(\d+) cycles=\d+ irq_taken=\d+ sum=([0-9a-f]{16}) errors=(\d+)$", line)
            if r:
                runs += 1; codes[r.group(2)] += 1; sums.add(r.group(3))
                if cur_err or cur_ast:
                    fail_runs += 1
                    for p in cur_err: props[p] += 1
                    for p in cur_ast: asserts[p] += 1
                    if prop is not None:
                        extra = (cur_err - {prop})
                        if extra: other_props |= extra
                        if prop not in cur_err or prop not in cur_ast: lacking.append(f"pt={r.group(1)} rd={rd} rs={rs}")
                cur_err, cur_ast = set(), set()
    summary = (f"{runs} runs over {len(PROFILES)} profiles; failing runs {fail_runs}; bench properties {dict(props)}; "
               f"core assertions {dict(asserts)}; exit codes {dict(codes)}; checksums {sorted(sums)}; "
               f"windows {dict(cov)}")
    if want == "report":
        print(f"  {name} (report only): {summary}"); continue
    if runs == 0: bad.append("no runs")
    if set(codes) != {"0"}: bad.append(f"non-zero exit codes {dict(codes)}")
    if ref is not None and sums != {ref}: bad.append(f"checksums {sorted(sums)} differ from the reference {ref}")
    if ref is None and len(sums) != 1: bad.append(f"{len(sums)} different checksums")
    if want == "clean":
        if fail_runs: bad.append(f"{fail_runs} failing runs: {dict(props)} {dict(asserts)}")
        for w in NEED[bool(icache)]:
            if cov[w] == 0: bad.append(f"window '{w}' never covered")
    elif prop is not None:
        if fail_runs == 0: bad.append(f"NOT CAUGHT: no run fails")
        if other_props: bad.append(f"other properties fail too: {sorted(other_props)}")
        if lacking: bad.append(f"{len(lacking)} failing runs lack {prop} in the bench or in the core (first: {lacking[0]})")
    else: bad.append(f"unknown expectation {want}")
    print(f"  {name} ({want}): {'PASS' if not bad else 'FAIL'}; {summary}")
    for b in bad: print(f"    FAIL {name}: {b}")
    bad_all += bad
print(f"FW_JUDGE {'PASS' if not bad_all else 'FAIL'}")
sys.exit(1 if bad_all else 0)
