# MC-M4 manifest

Generated 2026-09-27T18:35:43Z.

## Hardware worktree

```
HEAD:  565d33fa604d911dbf591e5187c0e43de57c34b4  (MC-M4: RD2DualBoardConfig (dual-core board shape, no monitors/traces/i)
base:  99b53b1 (MC-M3 accepted); dirty: 0
diff vs 99b53b1:  1 file changed, 22 insertions(+), 4 deletions(-)
RTL set hash: 52ea751de4126fa0 (M1 mc-single-wrapper: 52ea751de4126fa0)
```

## Board RTL and sealed inputs

```
RD2BoardTop.RD2DualBoardConfig.v 273463a2f43c99c8  (wall_s=64 rc=0)
rom_from_rtl.bin f1010b83e5680365  (single-core build: f1010b83e5680365)
shim 6dcbae303a422ca6
--- source-MANIFEST.txt (role, sha16, path):
include    d0fd087a156a3364 teaching-cpu-work/fpga-zynq/pynqz1/src/verilog/clocking.vh
include    4d86ce139119a062 worktrees/mc-dual-xv6/rtl/cpu/tcpu_defs.vh
wrapper    6d0b92b5f5a955a1 teaching-cpu-work/fpga-zynq/pynqz1/src/verilog/rocketchip_wrapper.v
shim       6dcbae303a422ca6 experiments/multicore/m4/build/inputs/teaching_top_shim.v
board-rtl  273463a2f43c99c8 experiments/multicore/m4/gen/gen-RD2DualBoardConfig/RD2BoardTop.RD2DualBoardConfig.v
blackbox   c18ce30820dd61e6 worktrees/mc-dual-xv6/rtl/cpu/tcpu_cacheable.v
blackbox   7ea0ee368aebae35 worktrees/mc-dual-xv6/rtl/cpu/tcpu_cdecode.v
blackbox   66fa67036efd3ef0 worktrees/mc-dual-xv6/rtl/cpu/tcpu_core.v
blackbox   51d725aaf8987a50 worktrees/mc-dual-xv6/rtl/cpu/tcpu_csr.v
blackbox   8832ef6d5f33b35e worktrees/mc-dual-xv6/rtl/cpu/tcpu_icache.v
blackbox   50ce699fcd5d2ea6 worktrees/mc-dual-xv6/rtl/cpu/tcpu_ifill.v
blackbox   5e85de1d474ad63f worktrees/mc-dual-xv6/rtl/cpu/tcpu_muldiv.v
blackbox   b6668bc2ce57c6fe worktrees/mc-dual-xv6/rtl/cpu/tcpu_permcheck.v
blackbox   ded150649edab04a worktrees/mc-dual-xv6/rtl/cpu/tcpu_ptw.v
blackbox   40334e9cf0c7a247 worktrees/mc-dual-xv6/rtl/cpu/tcpu_regfile.v
blackbox   c275f8f6abe1a92d worktrees/mc-dual-xv6/rtl/cpu/tcpu_tlb.v
blackbox   7a8398e13f7351f1 worktrees/mc-dual-xv6/rtl/cpu/tcpu_xlate.v
support    90af647728313f1a teaching-cpu-work/fpga-zynq/pynqz1/src/verilog/AsyncResetReg.v
support    5afcca017b4a6ca8 teaching-cpu-work/fpga-zynq/pynqz1/src/verilog/plusarg_reader.v
xdc        b9a05afdf3edfa1d teaching-cpu-work/fpga-zynq/pynqz1/src/constrs/base.xdc
bd-tcl     e50dbbea52f8e2cf teaching-cpu-work/fpga-zynq/pynqz1/src/tcl/pynqz1_bd.tcl
--- tooling-hashes.txt:
13aa318bec689842 experiments/multicore/m4/tests/build-board.sh
243a14890c80944a experiments/multicore/m4/tools/board-build/check-hierarchy-atomic.py
36b5d6703696658b experiments/multicore/m4/tools/board-build/audit-board-rtl-atomic.py
41c0e4bdcbf00ebb experiments/multicore/m4/tools/board-build/make-build-manifest-m4.py
ee29832944e6cda9 experiments/multicore/m4/tools/board-build/make-top-shim-atomic.py
60d5a609ca6a9f03 experiments/teaching-cpu/m4-prep/scripts/gen-project-tcl.py
12f73265e871b1e4 experiments/teaching-cpu/m4-prep/scripts/check-tcl.tcl
32fea9e55c89fc06 experiments/teaching-cpu/m4-build/run_impl.tcl
```

## Vivado

```
date: 2026-09-27T17:24:13Z
image: vivado-env:2025.2
jobs: 4
host nproc: 12
vivado v2025.2.1 (64-bit)
Tool Version Limit: 2025.11
tool: 2025.2.1
part: xc7z020clg400-1
synth_1 STATUS: synth_design Complete!
synth_1 PROGRESS: 100%
impl_1 STATUS: write_bitstream Complete!
impl_1 PROGRESS: 100%
WNS: 0.396295
TNS: 0.000000
WHS: 0.035343
THS: 0.000000
bitstream: /home/engineer/fpga/experiments/multicore/m4/build/attempt-1/reports/rocketchip_wrapper.bit
impl wall: wall=667s
bitstream sha256: 4ecccd051ebfe6143d7706e00a5f080dd53c6d5a29f71526fcaa0533d76e743b
```

## Software (sw/out/sha256.txt)

```
33021237cf1d82f1 kernel-deploy-128
0e57f951988188e5 kernel-deploy-128.syms
1e4749c0f7c1e7ee kernel-deploy-4
a23e4184ab3d1490 kernel-valid-4
d8e502693bba1b14 fs-deploy.img
f2c4410858f1327a fs-valid.img
diff vs the M3 tree: sw/out/xv6-m3-to-m4.patch (7 files, 1 new, 25 lines)
```

## Deployment bundle (deploy/MANIFEST.sha256)

```
dc54edefc5845888c5face751772f1f285515ee03ca1177addeb51d54ca56972  README.md
c050eab30f80a21a7c92c8688faa2f043c67aa2900fbc08b80f3dd8de2ba1fb9  fesvr-teaching-static
d8e502693bba1b14625d0f7b9a165f2ece055c64382887cb19610d0db41d7281  fs-dual-deploy.img
f2c4410858f1327a5345c705b0a9912cb47bd2f50cd61ecc61aefc41aeca8d2b  fs-dual-valid.img
33021237cf1d82f1500bf7c0d7b8c8a2035a34c81669720fd71b3add75c99fb9  kernel-dual-128mib
a23e4184ab3d1490272e68c0d081e15f2454dcdfcde2f25c14ebd36699d030c6  kernel-dual-valid-4mib
4ecccd051ebfe6143d7706e00a5f080dd53c6d5a29f71526fcaa0533d76e743b  rocketchip_wrapper_dual.bit
43e5b414c093f27854513f6ae08addbb431c6865b85f822685a824cda66e2841  rocketchip_wrapper_dual.bit.bin
```

## Judges / tools

```
13aa318bec6898426fac4d210a52898d8ae3a0faf21949fd18fff36708154976  build-board.sh
c70836c1b1a4aaacc6896ca8544a98f404bb3470d87dd9abf2d32ee1311db390  build-sw.sh
297526e3d13e0b98fb6b31adc51931590055a895d4d9736bea376f50960d329c  run-xv6.sh
d39b760a3e07a67d75ff6317b8b4fabf3e79a3c9e87831da6012c96e39883c8c  m3_check.py
36b5d6703696658b87321b32c6882a97e6e9f31134562e390f42928ae8faa8f4  audit-board-rtl-atomic.py
243a14890c80944a0c0fca258921db938d373bca22fa0c844df2a23659d7b165  check-hierarchy-atomic.py
41c0e4bdcbf00ebbed8b0e9089ce2730c3bff28e59303db5e179c9eaf27b2b9f  make-build-manifest-m4.py
ee29832944e6cda905529789a20869ef6f30be5754962c758b6404313ebe4998  make-top-shim-atomic.py
6c87e360e81f3919e03da8cbb21ceafe96ca7ba00ebb129ad827c215d9a9ac10  xv6_console.py
97fd56af4dfb84c5d87ee3c2d2a2910658091e72d791fee54e47d296557880f3  check-xv6.py
bit2bin.py dc4b7b921b5ac417  check-impl-reports.py da1dd900cf1ab9ef  run_impl.tcl 32fea9e55c89fc06
```
