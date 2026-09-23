#!/usr/bin/env python3
"""Solve the two-point frequency model from an E1 run and a 40 MHz run.

    L(f) = N_cycles + T_fixed * f

`L` is a measured ROI cost in CYCLES at configured frequency `f`. `N_cycles` is the part that scales
with the design clock -- fabric logic, which costs the same number of cycles whatever the clock does --
and `T_fixed` is a fixed TIME spent off the design clock (the PS/DDR path), which costs more cycles the
faster you clock. Two frequencies give two equations, so both fall out.

Three things this tool refuses to pretend:

* **two points cannot test linearity.** A line through two points always fits exactly. `linearity` in
  the output is therefore always "assumed, not tested"; testing it needs a third frequency. What two
  points *can* do is check a falsifiable prediction, which is the next item.
* **the CLINT load is the control.** It never leaves the fabric, so the model predicts its `T_fixed` is
  zero. If it is not zero within the measured spread, something other than the PS/DDR path moved between
  the builds and the DRAM numbers describe that instead. Every DRAM result is then marked
  not-interpretable -- not silently, and not merely footnoted.
* **an unphysical solution is a result about the model, not a number to report.** Negative fixed time,
  or negative cycle count, means the two points do not lie where the model says they must.

  e1_model.py <metrics-a.json> <metrics-b.json> [--out model.json]
"""
import json
import statistics
import sys


class ModelRefused(Exception):
    """A solve that would not mean anything."""


def spread(c):
    """The observed peak-to-peak spread of an ROI's cycle samples, used as its uncertainty.

    This is what was actually measured, not an assumed distribution: with five samples there is no
    basis for a standard error that would be narrower than the range itself.
    """
    return abs(c["max"] - c["min"])


def solve_roi(a, b, fa, fb):
    """Solve one ROI. `a`/`b` are its result entries; `fa`/`fb` the configured frequencies in Hz."""
    if fa == fb:
        raise ModelRefused("the two runs share a configured frequency; there is nothing to solve")
    ca, cb = a.get("cycles"), b.get("cycles")
    if not ca or not cb:
        raise ModelRefused("one side has no successful samples; its cost is null, not zero")
    if a["platform"] != b["platform"]:
        raise ModelRefused(f"{a['platform']} against {b['platform']}: different machines")

    la, lb = ca["median"], cb["median"]
    t_fixed = (la - lb) / (fa - fb)                 # seconds
    n_cycles = la - t_fixed * fa
    # Uncertainty propagated from the measured spreads, not invented.
    u_t = (spread(ca) + spread(cb)) / abs(fa - fb)
    u_n = spread(ca) + u_t * fa
    return dict(
        roi=a["roi"], workload=a["workload"],
        cycles_at={str(fa): la, str(fb): lb},
        spread_at={str(fa): spread(ca), str(fb): spread(cb)},
        t_fixed_seconds=t_fixed, t_fixed_uncertainty_seconds=u_t,
        t_fixed_ns=t_fixed * 1e9, t_fixed_uncertainty_ns=u_t * 1e9,
        n_cycles=n_cycles, n_cycles_uncertainty=u_n,
        consistent_with_zero_fixed_time=abs(t_fixed) <= u_t,
        physical=(t_fixed >= -u_t and n_cycles >= -u_n),
    )


CONTROL_ROI = "load_clint"


def run(ma, mb):
    fa, fb = ma["frequency"]["hz"], mb["frequency"]["hz"]
    by_a = {r["roi"]: r for r in ma["results"] if r["roi"] != "_extra"}
    by_b = {r["roi"]: r for r in mb["results"] if r["roi"] != "_extra"}
    shared = sorted(set(by_a) & set(by_b))

    solved, refused = [], []
    for roi in shared:
        try:
            solved.append(solve_roi(by_a[roi], by_b[roi], fa, fb))
        except ModelRefused as e:
            refused.append(dict(roi=roi, reason=str(e)))

    # The control decides whether anything else may be read as a PS/DDR figure.
    ctrl = next((s for s in solved if s["roi"] == CONTROL_ROI), None)
    if ctrl is None:
        control = dict(present=False, holds=False,
                       verdict=f"the control ROI {CONTROL_ROI} is absent from one or both runs, so "
                               f"nothing here distinguishes a PS/DDR effect from any other difference "
                               f"between the two builds")
    else:
        holds = ctrl["consistent_with_zero_fixed_time"]
        control = dict(
            present=True, holds=holds,
            t_fixed_ns=ctrl["t_fixed_ns"], uncertainty_ns=ctrl["t_fixed_uncertainty_ns"],
            verdict=("the CLINT load shows no fixed time within its measured spread, which is what the "
                     "model predicts for an ROI that never leaves the fabric"
                     if holds else
                     "the CLINT load shows a fixed time it should not have. Something other than the "
                     "PS/DDR path moved between these two builds. The DRAM figures below describe that "
                     "something, whatever it is, and are NOT interpretable as memory latency."))

    for s in solved:
        s["interpretable"] = bool(control["holds"] and s["physical"])
        if not s["physical"]:
            s["not_interpretable_because"] = ("the solution is unphysical: a negative fixed time or a "
                                              "negative cycle count means these two points do not lie "
                                              "where the model requires")
        elif not control["holds"]:
            s["not_interpretable_because"] = "the control failed; see control.verdict"

    return dict(
        model="L(f) = N_cycles + T_fixed * f",
        kind="two-point empirical solve",
        linearity="ASSUMED, NOT TESTED. A line through two points always fits exactly; testing "
                  "linearity needs a third frequency. The control below is the one falsifiable "
                  "prediction these two points can check.",
        runs={str(fa): ma["run_id"], str(fb): mb["run_id"]},
        frequencies_hz=[fa, fb],
        platform=ma["platform"],
        control_roi=CONTROL_ROI, control=control,
        rois_solved=len(solved), rois_refused=len(refused),
        interpretable=sum(1 for s in solved if s["interpretable"]),
        results=solved, refused=refused,
    )


def main(argv):
    ma = json.load(open(argv[0]))
    mb = json.load(open(argv[1]))
    out = run(ma, mb)
    if "--out" in argv:
        dest = argv[argv.index("--out") + 1]
        with open(dest, "w") as f:
            json.dump(out, f, indent=2)
            f.write("\n")
    print(f"E1_MODEL {out['frequencies_hz'][0]} vs {out['frequencies_hz'][1]} Hz: "
          f"{out['rois_solved']} solved, {out['rois_refused']} refused, "
          f"{out['interpretable']} interpretable")
    print(f"  control {CONTROL_ROI}: {'HOLDS' if out['control']['holds'] else 'FAILED'}")
    print(f"    {out['control']['verdict']}")
    print(f"  linearity: {out['linearity'].split('.')[0]}")
    for s in out["results"]:
        mark = "   " if s["interpretable"] else "  !"
        print(f"{mark} {s['roi']:12} T_fixed {s['t_fixed_ns']:9.1f} +/- {s['t_fixed_uncertainty_ns']:6.1f} ns"
              f"   N {s['n_cycles']:10.1f} +/- {s['n_cycles_uncertainty']:.1f}")
    return 0 if out["control"]["holds"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
