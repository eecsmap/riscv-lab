# Main integration audit — 2026-09-28

Before integration, remote main was `9845da2`, local main `4e7b7a7`, and
the accepted dual archive was `93b8117` (`mc-v1-dual`).

Local main's 33 unpublished commits comprise B0 measurements/checkers/profiles,
E1 build/procedure/safety fixes and failed-run/restore records. Thirty-two were
already ancestors of the dual archive. The common ancestor is `1e4e411`;
the only main-side divergence is `4e7b7a7`, preserving overridable PERF_PROBES
while keeping startup GATES fixed. The merge retains this correction.

Integration uses a separate worktree and a non-squash merge. Before documentation
edits, its tree differs from `mc-v1-dual` only in that five-line E1 library fix.
No CPU RTL, SoC, measurement kernel or benchmark changes are introduced by the
merge. Existing milestones and development history remain intact.

Five pre-existing uncommitted files in the main checkout are excluded and must
remain unchanged: E1 artefacts.sh, gen-markers.sh, markers.tsv,
testbed/recording-board.sh and validate_sample.py. They are not declared reviewed
or published by this integration.

The feature index records current capabilities and future configuration intent;
it does not implement new configuration combinations. No new board/synthesis
validation is claimed. The archived performance records can be rechecked with
the documented commands. The accepted archive's byte-identical software rebuild
remains applicable because its RTL/software sources are unchanged here.
