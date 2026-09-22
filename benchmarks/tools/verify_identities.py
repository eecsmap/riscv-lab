#!/usr/bin/env python3
"""Check B0's measurement identities, and say plainly which ones cannot be checked offline.

Codex's B0 review is blocked on measurement-identity acceptance, and until now nothing in the tree would
do that check or even enumerate what is checkable. This does both: it verifies every identity it can
reach from inside the repository, and lists the rest with the reason they are out of reach, so the gap is
a stated fact rather than something a reviewer has to discover.

It also fails on a structural gap this found: a workload with samples but no recorded ELF identity.

  verify_identities.py
"""
import glob
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
RELEASE = os.path.join(ROOT, "release/riscv-lab-v0.1.0-xv6-boot-pynq-z1")

npass = nfail = 0
unchecked = []


def ok(w):
    global npass
    npass += 1
    print(f"  ok       : {w}")


def no(w, why):
    global nfail
    nfail += 1
    print(f"  FAIL     : {w} -- {why}")


def skip(w, why):
    unchecked.append((w, why))
    print(f"  unchecked: {w} -- {why}")


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(65536), b""):
            h.update(b)
    return h.hexdigest()


def check_against(label, claimed, path):
    if not os.path.exists(path):
        skip(label, f"no copy of this artefact in the repository ({os.path.relpath(path, ROOT)})")
        return
    got = sha(path)
    if got == claimed:
        ok(f"{label} matches the repository's copy")
    else:
        no(f"{label} matches the repository's copy", f"claimed {claimed[:16]}…, file is {got[:16]}…")


print("== identities claimed by each run, checked where the artefact is in the repository")
for mpath in sorted(glob.glob(os.path.join(ROOT, "experiments/B0-measurement/runs/*/manifest.json"))):
    man = json.load(open(mpath))
    rid = man["run_id"]
    art = man.get("artifacts") or {}
    print(f"\n-- {rid} ({man['platform']})")

    if art.get("bitstream_sha256"):
        check_against(f"{rid}: bitstream", art["bitstream_sha256"],
                      os.path.join(RELEASE, "rocketchip_wrapper.bit"))
    if art.get("host_binary_sha256"):
        check_against(f"{rid}: host binary", art["host_binary_sha256"],
                      os.path.join(RELEASE, "fesvr-teaching-static"))
    if art.get("bitstream_bin_sha256"):
        check_against(f"{rid}: bitstream raw payload", art["bitstream_bin_sha256"],
                      os.path.join(RELEASE, "teaching.bit.bin"))
    if art.get("simulator_sha256"):
        skip(f"{rid}: simulator binary",
             "the simulator is a build artefact outside the repository; its own inputs.sha256 and "
             "tool banner are recorded in the manifest instead")

    # the structural check: every workload with samples must have a recorded ELF identity
    metrics = os.path.join(os.path.dirname(mpath), "metrics.json")
    if os.path.exists(metrics):
        sampled = {r["workload"] for r in json.load(open(metrics))["results"]
                   if r["samples_successful"]}
        named = {k.rsplit(".elf", 1)[0] for k in (art.get("probe_elf_sha256") or {})}
        missing = sampled - named
        if missing:
            no(f"{rid}: every sampled workload has a recorded ELF identity",
               f"no ELF hash for {sorted(missing)} despite samples existing")
        elif sampled:
            ok(f"{rid}: all {len(sampled)} sampled workloads have a recorded ELF identity")
    for name in sorted(art.get("probe_elf_sha256") or {}):
        skip(f"{rid}: probe {name}",
             "probe ELFs are build artefacts and are not committed; the source and its hash are in "
             "benchmarks/workloads/")

print("\n== workload sources, which ARE in the repository")
for wpath in sorted(glob.glob(os.path.join(ROOT, "benchmarks/workloads/*.json"))):
    w = json.load(open(wpath))
    src = os.path.join(ROOT, w["source"])
    check_against(f"workload {w['id']} source", w["source_sha256"], src)

print(f"\nIDENTITY_CHECK pass={npass} fail={nfail} unchecked={len(unchecked)}")
if unchecked:
    print("  Unchecked items are listed above with the reason. They are NOT failures and they are NOT")
    print("  verifications: an identity that cannot be checked from here has to be checked elsewhere.")
sys.exit(1 if nfail else 0)
