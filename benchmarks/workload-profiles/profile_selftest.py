#!/usr/bin/env python3
"""Offline tests for the proposed workload-profile delta to the frozen xv6 driver and checker.

The delta is NOT applied to the repository. This applies it to a scratch copy, so the provenance gate is
untouched and the patch can be reviewed before anything is frozen differently.

What must hold:

  * the DEFAULT behaviour is unchanged -- including that the accepted board transcript still checks clean
    through the patched checker. That is the regression that matters;
  * a named profile drives and checks the same three commands, by construction, from one definition;
  * there is no way to pass an arbitrary command: the interface takes a NAME;
  * wrong output, a truncated transcript, a missing stage and an unknown profile name are each refused.

  profile_selftest.py
"""
import os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PATCH = os.path.join(ROOT, "benchmarks/workload-profiles/xv6-workload-profiles.patch")
npass = nfail = 0
def ok(w):      global npass; npass += 1; print(f"  ok   : {w}")
def no(w, why): global nfail; nfail += 1; print(f"  FAIL : {w} -- {why}")
def want(c, w, why=""): ok(w) if c else no(w, why)

work = tempfile.mkdtemp(prefix="wprofile-")
mod = os.path.join(work, "mod")
os.makedirs(mod)
for f in ("tools/xv6-boot/scripts/xv6_console.py", "tools/xv6-boot/scripts/check-xv6.py",
          "tools/board/scripts/board_run.py", "tools/board/scripts/board-runner.py"):
    os.makedirs(os.path.join(mod, os.path.dirname(f)), exist_ok=True)
    shutil.copy(os.path.join(ROOT, f), os.path.join(mod, f))
r = subprocess.run(["patch", "-p1", "-s", "-d", mod, "-i", PATCH], capture_output=True, text=True)
want(r.returncode == 0, "the patch applies cleanly to a scratch copy", r.stdout + r.stderr)

sys.path.insert(0, os.path.join(mod, "tools/xv6-boot/scripts"))
import xv6_console as XC
UnknownProfile = XC.UnknownProfile

print("== 1. the default is untouched")
exp, stages = XC.profile("default")
want(exp is XC.EXPECTED or exp == XC.EXPECTED, "profile('default') is the original EXPECTED", f"{exp}")
want([c for _, c, _ in exp] == ["echo teaching-xv6-hello", "ls", "cat README", "echo abc | wc"],
     "  and it is still the accepted four commands, in order", f"{[c for _,c,_ in exp]}")
want(stages == XC.STAGES, "  and its stage names are the original STAGES", f"{stages}")

print("== 2. the named profile exists and is shared by construction")
exp2, stages2 = XC.profile("b0apps")
want([c for _, c, _ in exp2] == ["b0compute", "b0array", "b0file"],
     "profile('b0apps') drives the three application workloads", f"{[c for _,c,_ in exp2]}")
want(stages2[:3] == XC.STAGES[:3] and stages2[3:] == ["command b0compute", "command b0array", "command b0file"],
     "  and its stage names follow from the same definition", f"{stages2}")
want(all(re.search(r"CHECKSUM=[0-9a-f]+", rx) for _, _, rx in exp2),
     "  each carries an explicit expected checksum, not a bare marker",
     f"{[rx for _,_,rx in exp2]}")

print("== 3. there is no arbitrary-command escape hatch")
try:
    XC.profile("rm -rf /")
    no("an arbitrary command cannot be passed as a profile", "it was accepted")
except UnknownProfile as e:
    want("unknown workload profile" in str(e), "an arbitrary command cannot be passed as a profile", str(e))
try:
    XC.profile("nonexistent")
    no("an unknown profile name is refused", "it was accepted")
except UnknownProfile:
    ok("an unknown profile name is refused")
want(all(isinstance(k, str) for k in XC.PROFILES),
     "  the interface takes a NAME; commands live only in the profile table")

print("== 4. THE regression: the accepted board transcript still checks clean")
chk = os.path.join(mod, "tools/xv6-boot/scripts/check-xv6.py")
acc = os.path.join(ROOT, "evidence/xv6-board-run-3/run-1")
r = subprocess.run([sys.executable, chk, acc, "--require-commands"], capture_output=True, text=True)
want(r.returncode == 0 and "fails=0" in r.stdout,
     "the patched checker still accepts the accepted board transcript unchanged",
     (r.stdout + r.stderr)[-300:])

print("== 5. a b0apps transcript checks against the b0apps profile")
def make_run(dirpath, workload, cmds_outputs, stage_status="ok", extra_header=""):
    os.makedirs(dirpath, exist_ok=True)
    hdr = open(os.path.join(acc, "stages.txt")).read().splitlines()
    keep = [l for l in hdr if l.startswith("#") and not l.startswith("# workload:")]
    names = ["kernel banner", "init started / first prompt", "shell prompt"] + \
            [f"command {n}" for n, _ in cmds_outputs]
    with open(os.path.join(dirpath, "stages.txt"), "w") as f:
        for i, n in enumerate(names):
            f.write(f"{stage_status}\t{i+1}.0\t{n}\n")
        f.write(f"# workload: {workload}\n")
        for l in keep: f.write(l + "\n")
        if extra_header: f.write(extra_header + "\n")
    con = ["", "xv6 kernel is booting", "", "init: starting sh"]
    for name, out in cmds_outputs:
        con.append(f"$ {name}")
        con.append(out)
    con.append("$ ")
    open(os.path.join(dirpath, "console.txt"), "w").write("\n".join(con) + "\n")
    return dirpath

GOOD = [("b0compute", "B0-COMPUTE-CHECKSUM=5adf55920bf7696\nB0-COMPUTE-DONE"),
        ("b0array",   "B0-ARRAY-CHECKSUM=88133d5bd386db60\nB0-ARRAY-DONE"),
        ("b0file",    "B0-FILE-CHECKSUM=62e55f5326378000\nB0-FILE-DONE")]

def check(dirpath):
    return subprocess.run([sys.executable, chk, dirpath, "--require-commands"],
                          capture_output=True, text=True)


def refused(r, label, expect_in):
    """Refused, AND for the stated reason. An earlier version of this file accepted any non-zero exit,
    so when the patched checker crashed with NameError every negative passed on the crash."""
    out = r.stdout + r.stderr
    if r.returncode == 0:
        no(label, "it was accepted")
    elif "Traceback" in out:
        no(label, f"it exited non-zero by CRASHING, not by refusing: {out.strip()[-160:]}")
    elif expect_in and expect_in not in out:
        no(label, f"refused, but not for the stated reason: {out.strip()[-160:]}")
    else:
        ok(label)

d = make_run(os.path.join(work, "good"), "b0apps", GOOD)
r = check(d)
want(r.returncode == 0 and "fails=0" in r.stdout,
     "a correct b0apps transcript is accepted", (r.stdout + r.stderr)[-300:])

print("== 6. negatives")
bad = [("b0compute", "B0-COMPUTE-CHECKSUM=deadbeefdeadbeef\nB0-COMPUTE-DONE")] + GOOD[1:]
refused(check(make_run(os.path.join(work, "wrongsum"), "b0apps", bad)),
        "a wrong checksum is refused", "b0compute")

trunc = [("b0compute", "B0-COMPUTE-CHECK")] + GOOD[1:]
refused(check(make_run(os.path.join(work, "trunc"), "b0apps", trunc)),
        "a truncated output is refused", "b0compute")

refused(check(make_run(os.path.join(work, "timeout"), "b0apps", GOOD, stage_status="TIMEOUT")),
        "a transcript whose stages timed out is refused", "TIMEOUT")

refused(check(make_run(os.path.join(work, "missing"), "b0apps", GOOD[:2])),
        "a transcript missing a command stage is refused", "b0file")

refused(check(make_run(os.path.join(work, "unknown"), "not-a-profile", GOOD)),
        "a transcript naming an unknown profile is refused, not checked as default",
        "unknown workload profile")

print("== 7. a default transcript is not silently accepted against b0apps")
refused(check(make_run(os.path.join(work, "mismatch"), "b0apps",
                       [("echo teaching-xv6-hello", "teaching-xv6-hello"), ("ls", "README"),
                        ("cat README", "xv6 is a")])),
        "the four-command workload does not satisfy the b0apps profile", "b0compute")

print(f"WORKLOAD_PROFILE_SELFTEST pass={npass} fail={nfail}")
shutil.rmtree(work, ignore_errors=True)
sys.exit(1 if nfail else 0)
