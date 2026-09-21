#!/usr/bin/env python3
"""TEST ENTRY POINT. Not for production use, and deliberately not reachable from the production CLI.

The offline suites need to aim the runner at a fake board: a lock somewhere writable, a boot-id file that
is not `/proc/sys/kernel/random/boot_id`. Those knobs used to be options on `board-runner.py`, which meant
a real `ssh` run could use them too. They live here instead, and this entry point calls exactly the same
`board_run.run()` the production CLI calls, so the tests still exercise the real logic.

The production CLI has no way to reach this file, and this file is the only place the test-only transport
arguments are supplied.
"""
import argparse, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from transport import TransportError                    # noqa: E402
import board_run                                        # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("outdir")
ap.add_argument("--transport-cmd", required=True)
ap.add_argument("--host-binary", required=True)
ap.add_argument("--kernel", required=True)
ap.add_argument("--disk", required=True)
ap.add_argument("--evidence-dir", required=True)
ap.add_argument("--expect", action="append", default=[], metavar="REMOTE_PATH=SHA256")
ap.add_argument("--bitstream-sha", required=True)
ap.add_argument("--stage-timeout", type=float, default=300.0)
ap.add_argument("--startup-timeout", type=float, default=180.0)
ap.add_argument("--stop-timeout", type=float, default=60.0)
# ---- test-only, and only here
ap.add_argument("--channel", choices=("multiplexed", "exclusive"), default="multiplexed")
ap.add_argument("--serial-device", default=None)
ap.add_argument("--remote-lock", required=True, help="TEST ONLY: the fake board's lock path")
ap.add_argument("--remote-boot-id", required=True, help="TEST ONLY: the fake board's boot-id file")
a = ap.parse_args()

try:
    expect = board_run.parse_expect(a.expect)
except ValueError as e:
    print(f"REFUSE: {e}"); print("No host was launched."); sys.exit(2)

try:
    # The SAME build_transport() the production CLI uses, so this entry point cannot accidentally test a
    # construction that production does not perform. The overrides are additive and may only add the
    # test-only lock and boot-id knobs; they cannot replace the channel/device plumbing.
    tp = board_run.build_transport(a, expect, test_overrides=dict(
        remote_lock=a.remote_lock, remote_boot_id=a.remote_boot_id, allow_test_lock=True))
except (TransportError, ValueError) as e:
    print(f"REFUSE: {e}"); print("No host was launched."); sys.exit(2)

sys.exit(board_run.run(a, tp, expect))
