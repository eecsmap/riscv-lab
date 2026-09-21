# Cold start verified, 2026-09-21T06:33:14+00:00

| signal | session 2 | now | verdict |
| --- | --- | --- | --- |
| USB re-enumeration | ttyUSB0 02:56, ttyUSB1 03:17 | both 06:32 | CHANGED |
| boot id | 50271db5-f010-409d-bfd9-98a367280bc2 | ebeab8a6-0ac9-474a-84c3-bd6e0b357d3b | NEW |
| uptime | - | 22.44 s | fresh |
| /root/xv6run | 12 files | 0 entries | wiped |
| /var/lock/teaching-fesvr.lock | held, corrupted owner | NO_LOCK | gone WITH the power cycle, not cleared by hand |
| fesvr processes | unknown | 0 | none |

The board's clock reads 1970-01-01T00:00:22: no RTC, counting from epoch, which is what a genuine
fresh boot looks like on this platform and corroborates the uptime.

Session 1 boot id was 9e62de9e-f7f1-4cf4-93f0-060bff64ae3b, session 2 was 50271db5-...; this is a
third, distinct one. Session 2's stale lock is gone because the platform lost power, which is the
only permitted way for it to go.
