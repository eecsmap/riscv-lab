#!/usr/bin/env python3
"""Drive xv6 on the board. The production entry point.

There are no test switches here, deliberately. Review found `--allow-test-lock` and `--remote-boot-id` on
this CLI, which meant a real `ssh` run could be pointed at a lock that excludes nothing on the actual
board -- the switch that lets a test aim at a fake was equally available to production. The device lock and
the boot-id source are fixed below, and the tests reach the same logic through `_test_runner.py`, which
constructs a transport and calls the same `board_run.run()`.

  board-runner.py <outdir> --transport-cmd 'ssh <board>' --host-binary <remote path>
                  --kernel <remote path> --disk <remote writable copy> --evidence-dir <captured bundle>
                  --expect <remote path>=<sha256> [--expect ...] --bitstream-sha <sha256>
"""
import argparse, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from transport import TransportError                    # noqa: E402
sys.path.insert(0, os.path.join(HERE, '..', '..', 'xv6-boot', 'scripts'))
from xv6_console import profile, UnknownProfile         # noqa: E402
import board_run                                        # noqa: E402

ap = argparse.ArgumentParser()
ap.add_argument("outdir")
ap.add_argument("--transport-cmd", required=True)
# every path below is a path ON THE BOARD
ap.add_argument("--host-binary", required=True)
ap.add_argument("--kernel", required=True)
ap.add_argument("--disk", required=True, help="the per-run WRITABLE copy; the source image stays immutable")
ap.add_argument("--evidence-dir", required=True,
                help="the captured ARM evidence bundle; the preflight is re-run over it here")
ap.add_argument("--expect", action="append", default=[], metavar="REMOTE_PATH=SHA256",
                help="a deployment file and the sha256 approved for it; repeatable, one per role")
ap.add_argument("--bitstream-sha", required=True,
                help="the bitstream programmed into the PL; it is in the fabric and cannot be hashed from "
                     "a file, so it is supplied and recorded verbatim")
ap.add_argument("--channel", choices=("multiplexed", "exclusive"), required=True,
                help="how many things can talk to the board at once. 'exclusive' for a serial console, "
                     "where the host owns the line once it starts; 'multiplexed' for ssh. There is no "
                     "default: getting this wrong is invisible until it is on hardware")
ap.add_argument("--serial-device", default=None,
                help="the console device, for exclusive runs. It is locked for the duration and passed to "
                     "the transport shim, so the owner and the shim are demonstrably the same line")
ap.add_argument("--workload", default="default",
                help="a NAMED workload profile from xv6_console.PROFILES. There is no way to pass an "
                     "arbitrary command: an unknown name is refused before anything is constructed, and "
                     "the default is the accepted four-command workload")
ap.add_argument("--stage-timeout", type=float, default=300.0)
ap.add_argument("--startup-timeout", type=float, default=180.0)
ap.add_argument("--stop-timeout", type=float, default=60.0)
a = ap.parse_args()

# Before the expectations are parsed, before a transport exists, before any lease, lock, remote command or
# host launch: an unknown workload name is a refusal here, not a traceback from inside the command loop.
try:
    profile(a.workload)
except UnknownProfile as e:
    print(f"REFUSE: {e}")
    print("No host was launched.")
    sys.exit(2)

try:
    expect = board_run.parse_expect(a.expect)
except ValueError as e:
    print(f"REFUSE: {e}")
    print("No host was launched.")
    sys.exit(2)

if a.channel == "exclusive" and not a.serial_device:
    print("REFUSE: --channel exclusive needs --serial-device: the console device is what gets locked "
          "against a second opener, and on a serial line a second opener writes into the host's stdin.")
    print("No host was launched.")
    sys.exit(2)

try:
    # The production device lock and the production boot-id source. Not options.
    # build_transport() is shared with the test entry point, so the option-to-constructor mapping cannot
    # drift between them again. It used to be spelled out here, and this is the line that dropped
    # --channel and --serial-device on the floor for the whole of hardware session 2.
    tp = board_run.build_transport(a, expect)
except TransportError as e:
    print(f"REFUSE: {e}")
    print("No host was launched.")
    sys.exit(2)

sys.exit(board_run.run(a, tp, expect))
