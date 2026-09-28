# MC-M3 results

Generated 2026-09-27T12:08:04Z. Sources: `runs/<run>/{verdict.txt,cmd.txt,run/stages.txt,run/console.txt}`, `<run>.check`.

## dual-a

```
sim=/home/engineer/fpga/experiments/multicore/m3/runs/sim-dual/obj_dir/sim (693aaa1e0f8eaae6)
kernel=/home/engineer/fpga/experiments/multicore/m3/sw/out/kernel-prod (df05b6e462398f6dc44aa7ffb5db976b4874c3b29bf2f43844daa499c449ae8c)
disk=/home/engineer/fpga/experiments/multicore/m3/sw/out/fs-prod.img (cbb031e5994efbceb7e0b51f4e93306ae4db680813521eb522318c96d156caa6)
workload=m3dual-a max_cycles=2000000000 wall=5400 stage=3000 scheduler=[0x80001e4e,0x80001f12) (plusargs decimal 2147491406 2147491602)
start=2026-09-27T07:12:44Z
--- verdict: XV6_RC=0 wall=3504s
--- stages:
ok	4.2	kernel banner
ok	708.4	init started / first prompt
ok	798.0	shell prompt
ok	986.6	command b0compute
ok	1217.7	command b0array
ok	1652.1	command forktest
ok	1969.0	command m3par
ok	2208.6	command m3migrate
ok	2605.9	command m3exec
ok	3502.5	command m3fs
# workload: m3dual-a
# kernel sha256: df05b6e462398f6dc44aa7ffb5db976b4874c3b29bf2f43844daa499c449ae8c
# host exit: 0
# stop: deliberate-stop-after-all-commands
--- host lines:
AXI ar=18788645 r=18797941 rlast=18788645 aw=10987624 w=10999608 wlast=10987624 b=10987624
RD2HOST FINAL aWaits=13878561 aFires=23245713 dFires=23245713 epoch=1 injections=0 boot_ready=0 boot_timeout=0 bdev_queued=0
HARTS n=2 retired0=40476625 traps0=755 cause0=0x8 maxawait0=253 awaits0=7106443 epoch0=1 retired1=41293239 traps1=939 cause1=0x8 maxawait1=253 awaits1=6772118 epoch1=1
HARTS_USER user0=1840192 range0=1044007 user1=7170264 range1=429786
CYCLES total=477276309 host_done_at=477276309 drained=1
--- judge (m3_check.py):
INFO harts: retired [40476625, 41293239] user [1840192, 7170264] sched-range [1044007, 429786] traps [755, 939]; hart1 user growth steps 18/22
INFO disk: 190 block-device operations, strictly alternating request/completion
INFO m3par: children on harts 0x3 and 0x3
INFO m3migrate: harts 0x3 natural=0 pinned_ok=1 exec_ok=1
PASS /home/engineer/fpga/experiments/multicore/m3/runs/dual-a harts={'n': 2, 'retired': [40476625, 41293239], 'traps': [755, 939], 'user': [1840192, 7170264], 'range': [1044007, 429786]}
```

## dual-b

```
sim=/home/engineer/fpga/experiments/multicore/m3/runs/sim-dual/obj_dir/sim (693aaa1e0f8eaae6)
kernel=/home/engineer/fpga/experiments/multicore/m3/sw/out/kernel-prod (df05b6e462398f6dc44aa7ffb5db976b4874c3b29bf2f43844daa499c449ae8c)
disk=/home/engineer/fpga/experiments/multicore/m3/sw/out/fs-prod.img (cbb031e5994efbceb7e0b51f4e93306ae4db680813521eb522318c96d156caa6)
workload=m3dual-b max_cycles=2000000000 wall=5400 stage=3000 scheduler=[0x80001e4e,0x80001f12) (plusargs decimal 2147491406 2147491602)
start=2026-09-27T08:53:16Z
--- verdict: XV6_RC=0 wall=4740s
--- stages:
ok	4.2	kernel banner
ok	718.2	init started / first prompt
ok	809.5	shell prompt
ok	2471.8	command ut-exec
ok	4738.6	command b0file
# workload: m3dual-b
# kernel sha256: df05b6e462398f6dc44aa7ffb5db976b4874c3b29bf2f43844daa499c449ae8c
# host exit: 0
# stop: deliberate-stop-after-all-commands
--- host lines:
AXI ar=26198958 r=26260670 rlast=26198958 aw=15830726 w=15848870 wlast=15830726 b=15830726
RD2HOST FINAL aWaits=20676728 aFires=34188430 dFires=34188430 epoch=1 injections=0 boot_ready=0 boot_timeout=0 bdev_queued=0
HARTS n=2 retired0=54522469 traps0=560 cause0=0x8 maxawait0=256 awaits0=10499110 epoch0=1 retired1=54548903 traps1=2433 cause1=0x8 maxawait1=248 awaits1=10177618 epoch1=1
HARTS_USER user0=204330 range0=1678363 user1=321583 range1=686191
CYCLES total=631730197 host_done_at=631730197 drained=1
--- judge (m3_check.py):
INFO harts: retired [54522469, 54548903] user [204330, 321583] sched-range [1678363, 686191] traps [560, 2433]; hart1 user growth steps 27/30
INFO disk: 713 block-device operations, strictly alternating request/completion
PASS experiments/multicore/m3/runs/dual-b harts={'n': 2, 'retired': [54522469, 54548903], 'traps': [560, 2433], 'user': [204330, 321583], 'range': [1678363, 686191]}
```

## single-a

```
sim=/home/engineer/fpga/experiments/multicore/m3/runs/sim-single/obj_dir/sim (d7ecb822bff087a7)
kernel=/home/engineer/fpga/experiments/multicore/m3/sw/out/kernel-prod (df05b6e462398f6dc44aa7ffb5db976b4874c3b29bf2f43844daa499c449ae8c)
disk=/home/engineer/fpga/experiments/multicore/m3/sw/out/fs-prod.img (cbb031e5994efbceb7e0b51f4e93306ae4db680813521eb522318c96d156caa6)
workload=m3dual-a max_cycles=2000000000 wall=5400 stage=3000 scheduler=[0x80001e4e,0x80001f12) (plusargs decimal 2147491406 2147491602)
start=2026-09-27T10:12:16Z
--- verdict: XV6_RC=0 wall=3216s
--- stages:
ok	4.1	kernel banner
ok	553.7	init started / first prompt
ok	625.3	shell prompt
ok	781.8	command b0compute
ok	970.6	command b0array
ok	1396.1	command forktest
ok	1840.0	command m3par
ok	2022.0	command m3migrate
ok	2345.6	command m3exec
ok	3215.1	command m3fs
# workload: m3dual-a
# kernel sha256: df05b6e462398f6dc44aa7ffb5db976b4874c3b29bf2f43844daa499c449ae8c
# host exit: 0
# stop: deliberate-stop-after-all-commands
--- host lines:
AXI ar=13749294 r=13759934 rlast=13749294 aw=6039333 w=6051093 wlast=6039333 b=6039333
RD2HOST FINAL aWaits=2241422 aFires=13315426 dFires=13315426 epoch=1 injections=0 boot_ready=0 boot_timeout=0 bdev_queued=0
HARTS n=1 retired0=48457826 traps0=1368 cause0=0x8 maxawait0=240 awaits0=2241422 epoch0=1 retired1=0 traps1=0 cause1=0x0 maxawait1=0 awaits1=0 epoch1=0
HARTS_USER user0=8900902 range0=197711 user1=0 range1=0
CYCLES total=567423274 host_done_at=567423274 drained=1
--- judge (m3_check.py):
INFO n1: retired 48457826 user 8900902 sched-range 197711 traps 1368
INFO disk: 200 block-device operations, strictly alternating request/completion
INFO m3par: children on harts 0x1 and 0x1
INFO m3migrate: harts 0x1 natural=0 pinned_ok=0 exec_ok=1
PASS experiments/multicore/m3/runs/single-a harts={'n': 1, 'retired': [48457826, 0], 'traps': [1368, 0], 'user': [8900902, 0], 'range': [197711, 0]}
```

## single-b

```
sim=/home/engineer/fpga/experiments/multicore/m3/runs/sim-single/obj_dir/sim (d7ecb822bff087a7)
kernel=/home/engineer/fpga/experiments/multicore/m3/sw/out/kernel-prod (df05b6e462398f6dc44aa7ffb5db976b4874c3b29bf2f43844daa499c449ae8c)
disk=/home/engineer/fpga/experiments/multicore/m3/sw/out/fs-prod.img (cbb031e5994efbceb7e0b51f4e93306ae4db680813521eb522318c96d156caa6)
workload=m3dual-b max_cycles=2000000000 wall=5400 stage=3000 scheduler=[0x80001e4e,0x80001f12) (plusargs decimal 2147491406 2147491602)
start=2026-09-27T11:05:52Z
--- verdict: XV6_RC=0 wall=3703s
--- stages:
ok	4.2	kernel banner
ok	547.2	init started / first prompt
ok	618.6	shell prompt
ok	1930.3	command ut-exec
ok	3701.4	command b0file
# workload: m3dual-b
# kernel sha256: df05b6e462398f6dc44aa7ffb5db976b4874c3b29bf2f43844daa499c449ae8c
# host exit: 0
# stop: deliberate-stop-after-all-commands
--- host lines:
AXI ar=17466501 r=17528213 rlast=17466501 aw=8353731 w=8371875 wlast=8353731 b=8353731
RD2HOST FINAL aWaits=3220687 aFires=18301875 dFires=18301875 epoch=1 injections=0 boot_ready=0 boot_timeout=0 bdev_queued=0
HARTS n=1 retired0=56937701 traps0=2514 cause0=0x8 maxawait0=240 awaits0=3220687 epoch0=1 retired1=0 traps1=0 cause1=0x0 maxawait1=0 awaits1=0 epoch1=0
HARTS_USER user0=496524 range0=147247 user1=0 range1=0
CYCLES total=656728895 host_done_at=656728895 drained=1
--- judge (m3_check.py):
INFO n1: retired 56937701 user 496524 sched-range 147247 traps 2514
INFO disk: 713 block-device operations, strictly alternating request/completion
PASS experiments/multicore/m3/runs/single-b harts={'n': 1, 'retired': [56937701, 0], 'traps': [2514, 0], 'user': [496524, 0], 'range': [147247, 0]}
```

## race-racepos

```
sim=/home/engineer/fpga/experiments/multicore/m3/runs/sim-dual/obj_dir/sim (693aaa1e0f8eaae6)
kernel=/home/engineer/fpga/experiments/multicore/m3/sw/out/kernel-racepos (a8b24c60774b64cab1390e37b9fb594212df9d7b44d1c85b93d1a956f807d592)
disk=/home/engineer/fpga/experiments/multicore/m3/sw/out/fs-prod.img (cbb031e5994efbceb7e0b51f4e93306ae4db680813521eb522318c96d156caa6)
workload=m3boot max_cycles=200000000 wall=900 stage=150 scheduler=[0x80001fb4,0x80002078) (plusargs decimal 2147491764 2147491960)
start=2026-09-27T07:02:34Z
--- verdict: XV6_RC=1 wall=305s
--- stages:
ok	4.1	kernel banner
TIMEOUT	154.3	init started / first prompt
TIMEOUT	304.3	shell prompt
# workload: m3boot
# kernel sha256: a8b24c60774b64cab1390e37b9fb594212df9d7b44d1c85b93d1a956f807d592
# host exit: 0
# stop: no-shell-prompt
--- host lines:
HTIF-RACE-TEST readers=1 consumed=1 expected=1 OK
AXI ar=2070344 r=2070456 rlast=2070344 aw=893196 w=894764 wlast=893196 b=893196
RD2HOST FINAL aWaits=1761049 aFires=2519472 dFires=2519472 epoch=1 injections=0 boot_ready=0 boot_timeout=0 bdev_queued=0
HARTS n=2 retired0=3883785 traps0=29 cause0=0x8000000000000001 maxawait0=254 awaits0=938646 epoch0=1 retired1=3882579 traps1=18 cause1=0x8000000000000007 maxawait1=160 awaits1=822403 epoch1=1
HARTS_USER user0=29406 range0=89005 user1=29413 range1=50
CYCLES total=40606937 host_done_at=40606937 drained=1
```

## race-raceneg

```
sim=/home/engineer/fpga/experiments/multicore/m3/runs/sim-dual/obj_dir/sim (693aaa1e0f8eaae6)
kernel=/home/engineer/fpga/experiments/multicore/m3/sw/out/kernel-raceneg (9adf761836870aa085480e7079b4671ac7ac35ea94c4c54db4d94cfb87b77975)
disk=/home/engineer/fpga/experiments/multicore/m3/sw/out/fs-prod.img (cbb031e5994efbceb7e0b51f4e93306ae4db680813521eb522318c96d156caa6)
workload=m3boot max_cycles=200000000 wall=900 stage=150 scheduler=[0x80001fb4,0x80002078) (plusargs decimal 2147491764 2147491960)
start=2026-09-27T07:07:39Z
--- verdict: XV6_RC=1 wall=305s
--- stages:
ok	4.1	kernel banner
TIMEOUT	154.2	init started / first prompt
TIMEOUT	304.2	shell prompt
# workload: m3boot
# kernel sha256: 9adf761836870aa085480e7079b4671ac7ac35ea94c4c54db4d94cfb87b77975
# host exit: 0
# stop: no-shell-prompt
--- host lines:
HTIF-RACE-TEST readers=2 consumed=2 expected=1 FAIL
AXI ar=2086653 r=2086765 rlast=2086653 aw=906925 w=908493 wlast=906925 b=906925
RD2HOST FINAL aWaits=1753814 aFires=2544785 dFires=2544785 epoch=1 injections=0 boot_ready=0 boot_timeout=0 bdev_queued=0
HARTS n=2 retired0=3915228 traps0=29 cause0=0x8000000000000001 maxawait0=254 awaits0=937656 epoch0=1 retired1=3909000 traps1=18 cause1=0x8000000000000007 maxawait1=162 awaits1=816158 epoch1=1
HARTS_USER user0=29406 range0=90403 user1=29413 range1=50
CYCLES total=40978750 host_done_at=40978739 drained=12
```

## race judge

```
racepos: HTIF-RACE-TEST readers=1 consumed=1 expected=1 OK
raceneg: HTIF-RACE-TEST readers=2 consumed=2 expected=1 FAIL
RACE_JUDGE bad=0
```

## program output (dual-a console, the workload segments)

```
$ b0compute
B0-COMPUTE-CHECKSUM=5ADF55920BF7696
B0-COMPUTE-DONE
$ b0array
B0-ARRAY-CHECKSUM=88133D5BD386DB60
B0-ARRAY-DONE
$ forktest
fork test
fork test OK
$ m3par
M3-PAR-CHILD0 checksum=f6d983767e3c5638 harts=0x3
M3-PAR-CHILD1 checksum=01d86a21f972f3fa harts=0x3
M3-PAR-DONE children=2 ok=1
$ m3migrate
M3-EXEC-AFTER-MIGRATE
M3-MIGRATE-DONE harts=0x3 natural=0 pinned_ok=1 exec_ok=1
$ m3exec 4
M3-EXEC-CHAIN-DONE depth=4 sbrk_ok=1
$ m3fs
M3-FS-CHILD0 ok=1
M3-FS-CHILD1 ok=1
M3-FS-DONE ok=1
$ Completed after 477276309 cycles
```

## program output (dual-b console, the workload segments)

```
$ usertests exectest
usertests starting
ALL TESTS PASSED
$ b0file
B0-FILE-CHECKSUM=62E55F5326378000
B0-FILE-DONE
$ Completed after 631730197 cycles
```

## program output (single-a console, the workload segments)

```
$ b0compute
B0-COMPUTE-CHECKSUM=5ADF55920BF7696
B0-COMPUTE-DONE
$ b0array
B0-ARRAY-CHECKSUM=88133D5BD386DB60
B0-ARRAY-DONE
$ forktest
fork test
fork test OK
$ m3par
M3-PAR-CHILD0 checksum=f6d983767e3c5638 harts=0x1
M3-PAR-CHILD1 checksum=01d86a21f972f3fa harts=0x1
M3-PAR-DONE children=2 ok=1
$ m3migrate
M3-EXEC-AFTER-MIGRATE
M3-MIGRATE-DONE harts=0x1 natural=0 pinned_ok=0 exec_ok=1
$ m3exec 4
M3-EXEC-CHAIN-DONE depth=4 sbrk_ok=1
$ m3fs
M3-FS-CHILD0 ok=1
M3-FS-CHILD1 ok=1
M3-FS-DONE ok=1
$ Completed after 567423274 cycles
```

## program output (single-b console, the workload segments)

```
$ usertests exectest
usertests starting
ALL TESTS PASSED
$ b0file
B0-FILE-CHECKSUM=62E55F5326378000
B0-FILE-DONE
$ Completed after 656728895 cycles
```

## aborted / superseded runs (kept)

```
/home/engineer/fpga/experiments/multicore/m3/runs/aborted:
aborted
dual-a-run2
dual-b-oldfs
dual-m3-hexrange
dual-m3-run1
race-raceneg-kernel0c1b
race-raceneg-refused
race-racepos-kernel54d4
race-racepos-refused
single-m3-oldfs
```

## judge self-test

```
M3_CHECK_SELFTEST pass=15 fail=0 (/home/engineer/fpga/experiments/multicore/m3/runs/m3-check-selftest)
```
