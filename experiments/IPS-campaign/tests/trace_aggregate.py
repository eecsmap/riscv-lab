#!/usr/bin/env python3
"""Stream a simulator's stdout, counting the per-event trace instead of storing all of it.

The SoC harness emits a Chisel printf per REQ/RESP/COMMIT/TRAP and per AXI beat. It is gated only by
PRINTF_COND, which this build defines as always true, so it cannot be turned off without regenerating
the SoC -- and that trace is exactly the observability the later stages need, since the design has no
hardware performance counters for external fetches.

One run of the atomics probe produced 300 MB in thirteen minutes and was still going. So: count every
event, keep every NON-trace line verbatim (that is the probe's own console output and its verdict), and
keep a bounded head and tail of the raw trace for diagnosis. Nothing that carries a verdict is dropped.

  <sim> ... | trace_aggregate.py --out <dir> --keep 2000
"""
import argparse
import collections
import json
import re
import sys

EV = re.compile(r"^(EVA?H?) +(\d+) +(\w+)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--keep", type=int, default=2000, help="raw trace lines kept at each end")
    a = ap.parse_args()

    counts = collections.Counter()
    head, tail = [], collections.deque(maxlen=a.keep)
    console = []
    last_cycle = 0
    total = 0
    for line in sys.stdin:
        m = EV.match(line)
        if m:
            total += 1
            counts[f"{m.group(1)}:{m.group(3)}"] += 1
            try:
                last_cycle = max(last_cycle, int(m.group(2)))
            except ValueError:
                pass
            if len(head) < a.keep:
                head.append(line)
            else:
                tail.append(line)
        else:
            console.append(line)

    with open(f"{a.out}/console.txt", "w") as f:
        f.writelines(console)
    with open(f"{a.out}/trace-head.txt", "w") as f:
        f.writelines(head)
    with open(f"{a.out}/trace-tail.txt", "w") as f:
        f.writelines(tail)
    json.dump(dict(trace_lines=total, last_cycle=last_cycle,
                   events={k: v for k, v in sorted(counts.items())},
                   kept_raw=len(head) + len(tail),
                   note="the full trace is NOT retained: it reaches hundreds of MB per run. Counts are "
                        "exact; the raw head and tail are for diagnosis. Every non-trace line -- the "
                        "probe's own output and its verdict -- is in console.txt verbatim."),
              open(f"{a.out}/trace-counts.json", "w"), indent=2)
    print(f"TRACE_AGGREGATED lines={total} last_cycle={last_cycle} console_lines={len(console)}")


if __name__ == "__main__":
    main()
