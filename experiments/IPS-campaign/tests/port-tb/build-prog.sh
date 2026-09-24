#!/usr/bin/env bash
# Assemble the port testbench program and emit a byte-per-line hex image for $readmemh.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?outdir}
mkdir -p $OUT
CC=riscv64-unknown-elf-gcc
$CC -mabi=lp64 -mcmodel=medany -march=rv64ic_zicsr -nostdlib -nostartfiles -ffreestanding -O0 \
    -Wl,-Ttext=0x1000 -Wl,--section-start=.data=0x4000 -o $OUT/prog.elf $HERE/opt01_port_prog.S || exit 1
riscv64-unknown-elf-objcopy -O binary --gap-fill 0 $OUT/prog.elf $OUT/prog.bin || exit 1
python3 - "$OUT/prog.bin" "$OUT/prog.hex" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
with open(sys.argv[2], 'w') as f:
    for b in data:
        f.write(f"{b:02x}\n")
print(f"PROG_HEX_OK {len(data)} bytes")
PY
