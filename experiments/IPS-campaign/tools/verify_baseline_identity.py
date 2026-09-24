#!/usr/bin/env python3
"""Prove the baseline branch reproduces the ACCEPTED 40 MHz CPU configuration.

The campaign's first requirement is that the baseline is the accepted configuration rather than
whatever main happens to hold. That needs an authority outside this campaign, and one exists:
E1-clock-scaling/INPUTS.json froze fifteen inputs by hash in order to change exactly one constant,
so its `frozen_inputs` ARE the accepted configuration, recorded before this campaign existed and for
an unrelated purpose.

`intended_delta.sha256_before` is the accepted `clocking.vh`; `frozen_inputs` carries that same
pre-change hash, so nothing here depends on E1 having succeeded -- and E1 did not.

  verify_baseline_identity.py [--json <out>]
"""
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SRC = os.path.join(ROOT, "experiments/E1-clock-scaling/INPUTS.json")


def main(argv):
    d = json.load(open(SRC))
    delta = d["intended_delta"]
    rows, ok, bad, miss = [], 0, 0, 0
    for x in d["frozen_inputs"]:
        p = os.path.join(ROOT, x["path"])
        if not os.path.exists(p):
            rows.append(dict(path=x["path"], state="MISSING", expected=x["sha256"], actual=None)); miss += 1
            continue
        h = hashlib.sha256(open(p, "rb").read()).hexdigest()
        state = "match" if h == x["sha256"] else "DIFFERS"
        rows.append(dict(path=x["path"], state=state, expected=x["sha256"], actual=h))
        ok, bad = (ok + 1, bad) if state == "match" else (ok, bad + 1)

    # the accepted clocking.vh is the BEFORE side of E1's one change; confirm we are on that side
    cv = next((r for r in rows if r["path"].endswith("clocking.vh")), None)
    clock_state = ("accepted (40 MHz)" if cv and cv["actual"] == delta["sha256_before"] else
                   "E1 (25 MHz)" if cv and cv["actual"] == delta["sha256_after"] else
                   "neither the accepted nor the E1 value")

    res = dict(
        checked=len(rows), match=ok, differs=bad, missing=miss,
        authority=os.path.relpath(SRC, ROOT),
        authority_note="E1's frozen inputs record the accepted configuration by hash, from before this "
                       "campaign and for an unrelated purpose. E1's own outcome is irrelevant here: "
                       "only the pre-change hashes are used.",
        clocking_vh=clock_state,
        verdict="the working tree IS the accepted 40 MHz configuration"
                if (bad == 0 and miss == 0 and clock_state.startswith("accepted"))
                else "the working tree is NOT the accepted configuration",
        inputs=rows)
    if "--json" in argv:
        with open(argv[argv.index("--json") + 1], "w") as f:
            json.dump(res, f, indent=2); f.write("\n")
    for r in rows:
        if r["state"] != "match":
            print(f"  {r['state']:8} {r['path']}")
    print(f"BASELINE_IDENTITY match={ok} differs={bad} missing={miss} of {len(rows)}; "
          f"clocking.vh = {clock_state}")
    print(f"  {res['verdict']}")
    return 0 if res["verdict"].startswith("the working tree IS") else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
