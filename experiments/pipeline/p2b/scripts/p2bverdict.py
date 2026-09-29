#!/usr/bin/env python3
"""PIPE-P2b run verdict. Reads the section summaries run-p2b.sh wrote.   p2bverdict.py <run dir>   exit 0 = PASS
Checkpoint 1 (privilege). The only tolerated failures are the named reference baseline of the CPU-SU suite
(M1 T1.4, "SU 9" = three programs x three profiles), and the pipeline must fail them identically."""
import sys, re, os
PROFILES = ["min", "fixed", "rnd12345"]
SU = ["su01_modes", "su02_csr_priv", "su03_deleg", "su04_strap", "su05_irq_modes", "su06_timer_ssip", "su07_epc_len",
      "su08_satp_bare", "su09_warl", "su10_wfi", "su11_mip_sw"]
SU_BASELINE = {"su08_satp_bare": "1", "su09_warl": "8", "su11_mip_sw": "24"}   # pre-Sv39 expectations on the tag core
SB = ["su01_modes", "su03_deleg", "su04_strap", "su07_epc_len", "su10_wfi", "su08_satp_bare", "su09_warl", "su11_mip_sw"]
SD = ["FAULT_NO_DELEG on {i}, su01", "FAULT_S_IRQ_IN_M on {i}, su05", "FAULT_SRET_SPP on {i}, su03"]
G_FILES = 13
SV = ["sv01_bare_sv39", "sv02_pages", "sv03_perms", "sv04_bad_pte", "sv05_straddle", "sv06_switch", "sv09_nonleaf"]
NSV = 20
VD_CAUGHT = ["knob 21 (TLB_NO_FLUSH) on sv06", "knob 22 (TLB_HIT_NO_PERM) on sv03", "knob 23 (DRAIN_NO_WALKER) on sv03",
             "FAULT_PPN_TRUNC on pmcs, sv04", "FAULT_PPN_TRUNC on m, sv04", "FAULT_IF2_NO_XLATE on m, sv05",
             "FAULT_PTW_NO_PERM on m, sv03"]
VD_CONTROLS = ["pmcs-fault21", "pmcs-fault22", "pmcs-fault23", "pmcs-noperm", "pmcs-if2", "pmcs-trunc", "m-noperm", "m-if2", "m-trunc"]
VE_NONZERO = ["fetch_walks", "data_walks", "walks_preempted_by_data", "walks_aborted", "pte_transactions_killed", "tlb_flushes"]
VC_MIN_DURING = 50
run = sys.argv[1]; bad = []; notes = []
def read(name):
    try: return open(os.path.join(run, name), errors="replace").read().splitlines()
    except OSError: bad.append("missing output: " + name); return []
# ---- SA
sa = read("SA.txt")
for t in SU:
    for p in PROFILES:
        l = [x for x in sa if x.startswith(f"  {t} {p}: ")]
        if len(l) != 1: bad.append(f"SA: {t} {p}: {len(l)} lines"); continue
        m = re.search(r"pipeline exit (\d+) errors (\d+) \| multicycle exit (\d+)$", l[0])
        if not m: bad.append("SA: " + l[0].strip()); continue
        pe, pr, me = m.groups(); want = SU_BASELINE.get(t, "0")
        if me != want: bad.append(f"SA: {t} {p}: reference exit {me}, its recorded baseline is {want}")
        if pe != me: bad.append(f"SA: {t} {p}: pipeline exit {pe}, reference {me}")
        if pr != "0": bad.append(f"SA: {t} {p}: {pr} pipeline errors")
        if want != "0" and pe == me: notes.append(f"SA: {t} {p}: exit {pe} on both cores -- named baseline")
# ---- SB
sb = read("SB.txt")
for t in SB:
    for p in PROFILES:
        l = [x for x in sb if x.startswith(f"  {t} {p} ")]
        if len(l) != 1: bad.append(f"SB: {t} {p}: {len(l)} lines"); continue
        strict = t not in SU_BASELINE
        if strict and not re.search(r"--require-complete: DIFF_OK exit=0 retired=[1-9]\d* ", l[0]): bad.append("SB: " + l[0].strip())
        if not strict and not re.search(r"\(baseline failure: equality only\): DIFF_OK exit=\d+ retired=[1-9]\d* ", l[0]): bad.append("SB: " + l[0].strip())
# ---- SC
sc = read("SC.txt")
cases = [x for x in sc if re.match(r"  p2b_irq_priv N=\d+ \w+:", x)]
m = [x for x in sc if "without an interrupt: exit 2 " in x]
if len(m) != 1: bad.append("SC: the interrupt-free run did not fail its interrupt check (exit 2)")
if len(cases) < 3 * 20: bad.append(f"SC: only {len(cases)} interrupt cases")
for x in cases:
    if not re.search(r": PASS k=\d+ interrupts=1 .*\| aligned\(N'=\d+\): DIFF_OK exit=0 ", x): bad.append("SC: " + x.strip())
# ---- SD
sd = read("SD.txt")
for impl in ("pmcs", "m"):
    for name in SD:
        n = name.format(i=impl); l = [x for x in sd if x.startswith(f"  {n}: ")]
        if len(l) != 1: bad.append(f"SD: {n}: {len(l)} lines")
        elif not l[0].split(": ", 1)[1].startswith("CAUGHT first signal:"): bad.append("SD: NOT caught: " + l[0].strip())
    for f in ("nodeleg", "sirqm", "sretspp"):
        l = [x for x in sd if x.startswith(f"  control {impl}-{f} on t01:")]
        if len(l) != 1 or not l[0].endswith(": exit 0, errors 0"): bad.append(f"SD: control {impl}-{f}: {l}")
# ---- VA
va = read("VA.txt")
for t in SV:
    for p in PROFILES:
        l = [x for x in va if x.startswith(f"  {t} {p}: ")]
        if len(l) != 1: bad.append(f"VA: {t} {p}: {len(l)} lines"); continue
        if not re.search(r"pipeline exit 0 errors 0 \| multicycle exit 0$", l[0]): bad.append("VA: " + l[0].strip())
for n, k in (("sv03", 7), ("sv09", 3)):
    l = [x for x in va if x.startswith(f"  {n} no-retire (pipeline):")]
    if len(l) != 1 or not re.search(rf"exit 0 {k} commit-count checks OK, 0 FAIL$", l[0]): bad.append(f"VA: {n} no-retire: {l}")
# ---- VB
vb = read("VB.txt")
for p in PROFILES:
    for t in SV + ["p2b_walk_preempt"] + [f"hzsv{i}" for i in range(1, NSV + 1)]:
        l = [x for x in vb if x.startswith(f"  {t} {p}: ")]
        if len(l) != 1: bad.append(f"VB: {t} {p}: {len(l)} lines"); continue
        if not re.search(r": DIFF_OK exit=0 retired=[1-9]\d* ", l[0]): bad.append("VB: " + l[0].strip())
# ---- VC
vc = read("VC.txt")
if not [x for x in vc if "without an interrupt: exit 2 " in x]: bad.append("VC: the interrupt-free run did not fail its interrupt check (exit 2)")
cases = [x for x in vc if x.startswith("  p2b_irq_walk cycle=")]
if len(cases) < 300: bad.append(f"VC: only {len(cases)} cycles swept")
for x in cases:
    if not re.search(r": PASS k=\d+ pte_outstanding_at_raise=[01] \| aligned\(N'=\d+\): DIFF_OK exit=0 ", x): bad.append("VC: " + x.strip())
m = [x for x in vc if x.startswith("  VC total:")]
d = re.search(r"raised while a PTE read was outstanding: (\d+)$", m[0]) if m else None
if not d or int(d.group(1)) < VC_MIN_DURING: bad.append(f"VC: too few raises with a PTE read outstanding: {m}")
# ---- VD
vd = read("VD.txt")
for name in VD_CAUGHT:
    l = [x for x in vd if x.startswith(f"  {name}: ")]
    if len(l) != 1: bad.append(f"VD: {name}: {len(l)} lines")
    elif not l[0].split(": ", 1)[1].startswith("CAUGHT first signal:"): bad.append("VD: NOT caught: " + l[0].strip())
l = [x for x in vd if x.startswith("  FAULT_IF2_NO_XLATE on pmcs, sv05, against the uninjected reference:")]
if len(l) != 1 or not re.search(r"DIFF_FAIL .*retirement stream differs at record \d+: multi=0x0*30002ffe ", l[0]):
    bad.append(f"VD: FAULT_IF2_NO_XLATE on the pipeline did not diverge first at the straddler 0x30002ffe: {l}")
l = [x for x in vd if x.startswith("  FAULT_PTW_NO_PERM on pmcs, sv03 (masked by construction")]
if len(l) != 1 or not l[0].endswith(": exit 0, errors 0"): bad.append(f"VD: FAULT_PTW_NO_PERM on the pipeline: {l}")
else: notes.append("VD: FAULT_PTW_NO_PERM on the pipeline: masked by construction (knob 22 is its counterpart)")
for sim in VD_CONTROLS:
    l = [x for x in vd if x.startswith(f"  control {sim} on t01:")]
    if len(l) != 1 or not l[0].endswith(": exit 0, errors 0"): bad.append(f"VD: control {sim}: {l}")
# ---- VE
ve = dict(re.findall(r"^  (\w+) = (\d+)$", "\n".join(read("VE.txt")), re.M))
for k in VE_NONZERO:
    if int(ve.get(k, "0")) == 0: bad.append(f"VE: {k} = {ve.get(k, 'missing')}")
# ---- G
g = read("G.txt")
for x in g:
    if "CHANGED" in x: bad.append("G: " + x.strip())
if len([x for x in g if x.startswith("  unchanged ")]) != G_FILES: bad.append(f"G: not {G_FILES} unchanged files")
for n in sorted(set(re.sub(r" (min|fixed|rnd12345):", ":", x) for x in notes)): print("  note  " + n)
for b in bad: print("  FAIL  " + b)
print(f"P2B_VERDICT {'PASS' if not bad else 'FAIL'} ({len(bad)} failure reasons, {len(notes)} named baseline results)")
sys.exit(1 if bad else 0)
