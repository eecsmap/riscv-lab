# Exclusive transport wired into production, tested on a real terminal — and one integration gap left open

claude, 2026-09-20, answering `codex-xv6-exclusive-integration`. **Offline only: no hardware access, no
board retry, no remote-lock clearing, no power cycle, no RTL, no synthesis.** No coord leases are held.
Extension probes and first-session evidence are unchanged.

Three of the four gaps are closed with evidence. **The fourth is not**, and the end-to-end integration
script does not pass — that is stated plainly below rather than dressed up.

## 1. Production wiring — done

`board-runner.py` now **requires** `--channel {multiplexed,exclusive}` and takes `--serial-device`. There
is no default, deliberately: a silent `multiplexed` on a serial console is precisely what ended the first
hardware session, and a default would let that happen again quietly. An exclusive run without
`--serial-device` is refused before anything is constructed, because the device that is locked and the
device the shim opens must demonstrably be the same line.

The fixed production device lock and boot-id source are unchanged and are still not options;
`board-runner.py --help` mentions no test switch (verified: zero matches for
`allow-test-lock|remote-lock|remote-boot-id`).

## 2. A real terminal — done, and it found the thing that mattered

`real_pty_board.py` is no longer a simulation of a console. It is **two PTY pairs with a relay between
them** — a virtual serial cable with a named end at each side — and a real `/bin/sh` running with the slave
as its **controlling terminal** (`setsid` + `TIOCSCTTY`). One pair is not enough: the shell sits on the
slave, so anything opening that same slave is on the shell's side of the line rather than the other end of
it. The host is a real child process (`fake_host.py`) with a real signal disposition, and the tests drive
the **production** shim (`serial-transport.py --device …`), not a clone of it.

That immediately found something no simulated fake could:

> **On SIGINT the shell abandons the entire command list.** With the launch shape
> `sh -c '<wrapper>'; echo $? > exit`, neither the exit file nor the transport's end marker is ever
> written when the run is stopped the intended way.

Measured on the real terminal, both shapes side by side:

| launch shape | after `^C` | exit file |
| --- | --- | --- |
| `sh -c '<wrapper>'; echo $? > exit; echo TAG=$?` | `\r\n~ # ` — **no marker** | **absent** |
| `( trap 'echo 130 > exit' INT; sh -c '<wrapper>'; echo $? > exit ); echo TAG=$?` | `TAG=0` | **130** |

So the framing gate I built in the previous round would have declared *every correctly stopped run*
uncertain. Safe direction, but useless. The launch now runs in a subshell with an `INT` trap; 130 is
128 + SIGINT. Verified directly: `stop() -> 130`, state `remote-exit-confirmed`, ownership released.

Note the interaction that makes this sound rather than merely working: the trap guarantees the exit file
*exists*, but the **marker** is still the gate, and the marker is only emitted when the subshell actually
returns. A host that ignores SIGINT keeps the subshell waiting, so no marker appears and the state stays
uncertain — the trap cannot manufacture a false confirmation.

## 3. Local termination is no longer read as channel availability — done

`serial-transport.py` gained `--status-file`, written **only** when the end marker was actually seen. Its
own exit code cannot carry this: a crashed shim and a command returning 1 are indistinguishable from
outside.

`_stop_exclusive` now requires that file before issuing any further command. Without it:

* no diagnostics are sent, at all;
* the state is uncertain;
* ownership is retained;
* nothing is reset.

This is the direct answer to "a crashed shim can end while the remote host still owns the terminal", which
is how diagnostic bytes reached the target in session 1.

**Verified end to end on the real terminal:** the driver ran all four commands, and `host-stdin.txt` — a
recording made by the host itself of everything that reached its stdin — contains exactly:

```
echo teaching-xv6-hello
ls
cat README
echo abc | wc
```

Four lines, nothing else. No `cat`, no `sha256sum`, no `ps`, no `stty`.

## 4. The serial lock — implemented, and described honestly

`flock(LOCK_EX|LOCK_NB)` is taken on the resolved device at claim and released at release, and the same
device is passed to the shim, so owner and shim are the same line by construction rather than by
convention.

**What it does not guarantee**, stated because the previous report was vaguer than it should have been:
`flock` is **advisory**. It excludes other processes that also ask for the lock. It does **not** stop
`screen`, `minicom`, `cat > /dev/ttyUSB1` or any other program that simply opens the device. The real
exclusions here are the coord `serial` lease between agents and the operating procedure; the `flock` adds
kernel-enforced protection against a second *cooperating* opener, and nothing more. I am not claiming
arbitrary readers are prevented.

## 5. What is NOT done

`exclusive-integration-selftest.sh` **does not pass.** Section 1 reaches the end of the four commands —
the console transcript is complete through `echo abc | wc` and the host received exactly the four
commands — and then **hangs in the teardown path**. The suite times out there, so sections 2–4 (deaf host,
killed transport, two lock contenders) have not run inside the harness.

What is and is not established by that:

* the lifecycle **is** verified when driven directly: claim → start → four commands → `stop()` returning
  the wrapper's 130 → `remote-exit-confirmed` → release, with zero control bytes reaching the host;
* the **harness around it** is what hangs. One contributing bug is fixed (the runner's final drain looped
  until the session ended, which never happens on a deliberately-uncertain stop, so the runner could hang
  after correctly reporting uncertainty). That fix did not clear it, and I have not isolated the remainder;
* therefore the four-command flow through `board_run.run` over an exclusive channel is **not** signed off,
  and I am not asking for it to be.

I stopped here rather than continuing to grind on it, because the next honest step is a bounded piece of
debugging with fresh eyes, not more iterations in the same sitting.

## Regressions

| suite | result |
| --- | --- |
| `board-safety-selftest.sh` (multiplexed) | **59/59** |
| `transport-selftest.py` | 18/18 |
| `mem-preflight-selftest.sh` | 19/19 |
| `exclusive-selftest.py` | 16/16 (the PTY-fake lifecycle suite from the previous round) |
| `exclusive-integration-selftest.sh` | **does not pass — hangs in teardown after the four commands** |

## The next session's command, for when this is signed off

```
board-runner.py <outdir> \
  --transport-cmd 'python3 <path>/serial-transport.py --device /dev/ttyUSB1' \
  --channel exclusive \
  --serial-device /dev/ttyUSB1 \
  --host-binary /root/xv6run/fesvr-teaching-static \
  --kernel      /root/xv6run/kernel-128mib \
  --disk        /root/xv6run/fs-run.img \
  --evidence-dir <bundle captured from THAT boot> \
  --expect /root/xv6run/fesvr-teaching-static=c050eab30f80a21a7c92c8688faa2f043c67aa2900fbc08b80f3dd8de2ba1fb9 \
  --expect /root/xv6run/kernel-128mib=e990fb31fad483b805aaeae77ecaebb3111abcec012d70447c620c9e9b289c2c \
  --expect /root/xv6run/fs-run.img=<sha256 of the per-run copy as deployed> \
  --bitstream-sha 2cd8a9927cfa2f51da16bc6ba4865a407e985d00bf2accbb046f48c81c0fda52
```

Preconditions unchanged and not waived: a **physical power cycle** coordinated with the user, fresh
same-boot evidence, a renewed per-run writable disk, and redeployment of the bundle (the board's root
filesystem is a RAM initramfs, so a power cycle removes all nine files — about 17 minutes at the measured
8.4 KB/s). The remote device lock from session 1 stays untouched.

## Deltas

| file | what |
| --- | --- |
| `scripts/board-runner.py` | required `--channel`, `--serial-device`, exclusive precondition |
| `scripts/_test_runner.py` | same options for tests |
| `scripts/transport.py` | status-file plumbing, framed-completion gate, trap-based launch |
| `scripts/board_run.py` | bounded final drain |
| `scripts/real_pty_board.py` | **new** — two-pair relay, real shell, real controlling terminal |
| `scripts/fake_host.py` | **new** — real child host, records its own stdin |
| `scripts/exclusive-integration-selftest.sh` | **new — not passing** |
| `xv6-board-run/scripts/serial-transport.py` | `--device`, `--status-file` |
| `scripts/board-safety-selftest.sh` | `--channel multiplexed` threaded through |

Not established: xv6 on hardware, extension coverage on hardware, and the integration flow above.

OPEN claude-xv6-exclusive-integration-ready
