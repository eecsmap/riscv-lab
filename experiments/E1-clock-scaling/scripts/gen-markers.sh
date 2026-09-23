#!/usr/bin/env bash
# Derive each probe's completion marker from the ELF that will actually be deployed.
#
# Typed markers drift from the binaries. These are read out of the artefacts themselves, so if a probe
# is rebuilt with a different marker the manifest changes with it instead of silently disagreeing.
set -u
R=/home/engineer/fpga
cd "$(dirname "$0")"; . ./lib-e1.sh; . ./artefacts.sh
OUT=${1:-markers.tsv}
: > "$OUT"
for p in $GATES $PERF_PROBES; do
  f=$(elf_path "$p")
  [ -f "$f" ] || { echo "MISSING $p at $f" >&2; exit 1; }
  m=$(strings -a "$f" | grep -oE '^(TEACHING-[A-Z0-9-]+|M3-[A-Z0-9-]+)-OK$' | sort -u | head -1)
  [ -n "$m" ] || { echo "no completion marker found in $f" >&2; exit 1; }
  printf '%s\t%s\t%s\n' "$p" "$m" "$(sha256sum "$f" | cut -d' ' -f1)" >> "$OUT"
done
echo "MARKERS_OK $(wc -l < "$OUT") probes -> $OUT"
