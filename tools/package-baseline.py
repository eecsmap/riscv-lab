#!/usr/bin/env python3
"""One-time archive import from the original workspace; never rebuilds approved ELF files.

Usage: python3 tools/package-baseline.py /path/to/original/fpga/workspace
The original workspace is needed only to assemble the initial release, not to use it.
"""
from pathlib import Path
import hashlib
import shutil
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(sys.argv[1]).resolve()
OUT = ROOT/'release'
OUT.mkdir(exist_ok=True)
name = 'riscv-lab-v0.1.0-xv6-boot-pynq-z1'
stage = OUT/name
stage.mkdir(exist_ok=False)
records = []

def add(path, target, digest):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != digest:
        raise SystemExit(f'Artifact mismatch: {path}')
    shutil.copy2(path, stage/target)
    records.append(f'{digest}  {target}')

base = SOURCE/'experiments/teaching-cpu/xv6-board-prep'
for directory, manifest in [(base/'deploy-bundle', 'MANIFEST.sha256'),
                            (base/'probes/build', 'probes.sha256')]:
    for line in (directory/manifest).read_text().splitlines():
        digest, filename = line.split()
        add(directory/filename, filename, digest)
add(SOURCE/'experiments/teaching-cpu/xv6-board-run/derived/teaching.bit.bin',
    'teaching.bit.bin', '20fae71e4661c6c93a9826397594e058ef4bf6dc01071a41809ebb3a312c9f5a')
shutil.copytree(ROOT/'licenses', stage/'licenses')
shutil.copy2(ROOT/'software/xv6/LICENSE', stage/'licenses/xv6-LICENSE')
shutil.copy2(ROOT/'docs/BOARD.md', stage/'BOARD.md')
shutil.copy2(ROOT/'docs/RELEASE.md', stage/'README.md')
(stage/'MANIFEST.sha256').write_text('\n'.join(records)+'\n')
archive = OUT/(name+'.tar.gz')
with tarfile.open(archive, 'w:gz') as tar:
    tar.add(stage, arcname=name)
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
(OUT/'SHA256SUMS').write_text(f'{digest}  {archive.name}\n')
print(f'PACKAGED {len(records)} original artifacts: {archive}')
