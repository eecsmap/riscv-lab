# R-BOOT write-target review — 2026-09-19

Verdict: accepted for the finite write-target correction and CPU-A closeout. Proceed to isolated teaching xv6 boot (`codex-xv6-teaching-boot`). No synthesis or board acceptance is implied.

Independent checks:

- 227/227 HASHES.txt entries verified.
- Inspected per-tracker request-handshake direction/sector capture, completion clearing, SoC status wiring and host conditions 5/6. The instrumentation does not replace functional DMA/reset control.
- Replayed the delivered A-enabled simulator through the full R-BOOT runner: `codex-gates2/`, job `codex-rwt-review2`, RBOOT_DONE fails=0 infra=0, actual entry exit 0. Eight simulations include the initial-read negative and stuck/late-recovery fail-stop; the missing-READY counterexample is rejected. No independent simulator rebuild this turn.
- Independent g2 log: sector-2 READ accepted at 8538; WRITE accepted at 18951; hold at 18952 with write_inflight=1 and write_sector=2. Restart readback and complete 64-doubleword disk pattern pass.
- Rechecked the fresh read-target negative using --write-target=2: checker exit 1 specifically because hold 8539 has write_inflight=0/read_inflight=1.
- Default/V1 configuration and full SoC/atomic-drain results were archive-reviewed, not independently rerun. Current default/V1 is not the historical build3 binary; recording build3's hash does not mean it was rebuilt with the new trigger. Acceptance is of the current two configurations, not a new historical-build3 equivalence claim.

Nonblocking validation follow-up: the runner exercises the read-target case but does not itself run its log through --write-target=2; the rejection was independently run here. Preserve it as a future permanent self-test. The sector status uses Mux1H over active writes; the present single-write test is in scope, not a general multi-write sector-selection guarantee.

The first registered review launch ended before producing a run after the launching shell exited. It is not counted as evidence. The second registered launch was kept attached through completion; only codex-gates2 is the independent complete replay.

Prior g2 diagnosis has been corrected. No further reset research is required for this task. CPU-A functional acceptance plus the bounded closeout is complete; teaching xv6 has not yet booted and the expanded core has not been synthesized or tested on board.
