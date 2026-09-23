#!/usr/bin/env python3
"""Compare a measured E1 run against the pre-registered prediction.

The comparison is mechanical so that it cannot be retrofitted. This tool is able to say FALSIFIED, and
that is the only reason it is worth running: a checker that can only agree with whatever arrived would
add nothing to the claim.

Exit 0 only when every prediction holds. A falsified prediction is a RESULT, not an error -- it means
the model, or the claim that an ROI stays in the fabric, is wrong. It is reported as such.

  check_e1_prediction.py <e1-metrics.json> [<prediction.json>]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def main(argv):
    m = json.load(open(argv[0]))
    pred = json.load(open(argv[1] if len(argv) > 1
                          else os.path.join(ROOT, "experiments/E1-clock-scaling/PREDICTION.json")))
    if m["frequency"]["hz"] != pred["target_frequency_hz"]:
        print(f"REFUSE: this run is configured at {m['frequency']['hz']} Hz; the prediction was "
              f"registered for {pred['target_frequency_hz']} Hz")
        return 2
    by = {r["roi"]: r for r in m["results"] if r.get("cycles")}

    held, broke, absent = [], [], []
    for p in pred["predictions"]:
        r = by.get(p["roi"])
        if not r:
            absent.append(p["roi"]); continue
        c = r["cycles"]; got = c["median"]; got_spread = c["max"] - c["min"]
        if p["kind"] == "fabric-only":
            tol = p["tolerance_cycles"] + got_spread
            delta = got - p["predicted_cycles_at_25mhz"]
            (held if abs(delta) <= tol else broke).append(dict(
                roi=p["roi"], kind=p["kind"], predicted=p["predicted_cycles_at_25mhz"],
                measured=got, delta=delta, tolerance=tol,
                verdict=("unchanged within the two runs' spreads, as the model requires"
                         if abs(delta) <= tol else
                         f"moved by {delta:+,} cycles, more than the {tol:,} the spreads allow. "
                         f"This ROI does not behave as fabric-only, or the model is wrong.")))
        else:
            lo, hi = p["bracket_cycles_at_25mhz"]
            slack = got_spread + p["observed_spread_at_40mhz"]
            inside = (lo - slack) <= got <= (hi + slack)
            # where in the bracket it landed IS the answer
            frac = (got - lo) / (hi - lo) if hi != lo else None
            (held if inside else broke).append(dict(
                roi=p["roi"], kind=p["kind"], bracket=[lo, hi], measured=got, slack=slack,
                fraction_of_excess_that_is_design_clock_cycles=frac,
                verdict=(f"inside the bracket; {1-frac:.1%} of the excess behaves as fixed time and "
                         f"{frac:.1%} as design-clock work" if inside and frac is not None else
                         f"OUTSIDE the bracket [{lo:,} .. {hi:,}] by more than {slack:,} cycles. The "
                         f"excess is neither fixed time nor design-clock work, so the two-hypothesis "
                         f"split does not describe this system.")))

    for h in held:
        print(f"  HOLDS     {h['roi']:11} {h['verdict']}")
    for b in broke:
        print(f"  FALSIFIED {b['roi']:11} {b['verdict']}")
    for a in absent:
        print(f"  ABSENT    {a:11} the run has no successful samples for this ROI; nothing is concluded")
    print(f"E1_PREDICTION_CHECK held={len(held)} falsified={len(broke)} absent={len(absent)}")
    return 0 if (broke or absent) == [] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
