# Porting the console runner to the board: what actually has to change

My board-delta report said the driver and checker were "reusable as-is" with "one change needed, and it is
a one-line addition". That was wrong, and codex was right to reject it. This is the correction: an
inventory of what is simulator-specific, and the adapter that would have to exist. **Nothing here has been
executed against hardware, and none of it is proposed for execution yet.**

## 1. What in `xv6-drive.py` is simulator-only

| line of the invocation | why it does not port |
| --- | --- |
| `subprocess.Popen([sim, ...])` | launches a **local** process. On the board the host binary runs on the ARM, on the other side of a transport. |
| `+max-cycles=6000000000` | a Verilator plusarg. There is no cycle budget on hardware; the equivalent bound is wall-clock. |
| `+rd2_progress=20000000` | a plusarg of the simulator's own main (`rd2_boot_main.cpp`), which is not part of the board host at all. The board's progress evidence is the status word at 0x14, read over AXI. |
| positional `<sim> <elf> <disk>` | the board host takes the ELF through TSI and the disk through `+blkdev=`, but the *simulator* is replaced by a bitstream that must already be loaded — it is not an argument. |
| identity record | the driver records `simulator sha256`. On the board there is no simulator: the identities are the **bitstream**, the **host binary**, and the running **device tree**. |

The console reconstruction, the prompt segmentation, the stage machinery and `check-xv6.py` do port
unchanged, because they only ever look at a byte stream and a stage record. That part of my claim was
right; the process model was not.

## 2. The adapter that would have to exist

A transport object with four operations, so that `xv6-drive.py` stops constructing a `Popen` directly:

```
class Transport:
    def start(self, argv) -> stream     # begin the run, return a byte stream with stdin
    def signal(self, sig)               # ask it to stop
    def wait(self, timeout) -> int      # its exit status
    def identities(self) -> dict        # what this run is made of
```

* `LocalTransport` — today's behaviour, byte for byte, so the simulation path does not change.
* `BoardTransport` — runs `fesvr-teaching +blkdev=... <elf>` **on the ARM** over an authenticated shell
  session, with the board's stdout as the stream. Its `identities()` returns the bitstream hash, the
  `fesvr-teaching` hash, and the device tree's memory node as read **at run time from the running system**,
  not from the repository's DTS.

### Single reader, still

The console is the TSI stream that `fesvr-teaching` prints on the ARM. The transport carries exactly that
one stream. The board's own UART console must **not** be opened at the same time: two readers of the same
target output is precisely the ambiguity the driver's design avoids, and on the board it is easy to do by
accident because a serial terminal is usually already attached. The adapter therefore has to *own* the
session and refuse to start if another reader holds it.

### Shutdown, and what "safe" means on hardware

In simulation a SIGTERM ends the process and the run is over. On the board, stopping the host is not the
end of anything: the design keeps running. The rules that follow from the handshake in `STATUS-MAP.md`:

* the driver stops the host, and does **not** release the restart request as a cleanup action;
* if the host has fail-stopped (exit 2), the design is deliberately left held — that is the safe state and
  the driver must not "recover" it;
* recovery is a cold platform restart. The driver never reloads the PL, and never does so with
  transactions possibly outstanding. `PL_RECONFIG_SAFE` is `1'h0` in the netlist.

## 3. Board records must not be mistakable for simulator records

`stages.txt` gains a platform line and the identity set changes with it:

```
# driver: v3
# platform: board            (or: simulator)
# bitstream sha256: ...      board only
# host binary sha256: ...    board only
# dtb memory node: ...       board only, read from the running system
# simulator sha256: ...      simulator only
# kernel sha256: ...         both
# disk at start sha256: ...  both
```

`check-xv6.py` must require the identity set to match the declared platform, and reject a record that
carries a simulator identity while claiming to be a board run or the reverse. Without that, a board
transcript and a simulation transcript are interchangeable text, and the whole point of the identity
record is that a result names the machine that produced it.

## 4. Status

Specified, not implemented. The implementation is a small amount of work, but it is not a one-line change,
and it should not be written until the transport and the authority to use it have been decided.
