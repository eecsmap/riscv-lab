#!/usr/bin/env bash
# Apply the reviewed workload-profile delta to the frozen tools, and update provenance HONESTLY.
#
# Codex's ruling: the four current-file hashes may be updated when the reviewed corrected patch is
# applied, but the original manifest must first be preserved verbatim in an explicit historical file,
# recording per changed file its original hash, resulting hash, patch identity and reason. No entry is
# deleted and no file is exempted from hash verification.
#
#   apply-profile-delta.sh --dry-run     show exactly what would change, touch nothing
#   apply-profile-delta.sh --apply       do it
set -u
set -o pipefail
here=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$here/../.." && pwd)
MODE=${1:---dry-run}
PATCHFILE="$here/xv6-workload-profiles.patch"
HIST="$ROOT/provenance-history.json"
FILES="tools/xv6-boot/scripts/xv6_console.py tools/xv6-boot/scripts/check-xv6.py tools/board/scripts/board_run.py tools/board/scripts/board-runner.py"

[ -f "$PATCHFILE" ] || { echo "no patch at $PATCHFILE"; exit 2; }
cd "$ROOT"

echo "== the four files this delta touches"
for f in $FILES; do printf "  %-44s %s\n" "$f" "$(sha256sum $f | cut -c1-16)"; done

if [ "$MODE" = "--dry-run" ]; then
  echo "== dry run: applying to a scratch copy only"
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
  for f in $FILES; do mkdir -p "$tmp/$(dirname $f)"; cp "$f" "$tmp/$f"; done
  patch -p1 -s -d "$tmp" -i "$PATCHFILE" || { echo "  PATCH WOULD FAIL"; exit 1; }
  echo "== resulting hashes, if applied"
  for f in $FILES; do printf "  %-44s %s -> %s\n" "$f" "$(sha256sum $f | cut -c1-16)" "$(sha256sum $tmp/$f | cut -c1-16)"; done
  echo "== provenance entries that would change: $(python3 - "$ROOT" $FILES <<'PY'
import json, sys
root = sys.argv[1]; files = set(sys.argv[2:])
d = json.load(open(root + "/provenance.json"))
print(sum(1 for r in d if r["path"] in files), "of", len(d), "entries")
PY
)"
  echo "DRY_RUN_OK nothing was modified"
  exit 0
fi

[ "$MODE" = "--apply" ] || { echo "usage: --dry-run | --apply"; exit 2; }
[ -e "$HIST" ] && { echo "REFUSE: $HIST already exists; history is written once"; exit 2; }

echo "== preserving the original manifest verbatim before anything changes"
cp "$ROOT/provenance.json" "$ROOT/provenance-original-preimport.json"
python3 - "$ROOT" "$PATCHFILE" $FILES <<'PY'
import hashlib, json, subprocess, sys, pathlib, datetime
root, patchfile = sys.argv[1], sys.argv[2]
files = sys.argv[3:]
R = pathlib.Path(root)
orig = json.loads((R/"provenance.json").read_text())
before = {f: hashlib.sha256((R/f).read_bytes()).hexdigest() for f in files}
commit = subprocess.run(["git","-C",root,"rev-parse","HEAD"],capture_output=True,text=True).stdout.strip()
hist = dict(
  note="Original provenance manifest, preserved verbatim before the workload-profile delta was applied. "
       "Nothing is deleted from provenance.json and no file is exempted from hash verification; this "
       "records what the hashes WERE and why they changed.",
  created=datetime.datetime.now(datetime.timezone.utc).isoformat(),
  authority="codex-review-20260922-decisions, B0 section: provenance decision",
  patch=dict(path="benchmarks/workload-profiles/xv6-workload-profiles.patch",
             sha256=hashlib.sha256(pathlib.Path(patchfile).read_bytes()).hexdigest()),
  applied_at_commit=commit,
  reason="Named workload profiles, so the three B0 application workloads can be driven and checked from "
         "one shared definition in the production path. Default behaviour is unchanged.",
  original_manifest_verbatim=orig,
  changed_files=[dict(path=f, sha256_before=before[f]) for f in files])
(R/"provenance-history.json").write_text(json.dumps(hist, indent=2) + "\n")
print(f"  wrote provenance-history.json with all {len(orig)} original entries verbatim")
PY

echo "== applying"
patch -p1 -s -i "$PATCHFILE" || { echo "  PATCH FAILED -- provenance-history.json written but nothing applied"; exit 1; }

echo "== updating the four hashes, and recording the resulting ones in the history"
python3 - "$ROOT" $FILES <<'PY'
import hashlib, json, pathlib, sys
root = sys.argv[1]; files = sys.argv[2:]
R = pathlib.Path(root)
prov = json.loads((R/"provenance.json").read_text())
hist = json.loads((R/"provenance-history.json").read_text())
after = {}
n = 0
for row in prov:
    if row["path"] in files:
        h = hashlib.sha256((R/row["path"]).read_bytes()).hexdigest()
        after[row["path"]] = h
        row["sha256"] = h
        if "size" in row: row["size"] = (R/row["path"]).stat().st_size
        n += 1
assert n == len(files), f"expected {len(files)} provenance entries, updated {n}"
(R/"provenance.json").write_text(json.dumps(prov, indent=2) + "\n")
for c in hist["changed_files"]:
    c["sha256_after"] = after[c["path"]]
(R/"provenance-history.json").write_text(json.dumps(hist, indent=2) + "\n")
print(f"  updated {n} entries; {len(prov)} total, none removed")
PY
echo "APPLY_OK run 'make check' and 'make bench-selftest' now"
