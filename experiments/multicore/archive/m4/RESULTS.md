# MC-M4 results

Generated 2026-09-27T17:57:55Z.

## Vivado attempt-1 (dual RD2ZynqTop, 40 MHz)

```
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

| Slice LUTs                 | 22631 |     0 |          0 |     53200 | 42.54 |
| Slice Registers            | 11181 |     0 |          0 |    106400 | 10.51 |
| LUT as Logic                               | 21366 |     0 |          0 |     53200 | 40
| LUT as Memory                              |  1265 |     0 |          0 |     17400 |  7
| Slice Registers                            | 11181 |     0 |          0 |    106400 | 10
| Block RAM Tile |    0 |     0 |          0 |       140 |  0.00 |
| DSPs      |    0 |     0 |          0 |       220 |  0.00 |
| BUFGCTRL   |    1 |     0 |          0 |        32 |  3.13 |

Slack (MET) :             0.396ns  (required time - arrival time)
  Source:                 top/teaching_board_top/target/rd2serial/addr_reg[5]/C
  Destination:            top/teaching_board_top/target/backend/resvValid_0_reg/D
  Data Path Delay:        24.422ns  (logic 10.699ns (43.809%)  route 13.723ns (56.191%))
  Logic Levels:           46  (CARRY4=26 LUT2=1 LUT3=4 LUT4=6 LUT5=4 LUT6=5)

| PDCN-1569 | Warning  | LUT equation term check | 3      |
| RTSTAT-10 | Warning  | No routable loads       | 1      |

             -> PDCN-1569 x3 and RTSTAT-10 x1, all inside system_i/axi_interconnect_1 (the PS AXI protocol converter, baseline block design), identical in rule, count and location to build-cache's DRC; attested by claude 2026-09-27

IMPL_CHECK verdict=PASS
```

## pre-Vivado validators

```
HIERARCHY_CHECK fails=0
   tcpu_core instantiations: 2
   core: {'RESET_PC': '65600', 'MISA_A': '1', 'HART_ID': '0'}
   core: {'RESET_PC': '65600', 'MISA_A': '1', 'HART_ID': '1'}
   HART_ID 0 and 1 present, one each  ok
BOARD_RTL_AUDIT fails=0
# puts "TCL_CHECK fails=$fails"
TCL_CHECK fails=0
```

## deployment smoke (kernel-deploy-4 + fs-deploy, dual FAST sim)

```
sim=/home/engineer/fpga/experiments/multicore/m3/runs/sim-dual/obj_dir/sim (693aaa1e0f8eaae6)
kernel=/home/engineer/fpga/experiments/multicore/m4/sw/out/kernel-deploy-4 (1e4749c0f7c1e7eec77d5d44023b0fec214a32eeec293e356ddeed0e8d802b92)
disk=/home/engineer/fpga/experiments/multicore/m4/sw/out/fs-deploy.img (d8e502693bba1b14625d0f7b9a165f2ece055c64382887cb19610d0db41d7281)
workload=m4smoke max_cycles=2000000000 wall=3600 stage=1800 scheduler=[0x80001e4a,0x80001f00) (plusargs decimal 2147491402 2147491584)
start=2026-09-27T17:20:27Z
XV6_RC=0 wall=2175s
ok	4.1	kernel banner
ok	751.9	init started / first prompt
ok	851.0	shell prompt
ok	1043.4	command b0compute
ok	1309.0	command m3par2
ok	2174.6	command m3fs
HARTS n=2 retired0=24067205 traps0=296 cause0=0x8 maxawait0=253 awaits0=4345626 epoch0=1 retired1=24497990 traps1=342 cause1=0x8 maxawait1=253 awaits1=3848282 epoch1=1
HARTS_USER user0=1259004 range0=611629 user1=3050492 range1=245850
CYCLES total=286728473 host_done_at=286728473 drained=1
INFO harts: retired [24067205, 24497990] user [1259004, 3050492] sched-range [611629, 245850] traps [296, 342]; hart1 user growth steps 7/13
INFO disk: 153 block-device operations, strictly alternating request/completion, closed at EOF
PASS experiments/multicore/m4/runs/smoke-deploy harts={'n': 2, 'retired': [24067205, 24497990], 'traps': [296, 342], 'user': [1259004, 3050492], 'range': [611629, 245850]}
--- program output:
$ b0compute
B0-COMPUTE-CHECKSUM=5ADF55920BF7696
B0-COMPUTE-DONE
$ m3par2
M4-PAR-CHILD0 checksum=f6d983767e3c5638 harts=0x0
M4-PAR-CHILD1 checksum=01d86a21f972f3fa harts=0x0
M4-PAR-DONE children=2 ok=1
$ m3fs
M3-FS-CHILD0 ok=1
M3-FS-CHILD1 ok=1
M3-FS-DONE ok=1
$ Completed after 286728473 cycles
```

## M3 records re-evaluated with the closed disk rules

```
dual-a: PASS e INFO disk: 190 block-device operations, strictly alternating request/completion, closed at EOF
dual-b: PASS e INFO disk: 713 block-device operations, strictly alternating request/completion, closed at EOF
single-a: PASS e INFO disk: 200 block-device operations, strictly alternating request/completion, closed at EOF
single-b: PASS e INFO disk: 713 block-device operations, strictly alternating request/completion, closed at EOF
M3_CHECK_SELFTEST pass=17 fail=0 (experiments/multicore/m3/runs/m3-check-selftest-m4)
```

## deployment bundle

```
c050eab30f80a21a7c92c8688faa2f043c67aa2900fbc08b80f3dd8de2ba1fb9  fesvr-teaching-static
d8e502693bba1b14625d0f7b9a165f2ece055c64382887cb19610d0db41d7281  fs-dual-deploy.img
f2c4410858f1327a5345c705b0a9912cb47bd2f50cd61ecc61aefc41aeca8d2b  fs-dual-valid.img
33021237cf1d82f1500bf7c0d7b8c8a2035a34c81669720fd71b3add75c99fb9  kernel-dual-128mib
a23e4184ab3d1490272e68c0d081e15f2454dcdfcde2f25c14ebd36699d030c6  kernel-dual-valid-4mib
4ecccd051ebfe6143d7706e00a5f080dd53c6d5a29f71526fcaa0533d76e743b  rocketchip_wrapper_dual.bit
43e5b414c093f27854513f6ae08addbb431c6865b85f822685a824cda66e2841  rocketchip_wrapper_dual.bit.bin
```
