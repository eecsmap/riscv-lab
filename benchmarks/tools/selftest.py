#!/usr/bin/env python3
"""Negative fixtures for the B0 parser and metric generation.

A results pipeline that only ever sees good input is not known to reject bad input. Each case below is a
way a raw record can be wrong, and each must be refused for its OWN reason -- a parser that rejects
everything is as useless as one that accepts everything, so the positive controls are here too.

  selftest.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from probe_parse import parse, ProbeReject           # noqa: E402

npass = nfail = 0


def ok(w):
    global npass
    npass += 1
    print(f"  ok   : {w}")


def no(w, why):
    global nfail
    nfail += 1
    print(f"  FAIL : {w} -- {why}")


def want(c, w, why=""):
    ok(w) if c else no(w, why)


def rejects(text, wl, label, expect_in):
    try:
        parse(text, wl)
        no(label, "it was accepted")
    except ProbeReject as e:
        want(expect_in in str(e), label, f"refused, but for the wrong reason: {e}")


W = json.load(open(os.path.join(ROOT, "benchmarks/workloads/perf03_fetch.json")))
GOOD = ("FETCH-CYC-32BIT=00000000001275a4\n"
        "FETCH-INS-32BIT=0000000000007532\n"
        "FETCH-CYC-COMPRESSED=000000000009e495\n"
        "FETCH-INS-COMPRESSED=0000000000007532\n"
        "TEACHING-PERF-FETCH-OK\n"
        "RC=0\n")

print("== 0. the positive control: a good record parses, and the numbers are right")
r = parse(GOOD, W)
want(r["insn32"]["cycles"] == 0x1275a4 and r["insn32"]["retired"] == 30002,
     "a complete record yields its values", f"got {r['insn32']}")
want(abs(r["insn32"]["cpi"] - 40.32) < 0.01 and abs(r["insn16"]["cpi"] - 21.61) < 0.01,
     "and the CPIs computed from it", f"got {r['insn32']['cpi']}, {r['insn16']['cpi']}")

print("== 1. missing and truncated records")
rejects(GOOD.replace("FETCH-CYC-COMPRESSED=000000000009e495\n", ""), W,
        "a record missing one of its labels is refused", "missing from the record")
rejects(GOOD.replace("=000000000009e495", "=9e495"), W,
        "a truncated value is refused, not zero-extended", "missing from the record")
rejects(GOOD[:len(GOOD) // 2], W,
        "a record cut off mid-stream is refused", "marker")

print("== 2. the probe's own verdict")
rejects(GOOD.replace("TEACHING-PERF-FETCH-OK", "TEACHING-PERF-FETCH-FAIL"), W,
        "a probe that reported FAIL is refused", "rejected its own measurement")
rejects(GOOD.replace("TEACHING-PERF-FETCH-OK\n", ""), W,
        "a record with no completion marker is refused", "no marker of any kind")

print("== 3. wrong identity: the right shape, the wrong probe")
rejects(GOOD.replace("TEACHING-PERF-FETCH-OK", "TEACHING-PERF-SV39-OK"), W,
        "another probe's marker is not accepted as this one's", "instead")

print("== 4. exit status")
rejects(GOOD.replace("RC=0", "RC=124"), W,
        "a non-zero exit status is refused", "exited 124")

print("== 5. the retired count is the load-bearing check")
rejects(GOOD.replace("FETCH-INS-32BIT=0000000000007532", "FETCH-INS-32BIT=0000000000007533"), W,
        "a window that retired one instruction too many is refused", "did not run as described")
rejects(GOOD.replace("FETCH-INS-32BIT=0000000000007532", "FETCH-INS-32BIT=0000000000000000"), W,
        "zero retired instructions is refused before any division", "did not run as described")

print("== 6. arithmetically impossible records")
rejects(GOOD.replace("FETCH-CYC-32BIT=00000000001275a4", "FETCH-CYC-32BIT=0000000000000000"), W,
        "zero cycles is refused", "zero cycles, which no real window can take")
W2 = json.loads(json.dumps(W))
for roi in W2["roi"]:
    roi["expected_retired"] = 30002
rejects("FETCH-CYC-32BIT=0000000000001000\nFETCH-INS-32BIT=0000000000007532\n"
        "FETCH-CYC-COMPRESSED=000000000009e495\nFETCH-INS-COMPRESSED=0000000000007532\n"
        "TEACHING-PERF-FETCH-OK\n", W2,
        "CPI below 1 is refused on a multi-cycle core", "impossible on a multi-cycle core")

print("== 7. two writers on one channel")
rejects(GOOD + "FETCH-CYC-32BIT=0000000000001111\n", W,
        "a duplicated label is refused rather than resolved", "more than once")

print("== 8. the zero-denominator guard is reachable at all")
WZ = json.loads(json.dumps(W))
WZ["roi"] = [dict(name="z", cycles_label="Z-CYC", retired_label="Z-INS", insns_per_iter=0,
                  expected_retired=0, description="synthetic")]
WZ["marker"] = "M-OK"
rejects("Z-CYC=0000000000000010\nZ-INS=0000000000000000\nM-OK\n", WZ,
        "a ROI whose expected retired count is zero is refused, not divided by", "CPI undefined")

print("== 9. metric generation over a run with a failed sample")
with tempfile.TemporaryDirectory() as td:
    run = os.path.join(td, "run")
    os.makedirs(os.path.join(run, "raw"))
    man = dict(run_id="selftest", platform="simulator", status="reported",
               frequency=dict(hz=40000000, source="configured"),
               sample_policy=dict(min_samples=5))
    json.dump(man, open(os.path.join(run, "manifest.json"), "w"))
    for n, body in ((1, GOOD), (2, GOOD), (3, GOOD.replace("TEACHING-PERF-FETCH-OK",
                                                           "TEACHING-PERF-FETCH-FAIL"))):
        open(os.path.join(run, "raw", f"perf03_fetch.{n}.out"), "w").write(body)
        json.dump(dict(outcome="completed", sample=n), open(os.path.join(run, "raw", f"perf03_fetch.{n}.json"), "w"))
    p = subprocess.run([sys.executable, os.path.join(HERE, "gen_metrics.py"), run],
                       capture_output=True, text=True)
    want(p.returncode == 0, "gen_metrics completes over a run containing a bad sample", p.stderr[-200:])
    m = json.load(open(os.path.join(run, "metrics.json")))
    row = [r for r in m["results"] if r["roi"] == "insn32"][0]
    want(row["samples_successful"] == 2, "the good samples are counted", f"got {row['samples_successful']}")
    want(len(row["failures"]) == 1, "  and the bad one is recorded, not dropped", f"got {row['failures']}")
    want("rejected its own measurement" in row["failures"][0]["reason"],
         "  with the reason it failed for", f"got {row['failures'][0]['reason']}")
    want(row["meets_sample_policy"] is False,
         "  and 2 successes against a policy of 5 is reported as short", "it claimed to meet policy")
    want(row["derived_ips"]["kind"] == "model-derived",
         "  derived IPS is labelled model-derived", "it is not labelled")

print("== 10. a run with NO usable samples yields null, never zero")
with tempfile.TemporaryDirectory() as td:
    run = os.path.join(td, "run")
    os.makedirs(os.path.join(run, "raw"))
    json.dump(dict(run_id="empty", platform="board", status="reported",
                   frequency=dict(hz=40000000, source="configured"),
                   sample_policy=dict(min_samples=5)),
              open(os.path.join(run, "manifest.json"), "w"))
    open(os.path.join(run, "raw", "perf03_fetch.1.out"), "w").write("nothing useful here\n")
    json.dump(dict(outcome="completed", sample=1),
              open(os.path.join(run, "raw", "perf03_fetch.1.json"), "w"))
    subprocess.run([sys.executable, os.path.join(HERE, "gen_metrics.py"), run],
                   capture_output=True, text=True)
    m = json.load(open(os.path.join(run, "metrics.json")))
    row = [r for r in m["results"] if r["roi"] == "insn32"][0]
    want(row["cpi"] is None and row["derived_ips"] is None,
         "a metric with no successful samples is null", f"got cpi={row['cpi']}")
    want(row["samples_successful"] == 0, "  and the success count is zero", "count wrong")

print("== 11. ratios are refused where they would not mean anything")
from gen_comparisons import ratio, ComparisonRefused     # noqa: E402

def R(platform, workload, roi, cpi, hz=40000000):
    return dict(platform=platform, workload=workload, roi=roi, cpi_median=cpi, frequency_hz=hz)

def refuses(a, b, label, expect_in):
    try:
        ratio(a, b)
        no(label, "a ratio was produced")
    except ComparisonRefused as e:
        want(expect_in in str(e), label, f"refused for the wrong reason: {e}")

board32 = R("board", "perf03_fetch", "insn32", 40.32)
board16 = R("board", "perf03_fetch", "insn16", 21.61)
sim32 = R("simulator", "perf03_fetch", "insn32", 19.39)

want(abs(ratio(board16, board32) - 1.8658) < 0.001,
     "a like-for-like ratio is computed", f"got {ratio(board16, board32)}")
refuses(board32, sim32, "a board-against-simulator ratio is refused", "different machines")
refuses(board32, R("board", "perf01_cpi", "store", 46.18),
        "a ratio across different workload shapes is refused", "different workload shapes")
refuses(board32, R("board", "perf03_fetch", "insn32", 40.0, hz=50000000),
        "a ratio across different configured frequencies is refused", "different configured frequencies")
refuses(board32, R("board", "perf03_fetch", "insn32", ""),
        "a ratio against a null metric is refused, not treated as zero", "null, not zero")

print(f"B0_SELFTEST pass={npass} fail={nfail}")
sys.exit(1 if nfail else 0)
