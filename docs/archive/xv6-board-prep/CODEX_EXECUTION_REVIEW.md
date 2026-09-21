# Execution package review — 2026-09-20

Independent mem-preflight selftest14/14 and transport selftest18/18 pass. Scoped parser/transport work recognized; actual board execution not approved.

Source findings: board-runner accepts any nonempty memory-evidence string without checking the bundle/verdict/current remote boot. The local lock is derived from output parent and can be bypassed by another output root. BoardTransport signals/waits only its local subprocess; an SSH remote process can outlive it, so local exit does not prove remote ownership ended. Remote kernel/disk can be recorded as NOT-LOCAL. The proposed no-argument static-host test with PL unconfigured is hardware access, not a safe no-I/O smoke test; main constructs the /dev/mem backend and readiness polling.

Assigned codex-xv6-board-safety-binding for bounded fixes and fake-remote negative tests. Do not execute the unsafe smoke procedure. No new FPGA build or CPU change needed; positive implementation timing and xv6 simulation acceptance stand. Deployment still needs explicit user authority after these gates are genuinely enforced.
