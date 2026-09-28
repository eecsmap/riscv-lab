#!/usr/bin/env bash
# MC-M1 T1.7 / T1.8: BEFORE against AFTER, program by program.
#
# Fixed, controlled inputs (the same frozen ELFs, the same RTL, the same host) -- so the comparison is:
#   * the verdict marker and the exit code must be equal;
#   * the probe's console (its own output, counters included) must be byte-identical;
#   * where the configuration traced, the COMMIT/TRAP sequence with cycles stripped must be identical --
#     asynchronous timer events are the stated boundary: if only lines around an interrupt differ, that is
#     reported as such rather than hidden or waved through;
#   * the harness's completion cycle count is reported as a delta, never required to be zero.
#
#   compare-probes.sh <before-outdir> <after-outdir>
set -u
B=${1:?before dir}; A=${2:?after dir}
lb=$(ls "$B/runs" | head -1 | sed 's/-.*//'); la=$(ls "$A/runs" | head -1 | sed 's/-.*//')
fails=0
# the inputs the comparison is meant to hold fixed: same programs (the per-run workload builds must
# reproduce byte for byte) and same cpu RTL; a difference here would make every row below meaningless
if cmp -s "$B/elf.sha256" "$A/elf.sha256"; then echo "programs: identical ($(wc -l < "$B/elf.sha256") files)"
else echo "programs: DIFFER between before and after -- comparison invalid"; diff "$B/elf.sha256" "$A/elf.sha256" | head -4; fails=$((fails+1)); fi
rb=$(grep tcpu_core.v "$B/sim/inputs.sha256" | cut -c1-16); ra=$(grep tcpu_core.v "$A/sim/inputs.sha256" | cut -c1-16)
[ "$rb" = "$ra" ] && echo "rtl:      identical (tcpu_core.v $rb)" || { echo "rtl:      DIFFER ($rb vs $ra) -- comparison invalid"; fails=$((fails+1)); }
gb=$(grep -E 'RD2Harness\.' "$B/sim/inputs.sha256" | head -1 | cut -c1-16); ga=$(grep -E 'RD2Harness\.' "$A/sim/inputs.sha256" | head -1 | cut -c1-16)
echo "generated: $gb (before) vs $ga (after) -- the one intended difference"
printf '%-16s %-6s %-8s %-12s %-14s %s\n' program marker exit console commits cycles
for db in "$B"/runs/*/; do
  prog=$(basename "$db"); prog=${prog#$lb-}; da="$A/runs/$la-$prog"
  [ -d "$da" ] || { printf '%-16s %s\n' "$prog" "MISSING in after"; fails=$((fails+1)); continue; }
  # the tracing configuration interleaves the probe's characters with trace lines, so the aggregator's
  # console can carry a marker split across lines: judge the console with newlines removed
  mb=$(tr -d '\n' < "$db/console.txt" 2>/dev/null | grep -oE 'TEACHING-[A-Z0-9-]+-(OK|FAIL)|M3-[A-Z0-9-]+-(OK|FAIL)|PASS' | head -1)
  ma=$(tr -d '\n' < "$da/console.txt" 2>/dev/null | grep -oE 'TEACHING-[A-Z0-9-]+-(OK|FAIL)|M3-[A-Z0-9-]+-(OK|FAIL)|PASS' | head -1)
  eb=$(cat "$db/exit"); ea=$(cat "$da/exit")
  # the probe's own console: drop only the harness's completion line (its cycle count is compared separately)
  cdiff=$(diff <(tr -d '\n' < "$db/console.txt" | sed -E 's/Completed after [0-9]+ cycles//; s/CYCLES total=[0-9]+ host_done_at=[0-9]+//' | fold -w 80) \
               <(tr -d '\n' < "$da/console.txt" | sed -E 's/Completed after [0-9]+ cycles//; s/CYCLES total=[0-9]+ host_done_at=[0-9]+//' | fold -w 80) | grep -c '^[<>]')
  if [ -f "$db/commits.txt" ] && [ -f "$da/commits.txt" ]; then
    nb=$(wc -l < "$db/commits.txt"); na=$(wc -l < "$da/commits.txt")
    kdiff=$(diff "$db/commits.txt" "$da/commits.txt" | grep -c '^[<>]')
    commits="$nb/$na d=$kdiff"
  else commits="(no trace)"; kdiff=0; fi
  cb=$(tr -d '\n' < "$db/console.txt" | grep -oE 'Completed after [0-9]+' | grep -oE '[0-9]+$' | head -1)
  ca=$(tr -d '\n' < "$da/console.txt" | grep -oE 'Completed after [0-9]+' | grep -oE '[0-9]+$' | head -1)
  cyc="${cb:-?}->${ca:-?}"; [ -n "$cb" ] && [ -n "$ca" ] && cyc="$cyc (d=$((ca-cb)))"
  mk="same"; [ "$mb" = "$ma" ] || { mk="DIFF"; fails=$((fails+1)); }
  ex="same"; [ "$eb" = "$ea" ] || { ex="DIFF"; fails=$((fails+1)); }
  co="same"; [ "$cdiff" = 0 ] || { co="DIFF($cdiff)"; fails=$((fails+1)); }
  [ "$kdiff" = 0 ] || fails=$((fails+1))
  printf '%-16s %-6s %-8s %-12s %-14s %s\n' "$prog" "$mk" "$ex" "$co" "$commits" "$cyc"
done
echo "COMPARE fails=$fails  (a non-zero cycle delta is NOT a fail; it is reported for REPORT.md)"
[ $fails = 0 ]
