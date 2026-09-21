# Board state before the session, and why a power cycle is needed

claude, 2026-09-20. Read-only. Nothing was deployed, programmed or written to the board.

## What is there

| fact | value | how |
| --- | --- | --- |
| board | Digilent Adept USB, serial **003017B5C772**, console `/dev/ttyUSB1` | `/dev/serial/by-id` |
| ARM Linux | `3.15.0-xilinx-15089-g6fd59febbff1-dirty`, armv7l | `uname -a` |
| uptime | **4 days, 10:25** | `uptime` |
| boot id (current) | `7d2150fa-9d02-4704-9a69-077732aa012f` | `/proc/sys/kernel/random/boot_id` |
| existing host owners | **none** — no `fesvr` process | `ps -eo pid,args` |
| MemTotal | **247 MB** | `free -m` |
| DT `memory/reg` (raw) | `00 00 00 00 10 00 00 00` → base `0x0000_0000`, size `0x1000_0000` (256 MiB) | `od -An -tx1` on the raw property |
| ARM health | clean; `dmesg` tail is boot-time only, nothing logged in four days | `dmesg \| tail` |
| **PL** | **`prog_done = 1` — the fabric is CONFIGURED** | `/sys/devices/amba.1/f8007000.devcfg/prog_done` |

The memory picture is the safe one: Linux holds the low 256 MiB and the target's window
`0x1000_0000–0x1FFF_FFFF` is not Linux's. That is promising, but it is **not** the accepted evidence yet —
that has to be captured after the final cold boot and bound to the boot id it was taken under.

## Why this is a stop

The platform is not cold. It has been up for four days, and the PL still holds whatever the last session
(2026-09-16) left in it. Programming from here is precisely the condition the procedure forbids: a PL
reconfiguration while the fabric may have transactions in flight is what locked the PS until a power cycle
in `m4-board/DIAGNOSIS.md`, and `PL_RECONFIG_SAFE` is the constant `1'h0` in this design for that reason.

A software `reboot` does not fix it: on Zynq the PL stays configured across a PS software restart, so it
would give a fresh boot id over a fabric that was never cleared. The task says so explicitly — "a software
reboot is not evidence of a PL cold start".

**So a physical power cycle is required, and it needs a person.** That is requested rather than worked
around.

## What happens immediately after the power cycle

In this order, and stopping at the first failure:

1. re-read the boot id — it must differ from `7d2150fa-…`, which is how the cold start is evidenced;
2. confirm `prog_done = 0` — an unconfigured fabric;
3. capture the full evidence bundle bound to that new boot id: raw `#address-cells`/`#size-cells`,
   `memory/reg`, every `reserved-memory/*/reg`, `/proc/iomem`, `/proc/meminfo`, ARM health;
4. run `mem-preflight.py --expect-session <new boot id>`;
5. only then deploy, verify remote hashes, and program.
