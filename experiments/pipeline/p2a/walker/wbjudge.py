#!/usr/bin/env python3
"""PIPE-P2a walker-wrapper judge. Reads a run-wb.sh output directory and decides each variant against its expectation.
  wbjudge.py <run-wb out dir> <name>=<expectation>...      exit 0 = every variant met its expectation

  clean          no WB ERROR in any run of any profile; every profile reports its runs; the reference walks equal the
                 values derived by hand from the page tables in wb_tb.v; every abort class was hit (summed over the
                 24 profiles)
  caught:<prop>  every profile has failing runs, and in EVERY failing run the first failing property is <prop>
                 (its consequences may follow)
The shared walker sources the bench compiled must be byte-identical to tag mc-v1-dual (shared.txt)."""
import sys, re, os, collections
PROFILES = [(gm, rd, rs) for gm in (0, 1) for rd in range(3) for rs in range(1, 5)]
CLASSES = ["idle", "req", "unforwarded", "forwardable", "offered", "handshake", "outstanding",
           "resp_l2", "resp_l1", "resp_l0", "error"]
# derived by hand from wb_tb.v's tables: s1 4 KiB page 0x8001_0000 + 0xabc; s2 megapage 0x8020_0000 + 0x0123;
# s3 invalid PTE -> fetch page fault 12; s4 table at 0x9000_0000 (no memory) -> fetch access fault 1; s5 0x8002_0000 + 0x010
REF = "s1 pa=00000080010abc | s2 pa=00000080200123 | s3 fault cause=12 | s4 fault cause=1 | s5 pa=00000080020010"
out = sys.argv[1]; exp = dict(a.split("=", 1) for a in sys.argv[2:])
bad_all = []
sh = open(os.path.join(out, "shared.txt")).read().splitlines() if os.path.exists(os.path.join(out, "shared.txt")) else []
if len([l for l in sh if l.startswith("unchanged ")]) != 3 or any("CHANGED" in l for l in sh):
    bad_all.append(f"shared walker sources not all unchanged: {sh}")
print(f"== walker-wrapper bench: {out}")
for name, want in exp.items():
    bad = []; cov = collections.Counter(); runs = 0; fail_runs = 0; firsts = collections.Counter(); props = collections.Counter()
    prop = want.split(":", 1)[1] if want.startswith("caught:") else None
    for gm, rd, rs in PROFILES:
        f = os.path.join(out, name, f"gm{gm}-rd{rd}-rs{rs}.log")
        if not os.path.exists(f): bad.append(f"missing {f}"); continue
        txt = open(f, errors="replace").read()
        m = re.search(r"^WB TOTAL runs=(\d+) errors=(\d+)$", txt, re.M)
        if not m: bad.append(f"gm{gm}-rd{rd}-rs{rs}: no WB TOTAL line"); continue
        runs += int(m.group(1))
        r = re.search(r"^WB REF rd=\d+ rs=\d+ (.*)$", txt, re.M)
        if not r or r.group(1) != REF: bad.append(f"gm{gm}-rd{rd}-rs{rs}: reference walks differ: {r.group(1) if r else None}")
        c = re.search(r"^WB COVER wf=\d+ gm=\d+ rd=\d+ rs=\d+ (.*)$", txt, re.M)
        if not c: bad.append(f"gm{gm}-rd{rd}-rs{rs}: no WB COVER line")
        else:
            for k, v in re.findall(r"(\w+)=(\d+)", c.group(1)): cov[k] += int(v)
        first = {}; profile_fail = 0
        for s, t, p in re.findall(r"^WB ERROR s=(\d+) rd=\d+ rs=\d+ t=(-?\d+) cyc=\d+ ([\w-]+):", txt, re.M):
            props[p] += 1
            if (s, t) not in first: first[(s, t)] = p
        for key, p in first.items():
            fail_runs += 1; profile_fail += 1; firsts[p] += 1
        if prop is not None and profile_fail == 0: bad.append(f"gm{gm}-rd{rd}-rs{rs}: no failing run")
    summary = f"{runs} runs over {len(PROFILES)} profiles; failing runs {fail_runs}; first properties {dict(firsts)}; all properties {dict(props)}"
    if want == "clean":
        if fail_runs: bad.append(f"{fail_runs} failing runs")
        for k in CLASSES:
            if cov[k] == 0: bad.append(f"abort class '{k}' never hit")
        summary += f"; abort classes {dict((k, cov[k]) for k in CLASSES)}"
    elif prop is not None:
        if fail_runs == 0: bad.append("NOT CAUGHT")
        other = {p: n for p, n in firsts.items() if p != prop}
        if other: bad.append(f"runs whose first failure is not {prop}: {other}")
    else: bad.append(f"unknown expectation {want}")
    print(f"  {name} ({want}): {'PASS' if not bad else 'FAIL'}; {summary}")
    for b in bad: print(f"    FAIL {name}: {b}")
    bad_all += bad
if any(b.startswith("shared") for b in bad_all): print(f"    FAIL {bad_all[0]}")
print(f"WB_JUDGE {'PASS' if not bad_all else 'FAIL'}")
sys.exit(1 if bad_all else 0)
