#!/usr/bin/env python3
"""PIPE-P2a run verdict (M and C). Reads the section summaries run-p2a.sh wrote and decides PASS or FAIL.
  p2averdict.py <run dir> [--nhz N]          exit 0 = PASS, 1 = FAIL (every reason is printed)
FAIL on: a pipeline or reference self-check failure, the P1 configuration accepting M, a differential mismatch or a
missing comparison, an interrupt case failing or not aligning, an uncaught negative control or a failing control,
missing performance output, a changed shared source. There are no baseline exceptions in the M part."""
import sys, re, os
PROFILES = ["min", "fixed", "rnd12345", "rnd777", "rnd4242"]
B_FIXED = ["m01x", "p2a_md_hazard", "p2a_md_fault", "t01_alu"]
B_FIXED_C = ["m01x", "c01x", "c02", "p2a_c_link", "p2a_md_hazard", "p2a_md_fault", "t01_alu"]
C_POS = {"p2a_md_irq": list(range(8, 61, 2)), "p2a_c_irq": list(range(6, 71, 2))}; C_PROF = 3
D_LINES = ["knob 15 (MD_STALE_RESULT) on p2a_md_fault", "knob 16 (MD_RESTART) on p2a_md_hazard",
           "FAULT_W_SEXT on pm", "FAULT_MULH_SIGN on pm", "FAULT_W_SEXT on m", "FAULT_MULH_SIGN on m",
           "knob 17 (C_LINK_LEN) on p2a_c_link", "knob 18 (C_CARRY_DROP) on c02",
           "FAULT_C_IMM on pmc", "FAULT_C_REG on pmc", "FAULT_C_IMM on m", "FAULT_C_REG on m"]
# c02's 32-bit instruction at 0x80000ffe straddles 0x8000_1000: a fetch error on its first parcel reports mtval = the
# instruction, on its second parcel mtval = 0x80001000; knob 19 is caught when its mtval is the first parcel's instead
PARCEL = {"pmc-fe1": "0x80000ffe", "m-fe1": "0x80000ffe", "pmc-fe2": "0x80001000", "m-fe2": "0x80001000"}
D_CONTROLS = 8; F_BLOCKS = 4; F_ROIS = 3; G_FILES = 13
args = sys.argv[1:]; run = args.pop(0); nhz = 40
while args:
    a = args.pop(0)
    if a == "--nhz": nhz = int(args.pop(0))
    else: sys.exit("unknown argument " + a)
bad = []
def read(name):
    try: return open(os.path.join(run, name), errors="replace").read().splitlines()
    except OSError: bad.append("missing output: " + name); return []
# ---- A
a = read("A.txt")
for p in PROFILES:
    l = [x for x in a if x.startswith(f"  {p}: ")]
    if len(l) != 1: bad.append(f"A: {p}: {len(l)} result lines"); continue
    if not re.search(r"pipeline M exit 0 errors 0 \| multicycle exit 0 errors 0$", l[0]): bad.append("A: " + l[0].strip())
for p in PROFILES:
    l = [x for x in a if x.startswith(f"  C {p}: ")]
    if len(l) != 1: bad.append(f"A: C {p}: {len(l)} result lines"); continue
    if not re.search(r"pipeline M\+C m01c exit 0 c01 exit 0 c02 exit 0 errors 0 \| multicycle c01mc exit 0 c02 exit 0$", l[0]): bad.append("A: " + l[0].strip())
for sim in ("p1-min", "pm-min"):
    l = [x for x in a if x.startswith(f"  no-C build {sim} on c01:")]
    if len(l) != 1: bad.append(f"A: no-C build {sim}: {len(l)} lines"); continue
    m = re.search(r"exit [1-9]\d*; first trap: TRP cyc=\d+ irq=0 cause=0*(\d) epc=[0-9a-f]+ tval=([0-9a-f]+); instruction at epc: ([0-9a-f]+) \(\d+ hex digits\); compressed retired: 0$", l[0])
    ok = m and ((m.group(1) == "2" and len(m.group(3)) == 4) or (m.group(1) == "0" and int(m.group(2), 16) % 4 == 2))
    if not ok: bad.append("A: a build without C did not refuse C code: " + l[0].strip())
l = [x for x in a if x.startswith("  P1 configuration on m01:")]
if len(l) != 1: bad.append("A: no P1-configuration line")
else:
    m = re.search(r"exit (\d+); first trap: TRP cyc=\d+ irq=0 cause=0*2 epc=0*([0-9a-f]+) .*first M instruction at 0x0*([0-9a-f]+)$", l[0])
    if not m or m.group(1) == "0" or m.group(2) != m.group(3):
        bad.append("A: the P1 configuration did not refuse the first M instruction as illegal: " + l[0].strip())
# ---- B
nb = len(PROFILES) * (len(B_FIXED) + nhz)
res = [x for x in read("B/results.txt") if x.strip()]
if len(res) != nb: bad.append(f"B: {len(res)} comparisons, the plan has {nb}")
for x in res:
    if not re.match(r"\S+ \S+ DIFF_OK exit=0 retired=[1-9]\d* dreq=\d+$", x): bad.append("B: " + x)
if len({tuple(x.split()[:2]) for x in res}) != len(res): bad.append("B: a comparison is recorded twice")
nbc = len(PROFILES) * (len(B_FIXED_C) + nhz)
resc = [x for x in read("B/results-c.txt") if x.strip()]
if len(resc) != nbc: bad.append(f"B (M+C): {len(resc)} comparisons, the plan has {nbc}")
for x in resc:
    if not re.match(r"\S+ \S+ DIFF_OK exit=0 retired=[1-9]\d* dreq=\d+$", x): bad.append("B (M+C): " + x)
if len({tuple(x.split()[:2]) for x in resc}) != len(resc): bad.append("B (M+C): a comparison is recorded twice")
# ---- C
cfile = read("C.txt")
cl = []
for prog, pos in C_POS.items():
    mine = [x for x in cfile if re.match(rf"  {prog} N=\d+ \w+:", x)]
    if len(mine) != len(pos) * C_PROF: bad.append(f"C: {prog}: {len(mine)} cases, the plan has {len(pos) * C_PROF}")
    cl += mine
for x in cl:
    if not re.search(r": PASS k=\d+ interrupts=1 .*\| aligned\(N'=\d+\): DIFF_OK exit=0 ", x): bad.append("C: " + x.strip())
# ---- D
d = read("D.txt")
for name in D_LINES:
    l = [x for x in d if x.startswith(f"  {name}: ")]
    if len(l) != 1: bad.append(f"D: {name}: {len(l)} result lines")
    elif not l[0].split(": ", 1)[1].startswith("CAUGHT first signal:"): bad.append("D: NOT caught as intended: " + l[0].strip())
for sim, tval in list(PARCEL.items()) + [("pmc-fault19", None)]:
    l = [x for x in d if x.startswith(f"  parcel fault {sim} on c02:")]
    if len(l) != 1: bad.append(f"D: parcel fault {sim}: {len(l)} lines"); continue
    m = re.search(r"exit 4 TRAPS=1 last_cause=1 last_epc=0x80000ffe last_tval=(0x[0-9a-f]+) COMMIT COUNT OK errors 0$", l[0])
    if not m: bad.append("D: parcel fault: " + l[0].strip())
    elif tval is not None and m.group(1) != tval: bad.append(f"D: parcel fault {sim}: mtval {m.group(1)}, required {tval}")
    elif tval is None and m.group(1) == "0x80001000": bad.append("D: knob 19 (C_TVAL_FIRST) NOT caught: mtval is the second parcel's")
ctl = [x for x in d if x.startswith("  control ")]
if len(ctl) != D_CONTROLS: bad.append(f"D: {len(ctl)} controls, the plan has {D_CONTROLS}")
for x in ctl:
    if not x.endswith(": exit 0, errors 0"): bad.append("D: control failed: " + x.strip())
# ---- F
f = read("F.txt")
blocks = [x for x in f if re.match(r"  (m|pm) \((min|fixed)\):$", x)]
cblocks = [x for x in f if re.match(r"  C (m|pmc) \((min|fixed)\):$", x)]
if len(cblocks) != F_BLOCKS: bad.append(f"F: {len(cblocks)} C blocks, the plan has {F_BLOCKS}")
rois = [x for x in f if re.match(r"    ROI\d retired=[1-9]\d* cycles=[1-9]\d* CPI=\d+\.\d+ ", x)]
if len(blocks) != F_BLOCKS or len(rois) != 2 * F_BLOCKS * F_ROIS: bad.append(f"F: {len(blocks)} blocks / {len(rois)} ROI lines, the plan has {F_BLOCKS} / {2 * F_BLOCKS * F_ROIS}")
# ---- G
g = read("G.txt")
for x in g:
    if "CHANGED" in x: bad.append("G: " + x.strip())
if len([x for x in g if x.startswith("  unchanged ")]) != G_FILES: bad.append(f"G: not {G_FILES} unchanged files")
for b in bad: print("  FAIL  " + b)
print(f"P2A_VERDICT {'PASS' if not bad else 'FAIL'} ({len(bad)} failure reasons)")
sys.exit(1 if bad else 0)
