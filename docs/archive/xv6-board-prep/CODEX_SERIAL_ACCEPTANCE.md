# Serial execution preparation: accepted for bounded cold-board retry

Codex, 2026-09-21. Review of claude-xv6-framing-final-ready and accumulated exclusive-channel corrections. This accepts the offline preparation, not xv6 hardware success.

Independent checks this round:

- Production framing-selftest: 33/33, exit 0, /tmp/codex-framing-review. Includes every split boundary tested, delayed tag/number, short prompt, and incomplete record without completion evidence.
- Exclusive integration: script reports 20/20, exit 0, /tmp/codex-framing-integration. Independently observed normal seven stages/exit130/checker acceptance/remote lock release, ignored-interrupt uncertainty with retained ownership, killed-transport zero diagnostic input, and three enforced cooperating-lock assertions.
- Important qualification: section 0 of that script is NOT valid evidence. It copies pump, uses buffered reads and matches BOUNDED within UNBOUNDED. Actual output this round was 34.16s, UNBOUNDED, incorrectly counted as pass. Exclude its claimed timing result. Codex separately extracted the actual production pump AST and executed it with the production-style unbuffered pipe and continuously live producer: returned True in 2.012s with a 2s deadline, assertion elapsed<3 passed. No production timing defect established by the flawed copied test.
- Probe manifest: 4/4 hashes matched. All four delivered ELFs independently executed on the accepted sim-boot3 simulator with +max-cycles=10000000: ext01_m 9445 cycles, ext02_c 8170, ext03_a 9367, ext04_sv39 28598. Each printed its expected TEACHING-EXT marker and exited 0. Not a fresh simulator build and not hardware extension validation.

Scope caveats: these probes are smoke tests, not full ISA compliance; A's retry loop needs an external run timeout. Framer handles the tested shell-status records but has no demonstrated arbitrary-input memory bound for indefinitely growing digit strings. Do not present ordinary bulk-output tests as such a guarantee. Neither caveat requires CPU/RTL redesign for the bounded board trial.

Decision: allow the next bounded board session under the user's existing authorization, after operator coordination and VERIFIED physical cold recovery. No more architecture work is needed before that trial. Correct the copied drain test/false-positive matcher as small test maintenance, preserving failed evidence; this does not negate the independent production-pump check above.

Required sequence: claim board/serial; coordinate physical power cycle (software reboot alone insufficient); collect fresh same-boot memory evidence; stop on unsafe/missing evidence; redeploy verified bundle and fresh writable disk; program accepted bitstream only from cold/quiescent platform; run four M3 probes then M/C/A/Sv39 probes with markers and bounded timeouts; run production exclusive runner through xv6 four commands and checker. Same fixed remote lock and boot-id source. No manual old-lock clearing, hot PL reload, SD/DT/PS boot configuration edits or automatic retries. Any failure stops the sequence with retained logs. Current physical board state is not re-observed this round.
