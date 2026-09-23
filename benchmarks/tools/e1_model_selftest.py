#!/usr/bin/env python3
"""Check e1_model.py against data whose answer is known, and against data it must refuse.

Synthetic throughout: no board, no run directory. The point of planting the parameters is that a solver
which silently returned something plausible would still be wrong, and only a planted value catches that.

  e1_model_selftest.py
"""
import copy
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e1_model                                                        # noqa: E402

npass = nfail = 0
def ok(w):      global npass; npass += 1; print(f"  ok   : {w}")
def no(w, why): global nfail; nfail += 1; print(f"  FAIL : {w} -- {why}")
def want(c, w, why=""): ok(w) if c else no(w, why)

F_HI, F_LO = 40_000_000, 25_000_000


def roi(name, n_cycles, t_fixed, f, spread=0, platform="board"):
    """One ROI entry whose cycle count is exactly N + T*f, so the solver's answer is known."""
    median = n_cycles + t_fixed * f
    return dict(platform=platform, run_id=f"synthetic-{f}", workload="perf04_where", roi=name,
                status="reported", samples_successful=5, samples_failed=0,
                cycles=dict(median=median, min=median - spread / 2, max=median + spread / 2, n=5))


def metrics(f, rois):
    return dict(run_id=f"synthetic-{f}", platform="board", frequency=dict(hz=f, source="configured"),
                results=rois)


# The planted truth: the CLINT load never leaves the fabric, so its fixed time is zero; the DRAM load
# spends a real fixed time in the PS/DDR path.
PLANT = {"load_clint": (900_000, 0.0), "load_dram": (1_200_000, 4.5e-4), "alu": (1_000_000, 0.0)}

def pair(plant=PLANT, spread=0, platform_lo="board"):
    hi = metrics(F_HI, [roi(k, n, t, F_HI, spread) for k, (n, t) in plant.items()])
    lo = metrics(F_LO, [roi(k, n, t, F_LO, spread, platform_lo) for k, (n, t) in plant.items()])
    return hi, lo


print("== 1. the planted parameters come back")
out = e1_model.run(*pair())
for s in out["results"]:
    n_want, t_want = PLANT[s["roi"]]
    want(abs(s["n_cycles"] - n_want) < 1e-6, f"{s['roi']}: N recovered as {n_want:,}",
         f"got {s['n_cycles']}")
    want(abs(s["t_fixed_seconds"] - t_want) < 1e-15, f"{s['roi']}: T_fixed recovered as {t_want} s",
         f"got {s['t_fixed_seconds']}")

print("== 2. the control, when it holds")
want(out["control"]["present"] and out["control"]["holds"],
     "a CLINT load with no fixed time passes the control", json.dumps(out["control"])[:200])
want(all(s["interpretable"] for s in out["results"]),
     "  and every ROI is then interpretable", "some were not")

print("== 3. the control, when it FAILS, disqualifies the DRAM figure")
bad = dict(PLANT); bad["load_clint"] = (900_000, 2.0e-4)     # the control moved: it should not have
out2 = e1_model.run(*pair(bad))
want(not out2["control"]["holds"], "a CLINT load with a fixed time FAILS the control",
     "the control passed when it should not have")
dram = next(s for s in out2["results"] if s["roi"] == "load_dram")
want(not dram["interpretable"], "  and the DRAM figure is marked NOT interpretable", "it stayed interpretable")
want("NOT interpretable as memory latency" in out2["control"]["verdict"],
     "  and the verdict says so in words, not only in a flag", out2["control"]["verdict"][:120])
want(out2["interpretable"] == 0, "  no ROI survives a failed control", f"{out2['interpretable']} did")

print("== 4. the control's absence is not the control passing")
hi, lo = pair()
hi["results"] = [r for r in hi["results"] if r["roi"] != "load_clint"]
out3 = e1_model.run(hi, lo)
want(not out3["control"]["present"] and not out3["control"]["holds"],
     "a missing control ROI is reported absent AND does not hold", json.dumps(out3["control"])[:160])
want(out3["interpretable"] == 0, "  nothing is interpretable without the control", "something was")

print("== 5. refusals")
hi, lo = pair(); lo["frequency"]["hz"] = F_HI
out4 = e1_model.run(hi, lo)
want(out4["rois_solved"] == 0 and out4["rois_refused"] == 3,
     "two runs at the SAME frequency solve nothing", f"solved {out4['rois_solved']}")
want("nothing to solve" in out4["refused"][0]["reason"], "  and the reason names it",
     out4["refused"][0]["reason"])

hi, lo = pair()
for r in lo["results"]:
    if r["roi"] == "load_dram":
        r["cycles"] = None; r["samples_successful"] = 0
out5 = e1_model.run(hi, lo)
r5 = next(x for x in out5["refused"] if x["roi"] == "load_dram")
want("null, not zero" in r5["reason"], "an ROI with no successful samples is null, not zero", r5["reason"])
want(out5["rois_solved"] == 2, "  and the other ROIs still solve", f"solved {out5['rois_solved']}")

out6 = e1_model.run(*pair(platform_lo="simulator"))
want(out6["rois_solved"] == 0 and "different machines" in out6["refused"][0]["reason"],
     "a board run against a simulator run is refused", json.dumps(out6["refused"][:1]))

print("== 6. an unphysical solution is not reported as a measurement")
weird = dict(PLANT); weird["load_dram"] = (1_200_000, -3.0e-4)    # negative fixed time
out7 = e1_model.run(*pair(weird))
d7 = next(s for s in out7["results"] if s["roi"] == "load_dram")
want(not d7["physical"], "a negative fixed time is flagged unphysical", "it was called physical")
want(not d7["interpretable"] and "unphysical" in d7.get("not_interpretable_because", ""),
     "  and is not interpretable, with the reason attached", json.dumps(d7)[:160])

print("== 7. uncertainty comes from the measured spread, and widens the control")
tiny = dict(PLANT); tiny["load_clint"] = (900_000, 1.0e-7)   # a fixed time far below any real spread
out8 = e1_model.run(*pair(tiny, spread=0))
want(not out8["control"]["holds"], "with zero spread even a tiny control offset fails", "it passed")
out9 = e1_model.run(*pair(tiny, spread=100))
want(out9["control"]["holds"], "  the same offset inside a real spread is consistent with zero",
     f"u={out9['control']['uncertainty_ns']} t={out9['control']['t_fixed_ns']}")

print("== 8. linearity is never claimed to have been tested")
want("ASSUMED, NOT TESTED" in out["linearity"] and "third frequency" in out["linearity"],
     "the output says linearity is assumed and names what would test it", out["linearity"][:100])

print(f"E1_MODEL_SELFTEST pass={npass} fail={nfail}")
sys.exit(1 if nfail else 0)
