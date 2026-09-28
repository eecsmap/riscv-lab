# MC-M2b build manifest

Generated 2026-09-27T04:32:59Z.

## Worktree

```
path:    /home/engineer/fpga/worktrees/mc-dual-core
branch:  mc-dual-core
HEAD:    b147091f93feb23e3aeadec43c17a9c3d1a95f8d  (MC-M2b: two real TeachingHarts on the RD2 chain (NUM_CORES 1|2), per-hart CLINT/)
base:    33c4864 (MC-M2a accepted)
dirty:   0 path(s)
```

## RTL (rtl/cpu -- unchanged since M1)

```
set hash: 52ea751de4126fa0  (M1 mc-single-wrapper: 52ea751de4126fa0)
```

## Scala (soc/scala/teaching)

```
edf7e5b5fb8f27d2efd6ef11a2a3e5828e6199d0385285086e33d9f31a69d811  AtomicBackend.scala
147f113924299af27b1ce5d3d80e3dc52e90b6733bd74fe5550cac20f72e4132  AtomicHub.scala
2ff7ba63a6b279ee7e9540dc35522a8941e44a679dc45f89d6da717159de2149  AtomicSoc.scala
4ec9b2f2ec19ba8164de03aecba89adb716be89b0f6448c89e43a3533bdd7a30  AtomicTest.scala
3267a5dfe6e10d40a993c0fee0d10e9e20273cf9934aa7fe7271f47a6e07c8b7  BusTest.scala
aa774abab1b4e675ff4051bc77e8009f0e29bfa38200accf63c5b7e8b365e893  BusTester.scala
9f72b78284485d8220226851d5ff2b9bf5a3e13bd395c023691a82f760d0b83e  DualAtomicTest.scala
4a1e6bad6cd6d844db80d74f52a00a4a93161ecdd60b400e15f036e50025d5f2  PhysPort.scala
6e24f37554fb4293adc6e048c5fe7ee5dd4612bc48d0b92d45f605675c043e5f  PhysPortV2.scala
d35345e544c564c3f52d81a634fd8623c44344ea43d060bbc3da60ce312c00bd  RD1Bridge.scala
b9a2f99694b410b72febbceece1054b88951e2aceef4d0b0c7ba4646ac0cceaf  RD1Regress.scala
0d5799d3d303ad0bc9a63a9b07af01a0b69191e2c85222cedb55170c2c485b04  RD1Test.scala
e8de47ab295d1b7e2b6dfc2ea16b56174074448c10633f1f7ec3b9c0092ca672  RD2BlockDevice.scala
266b7500a44bf113152573320169f804a228af1ddd3d9ffefb92162820e3446a  RD2BridgeV2.scala
271a19942031e992a04b0df58b80109ae1ff111dd4b6e29b825179f440bb372f  RD2Clint.scala
7acf6d627561a438fe1d8cae03d24d3a7a543310d9b6d10ff21c3dc30530b1b9  RD2Serial.scala
ed3dbf9fdece4c36c936b05f46d4e03a50402b2db26ac3048ae0b77a82ce00e4  RD2Soc.scala
619689acc3e45201e522a34b913b3e63f5aaea6a67339767f82d87a95c064674  RD2Throttle.scala
081786ff6367afa7a4c90370138748a5e040a83afa917d9ca771c992e1dd4d33  RD2ThrottleTest.scala
725ffd898a36bd77f1f8fda621774d54b532df287d4b9bbf354fd63252f1cc8b  RD2Watch.scala
f4b6bd13f901cce79fbcdaaac90e3dfdfa8ea736b5aec6518a9e16e86fdaab52  ReqRespToTL.scala
919e29efa87deedff2eaef840895a2973ff882017fb7a262a0206053fe28fecb  TeachingCpuBlackBox.scala
cff0c098d4ebf27f6b21434abf1d5aa9b9b5972446af5926d5fe00194c74f09a  TeachingCpuSoc.scala
732e57d660e813e09907534f02ec350041243902b356b0b081a778b89417aaba  TeachingHart.scala
6d80143994bd041b1a15e2f546df9157f0dcdfdf6555c4c6595a9a940f177f33  TeachingSoc.scala
0d8c3c5cbfba7a546c2ff87d38ac7f0ce4e0435238db0b2b5f54e837452e28c9  atomic_soc_main.cpp
7ac41b995dc56faac6fc4744efd4cfc23602fa8bb89272a7386624b47ec1f09f  cpu_boot_main.cpp
675e8f91fe180a7ec0b30ee3e433279a019262085d894deb3876e2a5cf8ad26e  soc_main.cpp
30bb677bd7fe95c4deb2183b17f84826e63665adeb59ebc576e55919e75d6fa6  soc_tb_main.cpp
d954c96e0f8a9d920a68d27c69842ee13751fda4a5d6e66da28e5d39831fd1ac  unittest_main.cpp
```
Changed against 33c4864:  5 files changed, 261 insertions(+), 174 deletions(-)

## Private common

```
private common scala DIFFERS from the worktree:
   < 9e6ace862da8327a4c9d6807b952560f4f95230250e3cebe3f0e1553501139d1  AtomicBackend.scala
   > edf7e5b5fb8f27d2efd6ef11a2a3e5828e6199d0385285086e33d9f31a69d811  AtomicBackend.scala
shared scala tree vs M1 baseline: unchanged
shared fpga-zynq files modified since 2026-09-27 02:00 (excluding sbt caches): 0
```

## Generated Verilog and simulators

```
compile-check-1/RD2Harness.RD2DualBootConfig.v d7d13ad04163f2c0
gen-dual-fast/RD2Harness.RD2DualXv6FastConfig.v f69fc474a4d9533d
n1/rd2/gen-RD2AtomicXv6FastConfig/RD2Harness.RD2AtomicXv6FastConfig.v 125d62a950752aa9
n1/rd2/gen-RD2AtomicBootConfig/RD2Harness.RD2AtomicBootConfig.v 7a12fc6878540bb5
sim-dual-boot/obj_dir/sim                    74f7b44792bb9f17
sim-dual-fast/obj_dir/sim                    43362e9c036ee1c6
n1/rd2/probes-fast/sim/obj_dir/sim           7b0a8dea5853ba55
n1/rd2/probes-trace/sim/obj_dir/sim          001ded4c9cb87101
```

## Programs (progs/build)

```
aa1faca1d5b1456acca9cde25870788f4383603915877646a5077707a72e87bc  dual01_boot.elf
beffce7e53733a293c13c14d2f50690ac3728b9ac61cbb8eb429e64ca157e718  dual02_clint.elf
7bb6d1df99eea7b7fb548d482f1541292912442879c32d028e46b987e1604767  dual03_lock.elf
ab568bd79abfbee3e167b8ee4d6a721d4eaec3424b7451d174611a1deea1be8a  dual04_pbus.elf
495360cb6f21b745ef5f42084a6e8ccc90badb73b6988fd419754a46dca1ff37  dual05_fencei.elf
3d1451e280f0cf0a762e333b05f49c7d6d454b856a9d8690829fe23be6d14017  dual06_drain.elf
459347189d79d4f10ba99f68a5119ee12fc2dcbebbdc6ae9eb4b647c8c02f117  dual07_long.elf
69eee8c15ac5993f300d09b9f2dc16d660fb89149cc3e9ee1b14586fcd1df822  neg01_nohart1.elf
2e352aa8ccf90823478fcb1a33fc2aaf211b6b4ec4f4de584324d1a484fa335e  neg02_wronghart.elf
85f0dfcf37a5206bdd02fde59237c519eb1b41ff6b521f27bc08d2c275182daa  neg03_wrongcount.elf
084990bce0aa09c72f5d36a7648da1e71fd1a94453684367eb4d075f504ee1f8  neg04_early.elf
--- load identity (elf_ident.py):
90f94f2c28168bb1181c43e51856cc789c8d6415093a66255c3ad78a04018ac2  dual01_boot.elf
a910b583a7340e11a4ed3990e36f645dfa412937453535ab667588ca51ef8463  dual02_clint.elf
cc64661d4d771bfbb7ff591fc677a71409a5faec453dabdf9fc2dc56f4d32ed9  dual03_lock.elf
aee1aa241c97746656cefe92be00931a0847f3ec859b55678764aac841600b6a  dual04_pbus.elf
75c10e320ff9ab166c117dbd54e559e39ad1d77e19089572aafa5a7d42cb05ff  dual05_fencei.elf
944ec1c7f9eb7c794b2e512b96cbb09bf5812b4b398bfbeb7d99ed8af8438208  dual06_drain.elf
9a77cc21417690a0b4e3d15a98a92fab54ca2f95e59f9329bf7ee4171794b94f  dual07_long.elf
36106360a72fa12d7ea83391db36fb5320218d397f3ef671adef446fed8d7f58  neg01_nohart1.elf
ca59cb8ac2a1bcfe0b0d42927afc3ef8ec5929862f04c5aa4444c406f96330d3  neg02_wronghart.elf
971483033ede79f9f487aece5a4e508496db4b6292ecc149c3aa5dcd451e628c  neg03_wrongcount.elf
3da2218a0143d5eb295bf1c10623e492e94831e22ea8625b6e3e63d8648ea207  neg04_early.elf
toolchain: riscv64-unknown-elf-gcc (gc891d8dc23e) 13.2.0
```

## Judges and tools

```
e464aad74b336e69850b361069cd840c3811ccdc3843f3143430997f4be67377  dual_check.py
912cecdde1ef0a733fbd0b8d2f63fba2e1667b715c303ed33c0d14d127e9c5c1  dual-check-selftest.sh
c71e4d579ffd785ecf24f1b1c1ec9cdc8726ae1e68f17151ab1a8c6a330749dc  run-dual.sh
ee9dfda89f867d3a513af0fecd9876fda57556f4dada50931cb4f78aaed99e53  build-dual-sim.sh
c1ccdfe99c8f52988135a65a86eb7af172f86f19ba026ebbbf31937b322ed16f  m2b_main.cpp
10a6fc5246c1c52f56768c692c8cbcc231fdb89e91f91af14ca5f76f6cd8e700  m2b-suite.sh
8d8c94a5282d381abb79490ea8c9c1608c41694ea610085e8ab6818dc560414c  n1-regress.sh
38844417944931ab8a920b42522097ac80aee5a6d8ae2d3e01cbe5afa6f2e306  smoke2.sh
b9757f2ed35885bb7aa2ece9cf02325ffa202e0051289c98158852773cdb3c3d  rd2-regress.sh
666ed0a0695197e381d07b9400093f5eb08a5858e1acbe520e4e66dcc746e7f5  atomic-rerun.sh
6b25d66b6b12f0aa55038c38f6e33ecaa25ebca2bbe974205a166c7992d25d12  compare-probes.py
c7a47b85227c97a19946eebe29f73bbe935ca3acc97eeeb23208562552206e95  probe_console.py
984c01184d1a00795e8a4158eda007c27408409d4351305d2cbc024379c83c69  build.sh
d6520fc207194c9584cd354c541db55d90aa5646c036c69a4ea4c5472759a8be  link.ld
bb530a8a29090cbc1cb66993ba9e31f11079ee0e036298a5357b0e3d1f9b7817  start.S
69571ac54546edcea8ef155a993c6ff7763eedc5d663cb4b5a2a538f0302e799  htif.S
8eaf87511a7f1be187ae7d000bb0af878f734a1544679a8c408492d32f1a0206  dual.h
```

## Tools

```
Verilator 5.022 2024-02-24 rev conda-forge build 1
Python 3.10.14
riscv64-unknown-elf-gcc (gc891d8dc23e) 13.2.0
docker image for sbt: vivado-env:2025.2-sw (612322e4185a), java-8 inside
```
