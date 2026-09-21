#!/usr/bin/env python3
"""The shared console module and the accepted driver must agree where they overlap.

xv6-drive.py is accepted evidence and is not edited to import PARTIAL_EVENT from here, so the pattern
exists in both places. That is only safe if something checks it.
"""
import os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import xv6_console

drv = open(os.path.join(HERE, "xv6-drive.py")).read()
m = re.search(r"^PARTIAL_EVENT = re\.compile\((r'.*?')\)", drv, re.M)
fails = []
if not m:
    fails.append("xv6-drive.py no longer defines PARTIAL_EVENT where this check looks for it")
else:
    theirs = eval(m.group(1))
    ours = xv6_console.PARTIAL_EVENT_OK.pattern
    print(f"  driver : {theirs}")
    print(f"  shared : {ours}")
    if theirs != ours:
        fails.append("the two PARTIAL_EVENT patterns have drifted apart")

for name in ("EXPECTED", "STAGES", "PROMPT"):
    if not hasattr(xv6_console, name):
        fails.append(f"the shared module no longer exports {name}")

for f in fails: print(f"  FAIL: {f}")
print(f"CONSOLE_SELFTEST fails={len(fails)}")
sys.exit(1 if fails else 0)
