#!/usr/bin/env python3
"""Parse one raw probe output into structured values, or refuse.

Refusal is the point. A probe's console output can be truncated by a transport, can arrive without its
completion marker, can carry a value the probe itself declared invalid, or can come from a different
probe entirely. Each of those is a distinct failure with a distinct reason, and none of them may quietly
become a number in a results table.

Used by gen_metrics.py; exercised directly by selftest.py.
"""
import json
import re

VALUE_RE = re.compile(r"^([A-Z0-9][A-Z0-9-]*)=([0-9a-fA-F]{16})\s*$")
RC_RE = re.compile(r"^RC=(-?\d+)\s*$")


class ProbeReject(Exception):
    """The record cannot be turned into measurements. Carries the reason."""


def parse(text, workload):
    """text: verbatim probe output. workload: the descriptor dict. Returns a dict of ROI results.

    Raises ProbeReject with a specific reason for anything that is not a complete, self-consistent record.
    """
    lines = [ln.rstrip("\r") for ln in text.splitlines()]

    # 1. the probe's own verdict comes FIRST. This check used to sit after the marker check, where it
    #    was unreachable: a FAIL record has no OK marker, so it was refused as "marker absent" and the
    #    more informative reason -- the probe itself rejected its measurement, most likely because a
    #    window retired the wrong count -- was never reported.
    if re.search(r"TEACHING-[A-Z0-9-]*-FAIL", text):
        raise ProbeReject("the probe reported FAIL: it rejected its own measurement")

    # 2. the marker. Without it the probe did not declare success, whatever else is in the stream.
    if workload["marker"] not in text:
        other = re.findall(r"TEACHING-[A-Z0-9-]*-(?:OK|FAIL)", text)
        raise ProbeReject(
            f"completion marker {workload['marker']!r} absent" +
            (f"; the stream carries {sorted(set(other))} instead" if other else "; no marker of any kind"))

    # 3. the exit status, when the harness recorded one
    rc = None
    for ln in lines:
        m = RC_RE.match(ln.strip())
        if m:
            rc = int(m.group(1))
    if rc is not None and rc != 0:
        raise ProbeReject(f"the probe exited {rc}")

    # 4. the values. Duplicates are refused rather than resolved: two values for one label means two
    #    writers on the channel or two runs in one file, and neither can be silently preferred.
    vals = {}
    for ln in lines:
        m = VALUE_RE.match(ln.strip())
        if not m:
            continue
        label, hexval = m.group(1), m.group(2)
        if label in vals:
            raise ProbeReject(f"label {label!r} appears more than once")
        vals[label] = int(hexval, 16)

    out = {}
    for roi in workload["roi"]:
        for lbl in (roi["cycles_label"], roi["retired_label"]):
            if lbl not in vals:
                raise ProbeReject(f"ROI {roi['name']!r}: label {lbl!r} missing from the record")
        cycles = vals[roi["cycles_label"]]
        retired = vals[roi["retired_label"]]
        if retired != roi["expected_retired"]:
            raise ProbeReject(
                f"ROI {roi['name']!r} retired {retired}, expected {roi['expected_retired']}: the window "
                f"did not run as described, so its cycle count is about some other program")
        if retired == 0:
            raise ProbeReject(f"ROI {roi['name']!r}: zero retired instructions, CPI undefined")
        if cycles == 0:
            raise ProbeReject(f"ROI {roi['name']!r}: zero cycles, which no real window can take")
        if cycles < retired:
            raise ProbeReject(
                f"ROI {roi['name']!r}: {cycles} cycles for {retired} retired instructions is CPI < 1, "
                f"impossible on a multi-cycle core")
        out[roi["name"]] = dict(cycles=cycles, retired=retired, cpi=cycles / retired)

    for ex in workload.get("extra_values", []):
        if ex["label"] in vals:
            out.setdefault("_extra", {})[ex["name"]] = vals[ex["label"]]

    return out


def load_workload(path):
    with open(path) as f:
        return json.load(f)
