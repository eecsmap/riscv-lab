# M3 directory map

Nothing here is deleted; this says which directory the accepted result came from and why the others exist.

## The accepted evidence

    m3a-audit/     the ROM audit, from the image bytes, plus the teaching ROM and the script that makes it
    m3a-rtl/       the generated RTL, the ROM rebuilt out of it, and the reset-vector reading
    m3b-boot/      the first working boot chain and the original-ROM negative, as they were first obtained
    m3c-run/       the accepted matrix: four programs x two timing profiles, plus both negatives
    m3c-regress/   the M2-3 gates re-run under these sources
    m3c-rocket/    the Rocket isolation regression: its own ROM, its own simulator, hello.riscv
    ROM_DECISION.md  Codex' ruling that produced the one-instruction teaching ROM

## Superseded builds, kept

`gen-try1` .. `gen-try6` are the elaboration attempts that failed, with their logs: `reset.asBool` against
this Chisel version, `SERIAL_IF_WIDTH` needing `testchipip.SerialAdapter._`, `XLen` living in `tile`, a ROM
path that has to be relative to `simulation/`, and a top-level Module that may only expose io/clock/reset.

`sim-boot` .. `sim-f`, `gen-boot` .. `gen-e` are earlier successful builds, superseded as the harness was
corrected. Two corrections moved between them and are the reason there are so many:

- the subsystem was being held in reset by `sys_reset` alone. That register is not itself reset, so with
  randomised initialisation it could start deasserted and leave the design running on random state before
  anything had reset it; bus monitors then fired at time zero. It is now `sys_reset || reset`.
- the event log printed during reset, and assertion text was printed regardless of whether assertions were
  armed. Printing and stopping are now gated on the same switch, which is armed once the subsystem's reset
  is released.

`sim-TeachingCpu*Config` are the four simulators the accepted matrix used.
