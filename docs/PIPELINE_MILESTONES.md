# Pipeline experiment milestones

Archived 2026-10-01 after the user confirmed their dual-pipeline board trial.
Use immutable tags for comparisons; branches are development pointers.

| Configuration | Reference tag | Development branch |
|---|---|---|
| Multicycle single, I-cache + TLB | `ips-v1-icache` | `ips-cache` |
| Multicycle dual | `mc-v1-dual` | `mc-v1-closeout` |
| Pipeline single | `pipe-v1-single` | `pipe-single` |
| Pipeline dual | `pipe-v1-dual` | `pipe-dual` |

The early single-multicycle tag identifies its feature milestone, not all later
shared-system changes. Consult the recorded input hashes for exact performance
baseline identity; these tags are not four otherwise identical source trees.

## Compare and start an experiment

From the repository:

```sh
git fetch origin --tags
git diff --stat pipe-v1-single pipe-v1-dual
git diff pipe-v1-single pipe-v1-dual -- soc/scala/teaching/RD2Soc.scala
git diff pipe-v1-single pipe-v1-dual -- rtl
git log --reverse --oneline pipe-v1-single..pipe-v1-dual
git worktree add -b experiment/my-next-test ../riscv-my-next-test pipe-v1-dual
```

The RTL diff above is empty: dual pipeline reuses the accepted pipeline core and
multicore backend. Configuration, validation and deployment changed. Do not
switch branches in a checkout another agent or build is using.

## Evidence and reproduction entry points

- [P4a simulation/configuration matrix](../experiments/pipeline/p4a/REPORT.md)
- [P4b 40 MHz build, resources, timing and reproduction](../experiments/pipeline/p4b/REPORT.md)
- [P4c board validation and four-way performance comparison](../experiments/pipeline/p4c/REPORT.md)
- [Dual-pipeline board usage and rollback](../experiments/pipeline/p4c/HANDOFF.md)
- [Single-pipeline board baseline](../experiments/pipeline/p3/board/REPORT.md)

Board delivery commit: `4d723cd`. This archive commit adds documentation only.
Dual-pipeline payload SHA256:
`f330769dac6172da32c3b097ae615d7dde878a9cd2a276835686b1e0de5de7dd`.
Build source: `aa24497`; configuration: `RD2PipeDualBoardConfig`.
Large build products and user disk backups are local artifacts, not guaranteed
to be present in a fresh clone. Follow the reports' build instructions and input
manifests; the tag alone is not a self-contained binary deployment bundle.

At 40 MHz, fixed-work median elapsed times (three samples each):

| Configuration | Compute | Array |
|---|---:|---:|
| Multicycle single | 26.588 s | 40.548 s |
| Multicycle dual | 13.064 s | 20.530 s |
| Pipeline single | 15.829 s | 12.696 s |
| Pipeline dual | 7.951 s | 8.286 s |

Only dual pipeline was newly measured in P4c; the other rows are archived board
results. These are workload throughput comparisons, not IPS. Board evidence does
not include per-hart user instruction retirement counters. All use private
I-cache/TLB and no D-cache; see reports for complete workload/image identities.

## Review scope and remaining limitation

Codex independently rebuilt the dual simulator and passed 11 fast tests, xv6
perf-short and 16 runner selftests. Offline timing and board delivery were reviewed
from reports and artifacts, not independently rerun in Vivado/on the board.
The 65-file P4c session manifest was independently verified; the user subsequently
confirmed their own board trial. Earlier failed attempts remain in the history.

P4c adds a process-name scan and lock checks because legacy long-name `pgrep -x`
host detection misses the running host. Historical deployment library copies are
not globally fixed by this milestone; do not assume their negative pgrep result
proves the host is absent. Use the P4c guarded workflow.
