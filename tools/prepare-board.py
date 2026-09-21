#!/usr/bin/env python3
"""Resolve and verify frozen inputs, then emit Tcl. Does not launch Vivado."""
from pathlib import Path
import hashlib
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
build = ROOT / 'build'
build.mkdir(exist_ok=True)
rows = []
for line in (ROOT/'boards/pynq-z1/inputs.tsv').read_text().splitlines():
    if not line or line.startswith('#'):
        continue
    role, digest, size, relative, *note = line.split('\t')
    path = ROOT / relative
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != digest or len(data) != int(size):
        raise SystemExit(f'Frozen input mismatch: {relative}')
    rows.append('\t'.join([role, digest, size, str(path), *note]))
manifest = build/'board-inputs.tsv'
manifest.write_text('\n'.join(rows)+'\n')
subprocess.run([sys.executable, str(ROOT/'tools/gen-project-tcl.py'), str(manifest),
                str(build/'project.tcl'), '--project-dir', str(build/'vivado-project'),
                '--board-repo', str(ROOT/'boards/pynq-z1/board_files')], check=True)
print('Prepared project only. Vivado synthesis and implementation NOT run.')
