# 2026-09-24: I hung the board by reading a PL address

**My error, not a board fault.** Recorded because the rule it produces is worth more than the incident.

## What happened

After the user's recovery power cycle the board came back clean:

```
BOOTID=9ef0d922-3830-4a2e-b921-9a4c09e9f874   (was ebeab8a6-…)
UP=23   N=0   PD=1   FESVR=0   LOCK=NO_LOCK
```

`prog_done=1` at 23 s uptime is not what the documented cold state says — `PRE-STATE.md` expects an
unconfigured fabric after a cold start — so I went to read more registers. That diagnostic command
included:

```
devmem 0x43C00000
```

`0x43C0_0000` is the teaching adapter **inside the PL**. On Zynq, an AXI access to a PL slave that has
no clock or is held in reset does not return an error: it **hangs the CPU on the bus**. The command
never returned, and the console has been unresponsive since.

## The rule

**Never read a PL address until the PL state has been established by the procedure.** Concretely:

* `0x43C0_0000`+ is PL. `0xF800_xxxx` (devcfg, SLCR) is PS and is safe.
* the adapter status is available *without* any `devmem`: every probe prints it on its first line —
  `teaching: ready after 50 ms; status=0x… cpu_restart_safe=1 pl_reconfig_safe=0 …`. That is where
  `record_adapter_status` gets it, and it is the only way it should be read.
* `prog_done=1` is **not** a licence to touch PL addresses. It says a bitstream was loaded; it says
  nothing about whether *this* design is present, clocked, or out of reset.

The E1 scripts never do this — `record_adapter_status` parses probe output and no script issues
`devmem` against PL space. The defect was in an ad-hoc diagnostic I typed, which is exactly where this
kind of thing gets typed.

## On the earlier silence

This is a plausible mechanism for a silent console, and it is **not** evidence for what caused the
2026-09-23 incident. Nothing in that session read a PL address: the reads at 17:05 were
`0xF8007014` and `0xF800700C`, both PS. That cause remains unestablished.

## State now

The board is powered and hung. Nothing was programmed, deployed or cleared. No pin was written, so E1
has not started. Recovery is another physical power cycle.
