#!/usr/bin/env python3
"""PIPE-P2b guard self-test: can the verdict and the A judge FAIL?
  selftest-p2b.py <a passing run dir>          exit 0 = every mutant was refused for its own reason, the original passes
Verdict mutants: the run's section summaries are copied to a scratch directory, ONE line is altered the way a real
failure would alter it, and p2bverdict.py must FAIL naming that section. A mutant whose pattern matches nothing is
INVALID (the self-test fails: it would otherwise prove nothing). ajudge.py is fed synthetic runs, caught and not."""
import sys, os, re, shutil, subprocess, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
run = sys.argv[1]
FILES = ["SA.txt", "SB.txt", "SC.txt", "SD.txt", "VA.txt", "VB.txt", "VC.txt", "VD.txt", "VE.txt",
         "AA.txt", "AB.txt", "AC.txt", "AD.txt", "G.txt"]
# (section file, regex, replacement, description); the first match is altered; "DELETE" removes the whole line
MUT = [
    ("SA.txt", r"(su01_modes min: pipeline exit )0", r"\g<1>3", "a CPU-SU test failing on the pipeline"),
    ("SA.txt", r"(su09_warl min: pipeline exit 8 errors 0 \| multicycle exit )8", r"\g<1>0", "the reference leaving its baseline"),
    ("SB.txt", r"DIFF_OK", "DIFF_FAIL", "a privilege differential mismatch"),
    ("SC.txt", r"without an interrupt: exit 2 ", "without an interrupt: exit 0 ", "an interrupt test passing without its interrupt"),
    ("SC.txt", r": PASS k=", ": FAIL(exit 3) k=", "an interrupt case failing its checks"),
    ("SC.txt", r"\| aligned\(N'=\d+\): DIFF_OK", "| not-aligned", "an interrupt case not aligning"),
    ("SD.txt", r": CAUGHT first signal", ": NOT CAUGHT first signal", "an SU injection not caught"),
    ("SD.txt", r"(control \S+ on t01: exit 0, errors )0", r"\g<1>1", "an SU control failing"),
    ("VA.txt", r"(sv01_bare_sv39 min: pipeline exit )0", r"\g<1>5", "a Sv39 test failing on the pipeline"),
    ("VA.txt", r"7 commit-count checks OK", "6 commit-count checks OK", "a faulting instruction retiring"),
    ("VB.txt", r"hzsv3 fixed: DIFF_OK", "hzsv3 fixed: DIFF_FAIL", "a generated Sv39 program differing"),
    ("VB.txt", r"^  hzsv20 rnd12345: .*$", "DELETE", "a missing differential"),
    ("VC.txt", r": PASS k=(\d+) pte", r": FAIL(exit 2) k=\1 pte", "a walk-interrupt case failing"),
    ("VC.txt", r"outstanding: \d+$", "outstanding: 3", "too few raises during a walk"),
    ("VD.txt", r"(knob 21 \(TLB_NO_FLUSH\) on sv06: )CAUGHT", r"\g<1>NOT CAUGHT", "knob 21 not caught"),
    ("VD.txt", r"multi=0x0*30002ffe ", "multi=0x0000000030003000 ", "IF2 diverging elsewhere"),
    ("VD.txt", r"(tcpu_permcheck; knob 22 removes that check\): exit )0", r"\g<1>1", "the masked PTW_NO_PERM failing"),
    ("VE.txt", r"(data_walks = )\d+", r"\g<1>0", "no data walks"),
    ("AA.txt", r"(a01 t1: pipeline exit 0 errors 0 score )0", r"\g<1>1", "the A matrix checker failing on the pipeline"),
    ("AA.txt", r"(a02 race: .*\| multicycle exit )0", r"\g<1>7", "the reference failing the race"),
    ("AA.txt", r"(a03 t2: pipeline exit 0 errors )0", r"\g<1>2", "an A run with harness errors"),
    ("AA.txt", r"self-test exit code: refused", "self-test exit code: NOT refused", "the exit-code self-test not refusing"),
    ("AB.txt", r"a02 race: DIFF_OK", "a02 race: DIFF_FAIL", "an A differential mismatch"),
    ("AB.txt", r"^  a01 t2: .*$", "DELETE", "a missing A differential"),
    ("AC.txt", r"writes=5;", "writes=4;", "the interrupt-free AMO run writing the wrong number of times"),
    ("AC.txt", r"without an interrupt: exit 8 ", "without an interrupt: exit 0 ", "the AMO test passing without its interrupt"),
    ("AC.txt", r": PASS k=(\d+) inside_atomic=1", r": FAIL(exit 0, errors 0, interrupts 1, writes 6) k=\1 inside_atomic=1", "an AMO performed twice across an interrupt"),
    ("AC.txt", r"\| aligned\(N'=\d+\): DIFF_OK exit=0 ", "| aligned(N'=5) BUT DIFF_FAIL exit=0 ", "an AMO interrupt case differing"),
    ("AC.txt", r"atomic access: \d+$", "atomic access: 2", "too few raises inside an atomic"),
    ("AD.txt", r"(FAULT_A_SC_RESULT on pmcsa, a02: )CAUGHT", r"\g<1>NOT CAUGHT", "an A injection not caught on the pipeline"),
    ("AD.txt", r"(FAULT_A_EARLY_RETIRE on ma, a01: )CAUGHT", r"\g<1>NOT CAUGHT", "an A injection not caught on the reference"),
    ("AD.txt", r"(control pmcsa-FAULT_A_NO_RESV_CLEAR on t01: exit )0", r"\g<1>1", "an A control failing"),
    ("G.txt", r"^  unchanged (tcpu_core\.v)", r"  CHANGED \1", "a multicycle source changed"),
]
SECTION = lambda f: f.split(".")[0]
bad = []
def verdict(d):
    p = subprocess.run([sys.executable, os.path.join(HERE, "p2bverdict.py"), d], capture_output=True, text=True)
    return p.returncode, p.stdout
with tempfile.TemporaryDirectory(prefix="p2b-selftest-") as tmp:
    base = os.path.join(tmp, "base"); os.mkdir(base)
    for f in FILES: shutil.copy(os.path.join(run, f), base)
    rc, out = verdict(base)
    print(f"  original run: verdict rc={rc} ({out.strip().splitlines()[-1] if out.strip() else ''})")
    if rc != 0: bad.append("the original run does not pass: the mutants would prove nothing")
    for i, (f, rx, rep, what) in enumerate(MUT):
        d = os.path.join(tmp, f"m{i}"); shutil.copytree(base, d)
        txt = open(os.path.join(d, f)).read()
        m = re.search(rx, txt, re.M)
        if not m: bad.append(f"INVALID mutant {i} ({what}): /{rx}/ matches nothing in {f}"); print(f"  mutant {i:2d} INVALID  {what}"); continue
        new = txt[:m.start()] + ("" if rep == "DELETE" else m.expand(rep)) + txt[m.end():]
        if rep == "DELETE" and new[m.start():m.start() + 1] == "\n": new = new[:m.start()] + new[m.start() + 1:]
        open(os.path.join(d, f), "w").write(new)
        rc, out = verdict(d)
        reasons = [l for l in out.splitlines() if l.startswith("  FAIL  ")]
        own = [l for l in reasons if l.startswith(f"  FAIL  {SECTION(f)}")]
        ok = rc == 1 and own
        print(f"  mutant {i:2d} {'refused' if ok else 'ACCEPTED'}  {f}: {what}" + (f" -> {own[0].strip()[:110]}" if own else f" (rc={rc}, reasons {reasons[:2]})"))
        if not ok: bad.append(f"mutant {i} ({what}) was not refused for its own section")
    # a missing section file
    d = os.path.join(tmp, "missing"); shutil.copytree(base, d); os.remove(os.path.join(d, "AD.txt"))
    rc, out = verdict(d); ok = rc == 1 and "missing output: AD.txt" in out
    print(f"  mutant missing-AD {'refused' if ok else 'ACCEPTED'}")
    if not ok: bad.append("a run without AD.txt was not refused")
    # ---- ajudge.py on synthetic runs
    def aj(log, ec, rx, score=None):
        pre = os.path.join(tmp, "aj"); open(pre + ".log", "w").write(log); open(pre + ".exit", "w").write(ec)
        args = [sys.executable, os.path.join(HERE, "ajudge.py"), pre, rx]
        if score is not None: open(pre + ".score", "w").write(score); args.append(pre + ".score")
        return subprocess.run(args, capture_output=True, text=True).returncode
    ER = "^A_OBS_FAIL early-retire"; SC = "the SC returned 0, the rule says 1"
    FAILSC = "A02 cases=14\n  FAIL: case 3 (x): the SC returned 0, the rule says 1\n"
    AJ = [("the monitor fires first", "CMT a\nA_OBS_FAIL early-retire pc=0x1\nTOHOST code=0\n", "0", ER, None, 0),
          ("an assert fires before the monitor", "PIPE ASSERT data-response\nA_OBS_FAIL early-retire pc=0x1\n", "3", ER, None, 1),
          ("the run passed", "TOHOST code=0\n", "0", ER, None, 1),
          ("killed by the timeout", "A_OBS_FAIL early-retire pc=0x1\n", "124", ER, None, 1),
          ("the checker's first failure is the named one", "TOHOST code=0\n", "0", SC, FAILSC, 0),
          ("the program noticed too", "TOHOST code=5\n", "5", SC, FAILSC, 0),
          ("the checker's first failure is another", "TOHOST code=0\n", "0", SC, "  FAIL: case 1: the word is 0x1, the rule says 0x2\n" + FAILSC, 1),
          ("the run failed before the checker", "PROTO ERROR: x\nTOHOST code=0\n", "0", SC, FAILSC, 1),
          ("the checker found nothing", "TOHOST code=0\n", "0", SC, "A02 cases=14 disagreements=0\n", 1)]
    for what, log, ec, rx, score, want in AJ:
        got = aj(log, ec, rx, score)
        print(f"  ajudge {'ok' if got == want else 'WRONG'}  {what}: rc {got}, required {want}")
        if got != want: bad.append(f"ajudge: {what}: rc {got}, required {want}")
for b in bad: print("  FAIL  " + b)
print(f"P2B_SELFTEST {'PASS' if not bad else 'FAIL'} ({len(MUT) + 1} verdict mutants, 9 judge cases, {len(bad)} failures)")
sys.exit(1 if bad else 0)
