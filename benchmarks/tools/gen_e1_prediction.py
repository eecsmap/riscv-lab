#!/usr/bin/env python3
"""Pre-register what E1 must read, BEFORE E1 is measured.

A two-point model fitted after the fact explains any two points. Writing down first what each ROI must
read at the second frequency, and why, is what makes the measurement able to come out wrong.

Everything here is derived from the 40 MHz board record; nothing is typed in. Three classes of ROI:

  fabric-only   (alu, and the CLINT load) -- never leaves the PL, so the model says its CYCLE count is
                unchanged at any design clock. This is the falsifiable part.
  PS/DDR        (the DRAM load) -- brackets, not a point. Its excess over the CLINT load is either
                entirely fixed time (so it shrinks with the clock) or entirely design-clock cycles (so
                it does not). The measurement lands somewhere in between and that is the result.

  gen_e1_prediction.py [--out experiments/E1-clock-scaling/PREDICTION.json]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "experiments/B0-measurement/runs/2026-09-21-board-s3-b0/metrics.json")
F_HI, F_LO = 40_000_000, 25_000_000
FABRIC_ONLY = ["alu", "load_clint"]
CONTROL = "load_clint"
SUBJECT = "load_dram"


def main(argv):
    m = json.load(open(SRC))
    by = {}
    for r in m["results"]:
        if r["roi"] != "_extra" and r.get("cycles"):
            by.setdefault(r["roi"], r)          # perf01's alu and perf05's agree to 0.008%; take the first
    assert m["frequency"]["hz"] == F_HI, "the source record is not the 40 MHz run"

    preds = []
    for roi in FABRIC_ONLY:
        r = by[roi]; c = r["cycles"]; s = c["max"] - c["min"]
        preds.append(dict(
            roi=roi, kind="fabric-only", workload=r["workload"],
            cycles_at_40mhz=c["median"], observed_spread_at_40mhz=s,
            predicted_cycles_at_25mhz=c["median"],
            tolerance_cycles=s,
            basis="it never leaves the PL, so the model says its cycle count does not depend on the "
                  "design clock. A reading outside the 40 MHz run's own spread falsifies either the "
                  "model or the claim that this ROI stays in the fabric.",
            falsifies_if="the reading differs by more than the 40 MHz spread"))

    ctrl, subj = by[CONTROL]["cycles"], by[SUBJECT]["cycles"]
    excess = subj["median"] - ctrl["median"]
    preds.append(dict(
        roi=SUBJECT, kind="ps-ddr", workload=by[SUBJECT]["workload"],
        cycles_at_40mhz=subj["median"], observed_spread_at_40mhz=subj["max"] - subj["min"],
        excess_over_control_cycles=excess,
        bracket_cycles_at_25mhz=[
            round(ctrl["median"] + excess * F_LO / F_HI),   # all of the excess is fixed TIME
            subj["median"],                                  # all of it is design-clock CYCLES
        ],
        bracket_meaning=dict(
            low="every cycle of the excess is fixed time in the PS/DDR path, so at 25 MHz it costs "
                f"{F_LO/F_HI:.3f} of the cycles it costs at 40 MHz",
            high="none of it is fixed time; the excess is design-clock work and the cycle count is "
                 "unchanged"),
        basis="the DRAM load's excess over the CLINT load is the part that leaves the fabric. The two "
              "ends of the bracket are the two pure hypotheses; the measurement falls between them and "
              "its position IS T_fixed.",
        falsifies_if="the reading falls outside the bracket by more than the two runs' spreads, which "
                     "would mean the excess is neither fixed time nor design-clock work"))

    out = dict(
        pre_registered=True,
        registered_before="any E1 measurement exists; the E1 bitstream has never been on the board",
        generated_from=os.path.relpath(SRC, ROOT),
        source_run=m["run_id"], source_frequency_hz=F_HI, target_frequency_hz=F_LO,
        note="Derived, not typed. If the 40 MHz record changes, regenerate and the prediction changes "
             "with it -- which is why the generator is committed alongside the result.",
        control_roi=CONTROL,
        predictions=preds)
    dest = argv[argv.index("--out") + 1] if "--out" in argv else \
        os.path.join(ROOT, "experiments/E1-clock-scaling/PREDICTION.json")
    with open(dest, "w") as f:
        json.dump(out, f, indent=2); f.write("\n")
    print(f"E1_PREDICTION written to {os.path.relpath(dest, ROOT)}")
    for p in preds:
        if p["kind"] == "fabric-only":
            print(f"  {p['roi']:11} fabric-only : must read {p['predicted_cycles_at_25mhz']:>10,} "
                  f"+/- {p['tolerance_cycles']:,} cycles at 25 MHz")
        else:
            lo, hi = p["bracket_cycles_at_25mhz"]
            print(f"  {p['roi']:11} ps/ddr      : must land in [{lo:,} .. {hi:,}] cycles at 25 MHz")
            print(f"              (excess over the control at 40 MHz: {p['excess_over_control_cycles']:,} cycles)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
