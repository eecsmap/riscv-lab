#!/usr/bin/env python3
"""PIPE-P1: the run verdict. Reads the section summaries a run-p1.sh run wrote and decides PASS or FAIL.
  p1verdict.py <run dir> [--nhz N] [--coverage FILE]      exit 0 = PASS, 1 = FAIL (every reason is printed)

FAIL on: an unexpected failure of a positive test, missing or extra output, an uncaught negative control,
a changed shared source, or a missing coverage counter. The expected results of the negative controls (D, E) are what
PASS requires. The ONLY tolerated positive-test failures are the named baseline exceptions below, each with its exact
recorded result; a different failure of the same program, or the exception unexpectedly passing, is a FAIL."""
import sys, re, os

A_PROGRAMS = ("t01_alu t02_branch t03_ldst t04_trap t05_roi t01n_x0check c05_mret_count c06_targets c07_handler_fault "
              "c08_accessfault c09_ecall_ebreak d01_highpa d02_misaligned d03_badbranch d04_illegal "
              + " ".join("d05_jalr_f%d" % n for n in range(1, 8)) +
              " d06_loadpayload d07_csr_cycle d08_minstret_ok p1_misa-PIPE-ONLY").split()
A_EXCEPTIONS = {   # (program, implementation) -> the exact recorded status and why it is not a P1 regression
    ("c06_targets", "m"): ("FAIL(exit 3, want 0)", "multicycle baseline at tag mc-v1-dual; the pipeline passes"),
    ("d07_csr_cycle", "m"): ("FAIL(exit 38, want 0)", "stale M2-1 expectation (cycle counter), fails on both"),
    ("d07_csr_cycle", "p"): ("FAIL(exit 38, want 0)", "stale M2-1 expectation (cycle counter), fails on both"),
    ("p1_misa-PIPE-ONLY", "m"): ("FAIL(exit 1, want 0)", "misa differs by design; the program is pipeline-only"),
}
PROFILES = 5
B_FIXED = 11 + 8          # the completing existing programs + the P1 directed programs; hazard programs are --nhz
C_CASES = {"p1_irq_basic": 5, "p1_irq_masked": 3, "p1_irq_fault": 8, "p1_irq_hold": 2, "p1_irq_empty": 9,
           "p1_irq_warm": 6, "p1_irq_cancel": 8}       # raise positions per program; each on 3 profiles
D_KNOBS = 12; D_CONTROLS = 4; E_CASES = 5; G_FILES = 13; F_BLOCKS = 4; F_ROIS = 5
COVERAGE_KEYS = ("redirects redirect_while_held killed_fetch_responses killed_after_two_flushes flush_with_pending_valid "
                 "irq_tokens irq_synthetic irq_synthetic_fetch_ahead irq_cancelled drain_wait_cycles loaduse_stall_cycles "
                 "fwd_exmem fwd_memwb wb_bypass uncached_wait_cycles").split()

args = sys.argv[1:]; run = args.pop(0); nhz = 40; cov = None
while args:
    a = args.pop(0)
    if a == "--nhz": nhz = int(args.pop(0))
    elif a == "--coverage": cov = args.pop(0)
    else: sys.exit("unknown argument " + a)
cov = cov or os.path.join(run, "coverage.txt")
bad = []; notes = []
def read(name, in_run=True):   # in_run: a summary name inside the run dir; otherwise a path as given
    p = os.path.join(run, name) if in_run else name
    try: return open(p, errors="replace").read().splitlines()
    except OSError: bad.append("missing output: " + p); return []

# ---- A
seen = {}
for l in read("A.txt"):
    m = re.match(r"  (\S+)\s+m: (.*?)\s+p: (.*?)\s*$", l)
    if not m: continue
    prog, st = m.group(1), {"m": m.group(2).strip(), "p": m.group(3).strip()}
    if prog in seen: bad.append(f"A: {prog} reported twice")
    seen[prog] = st
    for impl in "mp":
        exc = A_EXCEPTIONS.get((prog, impl))
        if exc:
            if st[impl] != exc[0]: bad.append(f"A: {prog} {impl}: '{st[impl]}', the baseline exception is exactly '{exc[0]}'")
            else: notes.append(f"A: {prog} {impl}: {exc[0]} -- baseline exception ({exc[1]})")
        elif st[impl] != "PASS": bad.append(f"A: {prog} {impl}: {st[impl]}")
for p in A_PROGRAMS:
    if p not in seen: bad.append(f"A: {p}: no result")
for p in seen:
    if p not in A_PROGRAMS: bad.append(f"A: {p}: not in the test plan")

# ---- B
nb = PROFILES * (B_FIXED + nhz)
res = [l for l in read("B/results.txt") if l.strip()]
ok = [l for l in res if re.match(r"\S+ \S+ DIFF_OK exit=0 retired=[1-9]\d* dreq=\d+$", l)]
if len(res) != nb: bad.append(f"B: {len(res)} comparisons recorded, the plan has {nb}")
for l in res:
    if l not in ok: bad.append("B: " + l)
if len({tuple(l.split()[:2]) for l in res}) != len(res): bad.append("B: a (profile, program) pair is recorded twice")
tot = [l for l in read("B.txt") if "B total:" in l]
if not tot or not re.search(rf"B total: {nb} DIFF_OK, 0 DIFF_FAIL\b", tot[0]): bad.append(f"B: total line is not '{nb} DIFF_OK, 0 DIFF_FAIL': {tot}")

# ---- C
nc = 3 * sum(C_CASES.values())
cl = [l for l in read("C.txt") if re.match(r"  p1_irq_\w+ N=\d+ \w+:", l)]
if len(cl) != nc: bad.append(f"C: {len(cl)} interrupt cases reported, the plan has {nc}")
for l in cl:
    prog = l.split()[0]
    if prog not in C_CASES: bad.append("C: not in the test plan: " + l.strip()); continue
    if ": PASS " not in l: bad.append("C: " + l.strip())
    elif "| aligned(" in l:
        if not re.search(r"\| aligned\(N'=\d+\): DIFF_OK exit=0 ", l): bad.append("C: " + l.strip())
    elif "| n/a" in l:
        if prog != "p1_irq_cancel": bad.append("C: only the cancel program may take no interrupt: " + l.strip())
    else: bad.append("C: " + l.strip())
for prog, k in C_CASES.items():
    got = sum(1 for l in cl if l.split()[0] == prog)
    if got != 3 * k: bad.append(f"C: {prog}: {got} cases, the plan has {3 * k}")
tot = [l for l in read("C.txt") if "C total:" in l]
if not tot or not re.search(rf"self-checks {nc} PASS / 0 FAIL; .* not aligned or different 0$", tot[0]): bad.append(f"C: total line: {tot}")

# ---- D
d = read("D.txt"); knobs = {}
for l in d:
    m = re.match(r"  knob (\d+) on (\S+): (.*)$", l)
    if m: knobs.setdefault(int(m.group(1)), []).append(m.group(3))
for k in range(1, D_KNOBS + 1):
    r = knobs.get(k)
    if not r: bad.append(f"D: knob {k}: no result")
    elif len(r) > 1: bad.append(f"D: knob {k}: reported {len(r)} times")
    elif not r[0].startswith("CAUGHT"): bad.append(f"D: knob {k} NOT caught: {r[0]}")
for k in knobs:
    if not 1 <= k <= D_KNOBS: bad.append(f"D: knob {k} is not in the plan")
ctl = [l for l in d if l.startswith("  control knob")]
if len(ctl) != D_CONTROLS: bad.append(f"D: {len(ctl)} controls, the plan has {D_CONTROLS}")
for l in ctl:
    if not l.endswith(": exit 0, errors 0"): bad.append("D: control failed: " + l.strip())

# ---- E
el = [l for l in read("E.txt") if re.match(r"  p-\S+ on \S+: exit", l)]
if len(el) != E_CASES: bad.append(f"E: {len(el)} cases, the plan has {E_CASES}")
for l in el:
    if "-> caught: " not in l: bad.append("E: " + l.strip())

# ---- F (performance is reported, not judged; its output must be complete)
f = read("F.txt"); blocks = [l for l in f if re.match(r"  [mp] \((min|fixed)\):$", l)]
rois = [l for l in f if re.match(r"    ROI\d retired=[1-9]\d* cycles=[1-9]\d* CPI=\d+\.\d+ ", l)]
if len(blocks) != F_BLOCKS or len(rois) != F_BLOCKS * F_ROIS: bad.append(f"F: {len(blocks)} blocks / {len(rois)} ROI lines, the plan has {F_BLOCKS} / {F_BLOCKS * F_ROIS}")

# ---- G
g = read("G.txt")
un = [l for l in g if l.startswith("  unchanged ")]; ch = [l for l in g if "CHANGED" in l]
for l in ch: bad.append("G: " + l.strip())
if len(un) != G_FILES: bad.append(f"G: {len(un)} files unchanged, the plan has {G_FILES}")

# ---- coverage (every counter present and non-zero, each A/B/C pipeline log counted once)
cv = read(cov, in_run=False); na = sum(1 for p in A_PROGRAMS); ncv = na + nb + nc
if cv:
    m = re.match(r"== pipeline coverage summed over (\d+) runs \(A (\d+), B (\d+), C (\d+)\)", cv[0])
    if not m: bad.append("coverage: header is not the de-duplicated format: " + cv[0])
    elif tuple(map(int, m.groups())) != (ncv, na, nb, nc): bad.append(f"coverage: {m.group(0)}; the plan has {ncv} runs (A {na}, B {nb}, C {nc})")
    vals = dict(re.findall(r"  (\w+) = (\d+)", "\n".join(cv)))
    for k in COVERAGE_KEYS:
        if k not in vals: bad.append(f"coverage: {k} missing")
        elif int(vals[k]) == 0: bad.append(f"coverage: {k} = 0 (not exercised)")

for n in notes: print("  note  " + n)
for b in bad: print("  FAIL  " + b)
print(f"P1_VERDICT {'PASS' if not bad else 'FAIL'} ({len(bad)} failure reasons, {len(notes)} named baseline exceptions)")
sys.exit(1 if bad else 0)
