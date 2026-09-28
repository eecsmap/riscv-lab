# MC-M1 build manifest

Generated 2026-09-26T16:31:23Z.

## Worktree

```
path:    /home/engineer/fpga/worktrees/mc-single-wrapper
branch:  mc-single-wrapper
HEAD:    bcf403e338438a30cf61703fbec9eabd79e83f1b
base:    ips-v1-icache -> c16306bcfb40ead07a0375826527e9b871997f37
dirty:   0 path(s)
```

## RTL (rtl/cpu, the wrapper's)

```
c18ce30820dd61e6a4b6e203854a25b157ecd738d0fb816069e44b1fc034812d  tcpu_cacheable.v
7ea0ee368aebae35d962c09e83df0a41282fb47ddbfeff46fe37b27d3e837139  tcpu_cdecode.v
66fa67036efd3ef0847a426e11aba4e0214ea895b79467c97b1547257830250b  tcpu_core.v
51d725aaf8987a5076f0ef62e5006e47e3c9b41345327a1b1471d3d9e269a20e  tcpu_csr.v
8832ef6d5f33b35e3fb60026f35268b7d07a1b92ad7b80f5796f02892e212039  tcpu_icache.v
50ce699fcd5d2ea6ecedb5390c365804df2b9c05e6e6e38505a76850d31b7a94  tcpu_ifill.v
5e85de1d474ad63ff33aa78944ce60b9da579a47d5db0dc43c32c80fa7d8607f  tcpu_muldiv.v
b6668bc2ce57c6fe4e09199847dd8c4779c619de9e8a3c4c98f48ffb0dcd7e1d  tcpu_permcheck.v
ded150649edab04a90893850c0b65e9be113fee053d14e4e3f10bf5d4cbd680d  tcpu_ptw.v
40334e9cf0c7a247bc587cd486f59d7206131f121b6e1c6a6f254eeda3452350  tcpu_regfile.v
c275f8f6abe1a92d18e07d7b0e7b5380519144d4c1b2481f0062638569588ce3  tcpu_tlb.v
7a8398e13f7351f114e0af6cbb0bdad6942554f0b4c2d73d5b62ac1856d38e9d  tcpu_xlate.v
4d86ce139119a062928900f65b8f5bd38418253d5e91cf805de81329ef930920  tcpu_defs.vh
```

Changed against the tag:  2 files changed, 6 insertions(+), 2 deletions(-)

## Scala (soc/scala/teaching, the wrapper's)

```
8e5a9a5881177720fbfdc8cec7c3c513f9fba59f92fce074a76b52d14f9fb31b  AtomicBackend.scala
f2a700169cad2f55f16fba500389ac72798e7f9ad5ca5135bf03da4adc8a2316  AtomicHub.scala
1639a08c5a9ebd77ad6f017cef3da7acfa1cc85b28ae9d806e97ff6a36560085  AtomicSoc.scala
b11586e81d9d63ccd15fc02ed742adecb5e5ca31d5665aac15b72656d74e0414  AtomicTest.scala
3267a5dfe6e10d40a993c0fee0d10e9e20273cf9934aa7fe7271f47a6e07c8b7  BusTest.scala
aa774abab1b4e675ff4051bc77e8009f0e29bfa38200accf63c5b7e8b365e893  BusTester.scala
4a1e6bad6cd6d844db80d74f52a00a4a93161ecdd60b400e15f036e50025d5f2  PhysPort.scala
6e24f37554fb4293adc6e048c5fe7ee5dd4612bc48d0b92d45f605675c043e5f  PhysPortV2.scala
d35345e544c564c3f52d81a634fd8623c44344ea43d060bbc3da60ce312c00bd  RD1Bridge.scala
b9a2f99694b410b72febbceece1054b88951e2aceef4d0b0c7ba4646ac0cceaf  RD1Regress.scala
0d5799d3d303ad0bc9a63a9b07af01a0b69191e2c85222cedb55170c2c485b04  RD1Test.scala
e8de47ab295d1b7e2b6dfc2ea16b56174074448c10633f1f7ec3b9c0092ca672  RD2BlockDevice.scala
dca62ce32fb8cac5f2edca02574199a2dbd6b97ebf526576350b72f312f0d167  RD2BridgeV2.scala
271a19942031e992a04b0df58b80109ae1ff111dd4b6e29b825179f440bb372f  RD2Clint.scala
7acf6d627561a438fe1d8cae03d24d3a7a543310d9b6d10ff21c3dc30530b1b9  RD2Serial.scala
49b49606331f730407b332ff1303491ffcca0263307dcc326975ff948e5f86d7  RD2Soc.scala
619689acc3e45201e522a34b913b3e63f5aaea6a67339767f82d87a95c064674  RD2Throttle.scala
081786ff6367afa7a4c90370138748a5e040a83afa917d9ca771c992e1dd4d33  RD2ThrottleTest.scala
725ffd898a36bd77f1f8fda621774d54b532df287d4b9bbf354fd63252f1cc8b  RD2Watch.scala
f4b6bd13f901cce79fbcdaaac90e3dfdfa8ea736b5aec6518a9e16e86fdaab52  ReqRespToTL.scala
919e29efa87deedff2eaef840895a2973ff882017fb7a262a0206053fe28fecb  TeachingCpuBlackBox.scala
cff0c098d4ebf27f6b21434abf1d5aa9b9b5972446af5926d5fe00194c74f09a  TeachingCpuSoc.scala
b6bdca53a502a101ad4cee700518db1a2054f062b3238f04d0115723c4591f90  TeachingHart.scala
6d80143994bd041b1a15e2f546df9157f0dcdfdf6555c4c6595a9a940f177f33  TeachingSoc.scala
```

Changed against the tag:  3 files changed, 166 insertions(+), 42 deletions(-)

## Generator inputs

Private commons (fpga-zynq/common copies; the shared tree is not written): `/home/engineer/fpga/experiments/multicore/m1/gen/common-before` (tag scala), `/home/engineer/fpga/experiments/multicore/m1/gen/common-after` (wrapper scala).

```
shared scala tree baseline: fb0ee0a3d71af561  (36 files)
shared scala tree now:      unchanged
rocket-chip jars (lib): 0 stamp bytes; 20 jars
```

## Generated Verilog

```
gen-before-xv6fast   ed021fc06606fc51  wall_s=31
gen-before-boot      12fffa5c2348dff0  wall_s=38
gen-after-xv6fast    c36829afc4e3c6cd  wall_s=27
gen-after-boot       5c2801ed9d07d0f2  wall_s=39
```

## Simulators (Verilator, RD2Harness)

```
probes-before-fast   sim=7a7d1e3e08aefe07  generated=ed021fc06606fc51  tcpu_core=66fa67036efd3ef0
probes-after-fast    sim=a1006cd23bad5b43  generated=c36829afc4e3c6cd  tcpu_core=66fa67036efd3ef0
probes-before-trace  sim=397ba69904d06795  generated=12fffa5c2348dff0  tcpu_core=66fa67036efd3ef0
probes-after-trace   sim=b9d525edb69b58b1  generated=5c2801ed9d07d0f2  tcpu_core=66fa67036efd3ef0
xv6-after            sim=a1006cd23bad5b43  generated=c36829afc4e3c6cd  tcpu_core=66fa67036efd3ef0
closeout2-before-fast sim=7a7d1e3e08aefe07  generated=ed021fc06606fc51  tcpu_core=66fa67036efd3ef0
closeout2-after-fast sim=a1006cd23bad5b43  generated=c36829afc4e3c6cd  tcpu_core=66fa67036efd3ef0
closeout2-before-trace sim=397ba69904d06795  generated=12fffa5c2348dff0  tcpu_core=66fa67036efd3ef0
closeout2-after-trace sim=b9d525edb69b58b1  generated=5c2801ed9d07d0f2  tcpu_core=66fa67036efd3ef0
```

## Programs (frozen set used by the closeout rerun: whole-file sha256, then load-semantic identity)

```
69ca91994567a44f9afb0303013bb8412eb6142749c28b631000e92156da61a2  boot01_marker.elf
0c4ebbb7648a34c013bbf77b0c7a5f03f901993fbe0e690732c46f15f8fb2c0f  boot02_clint.elf
3089c7e72514eded26b80b02f9dcd57c0ee74609ca42803dd800e360daff39d0  boot03_ddr.elf
fc3b16962f69e53abfa37a30ddd1490091926a47f4dda1c16fa04e37ea592380  boot04_badaddr.elf
52bd012e00623daeaa0f369b9ea9f1436eff3f59ec60630a435a2ae25e2dc6f5  boot11_sv39.elf
3ad49cf06ca670c6d254945cb6b36c55987e3763979838b1ca341e7b183998a8  boot12_amo.elf
ef65cd867812c7d2cea39185bef754087d259135a338f21d65456a1c8609f5d7  cache01_smc.elf
b57e1b63d9d29688fd9ce3a04390d5eddf26edc6007e78fd6314da5df11d07e4  ext01_m.elf
f8f9f75e2134c084f53561efd77ae77e8ed05f6eeaf752b52b2ff86a9711abd6  ext02_c.elf
3d1cda4b1d6af6f8a8a3fe3a97277bfc01714a77ad4901993ca36c6addaf8ced  ext03_a.elf
0251f1512a16cf6b9c3bf2ad98663105a82b5ce304642378a94cc3dc0bf50023  ext04_sv39.elf
458d934cf9b4881cf38aa53ecc194e15a30fc9703364e2339a5d42ccd43a1544  hello.riscv
bc6185566c5de9da7a4dbce1942262dbeb68b1c8e556ac8f72f15fc1465596ab  perf02_sv39.elf
6498f89970d429e92a944036d91b20801410be8b14df88f7f59d6512efff05b5  perf03_fetch.elf
235f2318149ed2064904c92d4cab6849115d576fe80f478eea603e77c067315d  perf04_where.elf
e6be12db60bd76683f9c5286c759316466cc68c4e79eac9e3d1a3985ccb8d64a  perf06_iws.elf
368561b6463535e4c3263bdb855ce197505b3b41283985c9ba4b366773171717  tlb01_sfence.elf
288448b4fd3211f0ae6a5414d4367be6e4f315b29966e9b254d12367688cafb1  tlb02_canonical.elf
--- load identity (elf_ident.py) ---
4aaa53ed02ceb5373481999cfefd019e984d92dfb433f8187c4f3e2287656c88  boot01_marker.elf
317741f09ea55f07ce5707c463b850b83d75e60c3dbc32d55744c1332a56c28b  boot02_clint.elf
6d9f6e042c1903661ae658d48e3520cea7ebce4b8d031583e4875edaf9e420cb  boot03_ddr.elf
106b6d5b934d2cba852ac5b6259eda57da1a59d1d795d94a3d6f438fde231cd9  boot04_badaddr.elf
68a4e81afae805953482599389b01e348ab5b24a0f952bf27a2272b392dbf3a0  boot11_sv39.elf
ff99f2851473ad6812a12907419a00452751157667e98f004e11cf198b0a4bbb  boot12_amo.elf
81bbe9ec2002f34f6c44d750485ba1fdbe8642d206aabff69500d1875538a65c  cache01_smc.elf
499607b0324a50faf7444f39f1aaa59275eac34e2827946ab1e9b87b51c0951e  ext01_m.elf
4863c1d4b96328337abd337fed42bc9e88b93a178b02b961c2a631cb660a5c61  ext02_c.elf
051ca14209ff0033ce99e0599ea249a77a5c3071c08dd4124312d2e971722224  ext03_a.elf
1930fa827c22c8974e2bfec4b300bc6f98ea47fa93ce4972c23c191d1368b8b4  ext04_sv39.elf
750e0f4cdcfd667459d6c8969f07c473cdbb7c0465a07c726d50aa4dbc4d13df  hello.riscv
7c63d89bc4bfb11c97a239d73f222c27a240764b647148574c7f4b094a53e48c  perf02_sv39.elf
2da4573fe7217336bb4d54c6fb806219addb912ce575dbe1c5177a432a185338  perf03_fetch.elf
037b85b013151f46d4a73de6a348d1695ef67501e72e0f4bd2d9250cd9b1f37e  perf04_where.elf
63643e2a7dbdaf4f80e17a8b44c19c5da0d25b3e58ef3228ee0fde02b5e22726  perf06_iws.elf
9fb0d0e097b8fd0324dc500c6c68d17e5df5938e452cc7b78d57c580a0315ff8  tlb01_sfence.elf
dd6853ae7f0daeb5ef9491485458a73210f932a93d042de692ab6efe823ee6da  tlb02_canonical.elf
```

## xv6 inputs

```
kernel-4mib          6ad5c2338a31d59e
fs-b0-pristine.img   6bdd8148b79e5983
```

## Tools

```
Verilator 5.022 2024-02-24 rev conda-forge build 1
riscv64-unknown-elf-gcc (gc891d8dc23e) 13.2.0
docker image for sbt: vivado-env:2025.2-sw (612322e4185a), java-8 inside
sbt-launch: 4a3f4cda74c03aab
```

## Configurations

- `RD2Harness.RD2AtomicXv6FastConfig` — atomic path, no event trace, no TL monitors: probes (all), ROI, xv6.
- `RD2Harness.RD2AtomicBootConfig` — atomic path, event trace on: short probes for the COMMIT/TRAP comparison, R-BOOT gates.
- `MC1Unsupported{Pipeline,Dual,Zero}Config` — must refuse (T1.9).
- `AtomicSocHarness.AtomicSoc*Config` — the backend's SoC scenarios through TeachingCpuV2 directly (not the wrapper).
