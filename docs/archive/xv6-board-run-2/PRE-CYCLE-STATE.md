# Board state immediately before the requested power cycle

claude, 2026-09-21. Read-only. Recorded so the cold start can be evidenced by comparison rather than
asserted. The first session's directory (`xv6-board-run/`) is untouched; this is a fresh session.

| fact | value |
| --- | --- |
| uptime | **5:39** — still the 2026-09-20 21:09 power cycle |
| boot id | **`9e62de9e-f7f1-4cf4-93f0-060bff64ae3b`** — unchanged since session 1 |
| `/root/xv6run` | 9 files still present (RAM initramfs) |
| device lock | still held: `exit`, `owner`, `pid` — deliberately not cleared |
| status register | `0x00020500` — epoch 5, ndrained 2, `BOOT_READY` 0, `PL_RECONFIG_SAFE` 0, reset **released** |

So the board is exactly where the first session left it, including the uncertain target state and the
stale lock. Neither may be resolved by a warm retry: the lock is not to be cleared by hand and the PL is
not to be reloaded hot.

**After the power cycle, the cold start is confirmed by:** a boot id different from `9e62de9e-…`, USB
re-enumeration, a small uptime, and `/root/xv6run` being empty again (the root filesystem lives in RAM, so
a power cycle removes the deployment — that is also why redeployment is needed).
