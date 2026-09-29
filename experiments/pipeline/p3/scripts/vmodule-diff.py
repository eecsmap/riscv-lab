#!/usr/bin/env python3
"""Compare two generated Verilog files module by module, after removing scala source locators (`// @[...]` and the
TileLink monitors' `(connected at X.scala:l:c)`), which move whenever a scala file is edited.
  vmodule-diff.py <a.v> <b.v> [--label-a A] [--label-b B]
Prints the modules only in A, only in B, and those in both whose normalized text differs (with changed-line counts),
then VMODULE_DIFF identical=N differing=N only_a=N only_b=N."""
import re, sys, argparse, difflib
ap = argparse.ArgumentParser(); ap.add_argument("a"); ap.add_argument("b")
ap.add_argument("--label-a", default="A"); ap.add_argument("--label-b", default="B"); ap.add_argument("--show", type=int, default=0)
x = ap.parse_args()
def mods(p):
    txt = open(p, errors="replace").read()
    txt = re.sub(r"[ \t]*// @\[[^\]]*\]", "", txt)
    txt = re.sub(r"\(connected at [A-Za-z0-9_]+\.scala:\d+:\d+\)", "(connected at <scala>)", txt)
    out = {}
    for m in re.finditer(r"^module (\w+)\b.*?^endmodule", txt, re.S | re.M): out[m.group(1)] = m.group(0).splitlines()
    return out
A, B = mods(x.a), mods(x.b)
oa = sorted(set(A) - set(B)); ob = sorted(set(B) - set(A)); both = sorted(set(A) & set(B))
diff = [(m, sum(1 for l in difflib.unified_diff(A[m], B[m], lineterm="", n=0) if l[:1] in "+-" and l[:3] not in ("+++", "---"))) for m in both if A[m] != B[m]]
print(f"{x.label_a}: {len(A)} modules; {x.label_b}: {len(B)} modules")
print(f"only in {x.label_a} ({len(oa)}): {' '.join(oa) if oa else '-'}")
print(f"only in {x.label_b} ({len(ob)}): {' '.join(ob) if ob else '-'}")
print(f"in both, differing ({len(diff)}):")
for m, n in diff: print(f"  {m}: {n} changed lines")
for m, _ in diff[:x.show]:
    print(f"--- {m}")
    for l in difflib.unified_diff(A[m], B[m], lineterm="", n=0):
        if l[:3] not in ("+++", "---"): print("  " + l[:200])
print(f"VMODULE_DIFF identical={len(both) - len(diff)} differing={len(diff)} only_a={len(oa)} only_b={len(ob)}")
