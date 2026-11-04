#!/usr/bin/env python3
"""Check the AXI memory port as a timeline, burst by burst.

An earlier version of this script loaded every AR and AW into its queues before looking at a single R or B,
so a log in which every response sat at cycle 0 -- before the request that asked for it -- still passed, and
B was matched only by comparing sorted ID counts. Causality was not checked at all.

This version walks the events in cycle order. Within one cycle the address and write-data events are applied
before the responses, so a response may legitimately share a cycle with the thing it depends on and the
order the lines happen to be printed in does not matter.

What it holds the port to:
  - an R beat belongs to a read burst whose AR has already happened, on the same ID, in order within that
    ID and freely interleaved across IDs;
  - a burst gets exactly LEN+1 beats, with LAST on the last of them and nowhere else;
  - write data follows AXI4's ordering rule, and may legitimately arrive before its AW, which is buffered;
  - a B belongs to a write burst whose AW has happened and whose write data is complete;
  - responses carry a sane RESP, and nothing is left outstanding at the end.

  check-axi.py <log> [--min-reads=N] [--min-writes=N]
"""
import re, sys
from collections import defaultdict, deque

log = sys.argv[1] if len(sys.argv) > 1 else "/dev/stdin"
opt = dict(a.split("=", 1) for a in sys.argv[2:] if "=" in a)
fails, notes = [], []

by_cycle = defaultdict(lambda: {"a": [], "w": [], "r": []})
n_ar = n_aw = n_r_beats = n_w_beats = n_b = 0
for line in open(log, errors="replace"):
    m = re.search(r"EVA\s+(\d+)\s+(\S+)(.*)", line)
    if not m: continue
    cyc, kind = int(m.group(1)), m.group(2)
    f = {k: int(v, 0) for k, v in re.findall(r"(\w+)=\s*(0x[0-9a-f]+|\d+)", m.group(3))}
    if kind in ("AR", "AW"): by_cycle[cyc]["a"].append((kind, f))
    elif kind == "W":        by_cycle[cyc]["w"].append((kind, f))
    elif kind in ("R", "B"): by_cycle[cyc]["r"].append((kind, f))
    else: fails.append(f"unknown AXI channel {kind} at cycle {cyc}")

if not by_cycle: fails.append("no AXI channel events at all: per-burst closure cannot be checked")

reads = defaultdict(deque)      # id -> deque of [need, got, ar_cycle]
writes = deque()                # AW order: [need, got, aw_cycle, id, done_cycle or None]
w_buffer = deque()              # write beats seen before their AW
b_ready = defaultdict(deque)    # id -> deque of completion cycles, oldest first

def take_w(cyc, last):
    """associate one write beat with the oldest write burst that still needs data"""
    global fails
    for b in writes:
        if b[1] < b[0]:
            b[1] += 1
            if b[1] == b[0]:
                if not last: fails.append(f"write burst opened at cycle {b[2]} ended without LAST")
                b[4] = cyc; b_ready[b[3]].append(cyc)
            elif last:
                fails.append(f"WLAST at cycle {cyc} with {b[0] - b[1]} write beats still owed")
            return True
    return False

for cyc in sorted(by_cycle):
    ev = by_cycle[cyc]
    # 1. address channels: these create the obligations the responses will be matched against
    for kind, f in ev["a"]:
        if "len" not in f or "id" not in f:
            fails.append(f"{kind} at cycle {cyc} is missing id or len"); continue
        if kind == "AR":
            reads[f["id"]].append([f["len"] + 1, 0, cyc]); n_ar += 1
        else:
            writes.append([f["len"] + 1, 0, cyc, f["id"], None]); n_aw += 1
            # write data that arrived early belongs to this burst, in order
            while w_buffer and writes[-1][1] < writes[-1][0]:
                wc, wlast = w_buffer.popleft()
                if not take_w(wc, wlast):
                    fails.append(f"buffered write beat from cycle {wc} could not be placed")
    # 2. write data, which may legitimately precede its AW
    for _, f in ev["w"]:
        n_w_beats += 1
        if not take_w(cyc, f.get("last", 0)):
            w_buffer.append((cyc, f.get("last", 0)))
    # 3. responses, which must find an obligation that already exists
    for kind, f in ev["r"]:
        if kind == "R":
            n_r_beats += 1
            i = f.get("id")
            if i is None: fails.append(f"R at cycle {cyc} has no id"); continue
            q = reads.get(i)
            if not q:
                fails.append(f"R beat at cycle {cyc} for id {i} with no read burst outstanding"); continue
            b = q[0]
            if cyc < b[2]:
                fails.append(f"R beat at cycle {cyc} precedes its AR at cycle {b[2]}"); continue
            b[1] += 1
            last = f.get("last", 0)
            if b[1] == b[0]:
                if not last: fails.append(f"read burst on id {i} opened at {b[2]} ended without LAST")
                q.popleft()
            elif last:
                fails.append(f"RLAST at cycle {cyc} on id {i} with {b[0] - b[1]} beats still owed")
            if f.get("resp", 0) not in (0, 1):
                fails.append(f"R beat at cycle {cyc} carries resp {f['resp']}")
        else:
            n_b += 1
            i = f.get("id")
            if i is None: fails.append(f"B at cycle {cyc} has no id"); continue
            q = b_ready.get(i)
            if not q:
                pend = [b for b in writes if b[3] == i and b[4] is None]
                if pend:
                    fails.append(f"B at cycle {cyc} for id {i} arrives before that burst's write data is complete")
                else:
                    fails.append(f"B at cycle {cyc} for id {i} with no write burst awaiting a response")
                continue
            done = q.popleft()
            if cyc < done:
                fails.append(f"B at cycle {cyc} precedes the completion of its write data at cycle {done}")
            for b in list(writes):
                if b[3] == i and b[4] is not None:
                    writes.remove(b); break
            if f.get("resp", 0) not in (0, 1):
                fails.append(f"B at cycle {cyc} carries resp {f['resp']}")

left_r = {i: len(q) for i, q in reads.items() if q}
if left_r: fails.append(f"read bursts never completed: {left_r}")
if writes: fails.append(f"{len(writes)} write bursts never completed or were never answered")
if w_buffer: fails.append(f"{len(w_buffer)} write beats never belonged to any burst")
leftover_b = {i: len(q) for i, q in b_ready.items() if q}
if leftover_b: fails.append(f"write bursts completed but never answered: {leftover_b}")

minr = int(opt.get("--min-reads", 1)); minw = int(opt.get("--min-writes", 1))
if n_ar < minr: fails.append(f"only {n_ar} read bursts, expected at least {minr}")
if n_aw < minw: fails.append(f"only {n_aw} write bursts, expected at least {minw}")
if n_ar: notes.append(f"{n_ar} read bursts, {n_r_beats} beats, each after its AR, in order within its id")
if n_aw: notes.append(f"{n_aw} write bursts, {n_w_beats} beats, {n_b} responses, each after its data completed")

for n in notes: print("  note:", n)
for f in fails: print("  FAIL:", f)
print(f"AXI_CHECK_DONE fails={len(fails)}")
sys.exit(1 if fails else 0)
