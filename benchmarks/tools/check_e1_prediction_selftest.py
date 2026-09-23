#!/usr/bin/env python3
"""Prove the prediction checker can say FALSIFIED, and says it for the right reason."""
import json, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PRED = json.load(open(os.path.join(ROOT, "experiments/E1-clock-scaling/PREDICTION.json")))
# Overridable so a mutant of the checker can be pointed at without relocating this file -- ROOT is
# derived from HERE, so copying the selftest elsewhere breaks it. (That bit me: a mutant run produced no
# output at all, which is neither a pass nor a catch.)
CHECK = os.environ.get("E1_CHECK_BIN", os.path.join(HERE, "check_e1_prediction.py"))
npass = nfail = 0
def ok(w):      global npass; npass += 1; print(f"  ok   : {w}")
def no(w, why): global nfail; nfail += 1; print(f"  FAIL : {w} -- {why}")

def synth(vals, hz=25_000_000, spread=200):
    res = [dict(platform="board", run_id="synthetic", workload="perf04_where", roi=k, status="reported",
                cycles=dict(median=v, min=v - spread // 2, max=v + spread // 2, n=5)) for k, v in vals.items()]
    f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(dict(run_id="synthetic", platform="board", frequency=dict(hz=hz, source="configured"),
                   results=res), f); f.close()
    return f.name

PREDPATH = os.path.join(ROOT, "experiments/E1-clock-scaling/PREDICTION.json")


def run(path):
    """Run the checker and REFUSE to treat a crash as a verdict.

    A crashing checker exits non-zero with nothing on stdout, which reads exactly like a falsification
    unless something distinguishes them. It caught me out once here already, so every case now requires
    the checker to have reached one of its own marker lines.
    """
    p = subprocess.run([sys.executable, CHECK, path, PREDPATH], capture_output=True, text=True)
    if not ("E1_PREDICTION_CHECK " in p.stdout or "REFUSE:" in p.stdout):
        return None, (p.stdout + p.stderr)[-300:]
    return p.returncode, p.stdout

P = {p["roi"]: p for p in PRED["predictions"]}
EXACT = {"alu": P["alu"]["predicted_cycles_at_25mhz"],
         "load_clint": P["load_clint"]["predicted_cycles_at_25mhz"],
         "load_dram": sum(P["load_dram"]["bracket_cycles_at_25mhz"]) // 2}

print("== 1. a run that matches the prediction holds")
rc, out = run(synth(EXACT))
ok("every prediction holds and the checker exits 0") if rc == 0 and "falsified=0" in out \
    else no("a matching run holds", f"rc={rc} {out.strip()[-200:]}")
ok("  and the DRAM position is reported as a split, not a pass/fail") if "as fixed time and" in out \
    else no("the DRAM split is reported", out[-200:])

print("== 2. a fabric-only ROI that MOVED is falsified")
moved = dict(EXACT); moved["load_clint"] += 50_000
rc, out = run(synth(moved))
ok("a CLINT load that moved is falsified, and the checker exits non-zero") if rc == 1 and "FALSIFIED load_clint" in out \
    else no("a moved control is falsified", f"rc={rc} {out.strip()[-200:]}")
ok("  and the message says it does not behave as fabric-only") if "does not behave as fabric-only" in out \
    else no("the reason is named", out[-200:])

print("== 3. a DRAM reading outside the bracket is falsified")
outside = dict(EXACT); outside["load_dram"] = P["load_dram"]["bracket_cycles_at_25mhz"][1] + 200_000
rc, out = run(synth(outside))
ok("a reading above the bracket is falsified") if rc == 1 and "FALSIFIED load_dram" in out \
    else no("outside the bracket is falsified", f"rc={rc} {out.strip()[-200:]}")
ok("  and it says the two-hypothesis split does not describe the system") \
    if "neither fixed time nor design-clock" in out else no("the reason is named", out[-200:])

print("== 4. the bracket ENDS are inside it, so a pure hypothesis is not falsified by rounding")
for end, label in ((P["load_dram"]["bracket_cycles_at_25mhz"][0], "all fixed time"),
                   (P["load_dram"]["bracket_cycles_at_25mhz"][1], "all design-clock cycles")):
    v = dict(EXACT); v["load_dram"] = end
    rc, out = run(synth(v))
    # NOT "FALSIFIED is absent": an empty output satisfies that vacuously, which is how a crashing
    # checker passed this section once. Require the positive line.
    ok(f"the '{label}' end of the bracket holds") if rc == 0 and "HOLDS     load_dram" in out \
        else no(f"'{label}' end holds", f"rc={rc} {out[-160:]}")

print("== 5. a run at the wrong frequency is refused, not compared")
rc, out = run(synth(EXACT, hz=40_000_000))
ok("a 40 MHz run is refused against a 25 MHz prediction (exit 2)") if rc == 2 and "REFUSE" in out \
    else no("wrong frequency refused", f"rc={rc} {out.strip()[-160:]}")

print("== 6. a missing ROI concludes nothing and does not pass")
miss = {k: v for k, v in EXACT.items() if k != "load_dram"}
rc, out = run(synth(miss))
ok("an absent ROI is reported absent and the checker does not exit 0") if rc == 1 and "ABSENT" in out \
    else no("absent ROI", f"rc={rc} {out.strip()[-160:]}")

print(f"E1_PREDICTION_CHECK_SELFTEST pass={npass} fail={nfail}")
sys.exit(1 if nfail else 0)
