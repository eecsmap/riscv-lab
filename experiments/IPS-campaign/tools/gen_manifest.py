#!/usr/bin/env python3
"""Freeze the campaign's identities into manifest.json.

Every hash here is COMPUTED from a file that exists, or copied from a record that states where it was
verified. Nothing is typed from memory and no commit id is invented: if something cannot be resolved it
is recorded as unresolved, with the reason, rather than filled in.

  gen_manifest.py [--out manifest.json]
"""
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))


def _workspace(start):
    """The shared workspace root, found by its own contents.

    ROOT/.. only works when the checkout sits directly under it. This campaign runs in worktrees under
    fpga/worktrees/, where that assumption silently produced a wrong prefix and every probe came back
    unresolved -- which the generator reported rather than hid, but the path was still wrong.
    """
    d = os.path.abspath(start)
    while True:
        if os.path.isdir(os.path.join(d, ".coord")) and \
           os.path.isdir(os.path.join(d, "experiments/teaching-cpu")):
            return d
        up = os.path.dirname(d)
        if up == d:
            raise SystemExit("cannot locate the workspace root (no ancestor has .coord and "
                             "experiments/teaching-cpu)")
        d = up


FPGA = _workspace(ROOT)
PREP = os.path.join(FPGA, "experiments/teaching-cpu/xv6-board-prep")


def sha(path):
    try:
        return hashlib.sha256(open(path, "rb").read()).hexdigest()
    except OSError:
        return None


def entry(path, note=None):
    rel = os.path.relpath(path, FPGA)
    h = sha(path)
    d = dict(path=rel, sha256=h)
    if h is None:
        d["unresolved"] = "file not present at this path"
    if note:
        d["note"] = note
    return d


def git(*args, cwd=ROOT):
    p = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None


def main(argv):
    accepted = json.load(open(os.path.join(ROOT, "experiments/E1-clock-scaling/INPUTS.json")))

    branches = {}
    for name in ("ips-baseline", "ips-fetch32", "ips-tlb", "ips-cache"):
        c = git("rev-parse", name)
        branches[name] = dict(commit=c) if c else dict(
            commit=None, unresolved="branch does not exist yet; it will be recorded when created")

    probes = {}
    for p in ("boot01_marker", "boot02_clint", "boot03_ddr", "boot04_badaddr"):
        probes[p] = entry(os.path.join(PREP, "deploy-bundle", f"{p}.elf"))
    for p in ("ext01_m", "ext02_c", "ext03_a", "ext04_sv39"):
        probes[p] = entry(os.path.join(PREP, "probes/build", f"{p}.elf"))
    for p in ("perf03_fetch", "perf04_where"):
        probes[p] = entry(os.path.join(PREP, "probes/build-perf", f"{p}.elf"))
    for p in ("perf01_cpi", "perf02_sv39", "perf05_size"):
        probes[p] = entry(os.path.join(PREP, "probes/build-perf", f"{p}.elf"),
                          note="in the frozen set only if it is rebuilt or located; see workloads below")

    sources = {p: entry(os.path.join(PREP, "probes", f"{p}.S"))
               for p in ("perf01_cpi", "perf02_sv39", "perf03_fetch", "perf04_where", "perf05_size")}
    for a in ("b0compute", "b0array", "b0file"):
        sources[a] = entry(os.path.join(ROOT, "benchmarks/workloads/src", f"{a}.c"))

    man = dict(
        campaign="IPS-campaign",
        stage="0 — identities and measurement contract",
        created_utc=subprocess.run(["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"],
                                   capture_output=True, text=True).stdout.strip(),
        authorisation="codex-ips-four-stage-campaign",
        clock=dict(hz=40_000_000, source="configured",
                   derivation="125 MHz board oscillator on pin H16 (create_clock -period 8) through an "
                              "MMCM at x8/25. Not measured by any probe.",
                   applies_to="every variant in this campaign; the clock is NOT a variable here"),
        branches=branches,
        accepted_configuration=dict(
            authority="experiments/E1-clock-scaling/INPUTS.json frozen_inputs",
            authority_note="fifteen inputs frozen by hash before this campaign existed, for an "
                           "unrelated purpose. Only the pre-change hashes are used, so nothing here "
                           "depends on E1 having succeeded -- and it did not.",
            verified_by="experiments/IPS-campaign/tools/verify_baseline_identity.py",
            inputs=[dict(path=x["path"], sha256=x["sha256"]) for x in accepted["frozen_inputs"]],
            clocking_vh_accepted=accepted["intended_delta"]["sha256_before"]),
        toolchain=dict(
            riscv_gcc=subprocess.run(["riscv64-linux-gnu-gcc", "--version"],
                                     capture_output=True, text=True).stdout.splitlines()[0],
            python=sys.version.split()[0],
            vivado="vivado v2025.2.1 (64-bit)",
            vivado_note="recorded from E1-clock-scaling/BUILD.json, which read it from its own build "
                        "banner. Each campaign build must record its OWN banner: a tool-version change "
                        "is a documented confound, not an architecture result."),
        board_artifacts=dict(
            bitstream_sha256="2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52",
            raw_payload=entry(os.path.join(FPGA, "experiments/teaching-cpu/xv6-board-run/derived/teaching.bit.bin")),
            host_binary=entry(os.path.join(PREP, "deploy-bundle", "fesvr-teaching-static")),
            xv6_kernel=entry(os.path.join(PREP, "deploy-bundle", "kernel-128mib")),
            b0_disk=dict(
                sha256="6bdd8148b79e5983ecaad04e394327f970e893a4c756a627b7e47da6e31c82ec",
                built_by="riscv-lab/benchmarks/workloads/build-xv6-b0.sh",
                note="not stored in this repo. This hash was VERIFIED ON THE BOARD before each of the "
                     "four samples of the 2026-09-23 application campaign; a fresh copy of the pristine "
                     "image is made per sample."),
            verified_on_board="2026-09-24 restore session: teaching.bit.bin reads 20fae71e…, 8/8 gates"),
        probes=probes,
        sources=sources,
        metrics=dict(
            primary=["delta_instret", "delta_cycle", "cpi = cycles/instret",
                     "ips = instret * 40e6 / cycles", "roi_seconds = cycles / 40e6"],
            counters="core mcycle/minstret (cycle/instret in S-mode), read either side of the ROI. "
                     "They count RETIREMENT, not fetches or offered requests.",
            rejects="zero, invalid or wrapped counter readings are rejected, not repaired",
            simulation="simulation wall speed is NOT CPU IPS and is never reported as such",
            applications="application wall time is a separate end-to-end metric. If trustworthy "
                         "application ROI counters are unavailable, IPS/CPI are null with a reason and "
                         "are never inferred from host waiting time.",
            pooling="simulation and hardware results are never pooled",
            samples=">=3 successful samples per workload/config/platform; every attempt reported; "
                    "median with min/max"),
        stage_status_vocabulary=["IMPLEMENTED", "SIM-VERIFIED", "BUILD-VERIFIED", "BOARD-VERIFIED",
                                 "PERFORMANCE-MEASURED"],
    )
    dest = argv[argv.index("--out") + 1] if "--out" in argv else \
        os.path.join(ROOT, "experiments/IPS-campaign/manifest.json")
    with open(dest, "w") as f:
        json.dump(man, f, indent=2); f.write("\n")
    unresolved = [k for k, v in {**probes, **sources}.items() if v.get("sha256") is None]
    print(f"MANIFEST_OK {os.path.relpath(dest, ROOT)}")
    print(f"  accepted-config inputs frozen : {len(man['accepted_configuration']['inputs'])}")
    print(f"  probes recorded               : {sum(1 for v in probes.values() if v['sha256'])}/{len(probes)}")
    print(f"  sources recorded              : {sum(1 for v in sources.values() if v['sha256'])}/{len(sources)}")
    if unresolved:
        print(f"  UNRESOLVED (recorded as such, not invented): {', '.join(sorted(unresolved))}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
