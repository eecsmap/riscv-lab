#!/usr/bin/env python3
"""Portable, offline checks. Never connects to a board or claims host locks."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def run(*args):
    subprocess.run([str(x) for x in args], cwd=ROOT, check=True)

def check_imports():
    records = json.loads((ROOT / 'provenance.json').read_text())
    for row in records:
        path = ROOT / row['path']
        if hashlib.sha256(path.read_bytes()).hexdigest() != row['sha256']:
            raise SystemExit(f'Imported snapshot changed: {row["path"]}')
    print(f'IMPORT_HASHES_OK {len(records)}', flush=True)

if __name__ == '__main__':
    check_imports()
    run(sys.executable, 'tools/xv6-boot/scripts/check-xv6.py',
        'evidence/xv6-board-run-3/run-1', '--require-commands')
    run(sys.executable, 'tools/board/scripts/mem-preflight.py',
        'evidence/xv6-board-run-3/evidence-1', '--expect-session',
        'ebeab8a6-0ac9-474a-84c3-bd6e0b357d3b')
    run(sys.executable, 'tools/board/scripts/framing-selftest.py')
    with tempfile.TemporaryDirectory(prefix='riscv-lab-check-') as tmp:
        run(sys.executable, 'tools/board/scripts/transport-selftest.py', Path(tmp)/'transport')
        run('bash', 'tools/board/scripts/mem-preflight-selftest.sh', Path(tmp)/'memory')
    print('RISCV_LAB_CHECK_OK (offline; no hardware run)')
