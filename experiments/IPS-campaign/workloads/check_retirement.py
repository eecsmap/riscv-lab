#!/usr/bin/env python3
"""Derive perf06's expected retirement counts FROM THE DISASSEMBLY, and compare them with the source.

The probe asserts its own retirement count and fails loudly if the window did not run as described.
That assertion is only worth having if the constant is right, and the constant is arithmetic I did by
hand over a shape the assembler is free to change -- a relaxed branch, a macro that expands to two
instructions, an .equ that does not mean what it reads like.

So: count the real instructions between the counter reads, in the real binary.

  check_retirement.py <perf06_iws.dis>
"""
import re
import sys

# the source constants this must agree with
SRC = {"resident": dict(body=32, iters=2000), "exceeds": dict(body=1024, iters=64)}


def instructions(dis, sym):
    m = re.search(rf"^([0-9a-f]+) <{sym}>:$", dis, re.M)
    if not m:
        sys.exit(f"{sym} not found")
    body = dis[m.end():]
    nxt = re.search(r"^[0-9a-f]+ <\w+>:$", body, re.M)
    body = body[:nxt.start()] if nxt else body
    out = []
    for ln in body.splitlines():
        mm = re.match(r"^\s*([0-9a-f]+):\s+[0-9a-f ]+\s+(\S+)", ln)
        if mm:
            out.append((int(mm.group(1), 16), mm.group(2)))
    return out


def analyse(dis, sym, body_n, iters):
    ins = instructions(dis, sym)
    # the measured window runs from the SECOND csrr (instret) to the last csrr, inclusive of both
    # trailing csrr -- the same convention perf03 uses.
    csrrs = [i for i, (_, op) in enumerate(ins) if op.startswith("csrr")]
    if len(csrrs) != 4:
        sys.exit(f"{sym}: expected 4 csrr, found {len(csrrs)}")
    first_end, last_start = csrrs[1], csrrs[2]
    loop = ins[first_end + 1:last_start]           # everything strictly between the reads
    ops = [op for _, op in loop]
    # the loop body repeats; the per-iteration sequence is the whole of `loop`
    per_iter_taken = len(ops)                      # includes addi, beqz, j
    has_j = "jal" in ops or "j" in ops
    if not has_j:
        sys.exit(f"{sym}: no unconditional jump back -- the loop shape is not what the probe assumes")
    # last iteration skips the jump
    total = (iters - 1) * per_iter_taken + (per_iter_taken - 1) + 2
    return dict(per_iteration=per_iter_taken, body_expected=body_n, total=total,
                ops_tail=ops[-3:])


def main(argv):
    dis = open(argv[0]).read()
    bad = 0
    for name, cfg in SRC.items():
        r = analyse(dis, f"measure_{name}", cfg["body"], cfg["iters"])
        formula = cfg["iters"] * (cfg["body"] + 3) + 1
        agree = r["total"] == formula
        bad += 0 if agree else 1
        print(f"  {name:9} per-iteration {r['per_iteration']:5d} instr  (body {cfg['body']} + 3)"
              f"   total {r['total']:8d}")
        print(f"            source constant says {formula:8d}   "
              f"{'agree' if agree else 'DISAGREE -- the probe would fail its own assertion'}")
        print(f"            loop tail: {' '.join(r['ops_tail'])}")
    print(f"PERF06_RETIREMENT ok={2-bad} bad={bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
