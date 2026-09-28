# MC-M2a build manifest

Generated 2026-09-26T23:47:00Z.

## Worktree

```
path:    /home/engineer/fpga/worktrees/mc-dual-backend
branch:  mc-dual-backend
HEAD:    33c48646dab1ca7e7d9b8ad2e484696a31a4af44  (MC-M2a review fix: nKill counts every reservation cleared in a cycle (per-hart i)
base:    bcf403e (MC-M1 accepted)
dirty:   0 path(s)
```

## RTL (rtl/cpu -- unchanged from M1)

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
set hash: 52ea751de4126fa0  (M1 mc-single-wrapper: 52ea751de4126fa0)
```

## Scala (soc/scala/teaching)

```
9e6ace862da8327a4c9d6807b952560f4f95230250e3cebe3f0e1553501139d1  AtomicBackend.scala
79cdd83654a64e4305ba3fcd8873b2ae067433ecf9049cd75efcda2dd9ad0a83  AtomicHub.scala
ade0e13b4b84f85e09000e3763fae3d6ab9ff4fbf237d828823c8e2f876e6a24  AtomicSoc.scala
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
a6a864983e806f51f7ee4897ff23825b8392a12293b0ee5170068d5315752033  RD2Soc.scala
619689acc3e45201e522a34b913b3e63f5aaea6a67339767f82d87a95c064674  RD2Throttle.scala
081786ff6367afa7a4c90370138748a5e040a83afa917d9ca771c992e1dd4d33  RD2ThrottleTest.scala
725ffd898a36bd77f1f8fda621774d54b532df287d4b9bbf354fd63252f1cc8b  RD2Watch.scala
f4b6bd13f901cce79fbcdaaac90e3dfdfa8ea736b5aec6518a9e16e86fdaab52  ReqRespToTL.scala
919e29efa87deedff2eaef840895a2973ff882017fb7a262a0206053fe28fecb  TeachingCpuBlackBox.scala
cff0c098d4ebf27f6b21434abf1d5aa9b9b5972446af5926d5fe00194c74f09a  TeachingCpuSoc.scala
b6bdca53a502a101ad4cee700518db1a2054f062b3238f04d0115723c4591f90  TeachingHart.scala
6d80143994bd041b1a15e2f546df9157f0dcdfdf6555c4c6595a9a940f177f33  TeachingSoc.scala
0d8c3c5cbfba7a546c2ff87d38ac7f0ce4e0435238db0b2b5f54e837452e28c9  atomic_soc_main.cpp
7ac41b995dc56faac6fc4744efd4cfc23602fa8bb89272a7386624b47ec1f09f  cpu_boot_main.cpp
675e8f91fe180a7ec0b30ee3e433279a019262085d894deb3876e2a5cf8ad26e  soc_main.cpp
30bb677bd7fe95c4deb2183b17f84826e63665adeb59ebc576e55919e75d6fa6  soc_tb_main.cpp
d954c96e0f8a9d920a68d27c69842ee13751fda4a5d6e66da28e5d39831fd1ac  unittest_main.cpp
```

Changed against bcf403e:  7 files changed, 504 insertions(+), 84 deletions(-); new: 

## Generator inputs

Private common: `/home/engineer/fpga/experiments/multicore/m2a/gen/common-dual` (prepare-common.sh copy of fpga-zynq/common with the worktree scala; the shared tree is not written).

```
private common scala == worktree scala
shared scala tree vs M1 baseline: unchanged
```

## Runs (generated Verilog / simulator per scenario)

```
dual-directed-final/d01-lrsc-race    gen=c7e21ca0a8c051e1 sim=8eb05f8ffec000f7
dual-directed-final/d02-store-kills  gen=8dac093b49808b14 sim=562d86ad980aa923
dual-directed-final/d03-granules     gen=6a5d2f91831cda5b sim=bab647eb33c3c419
dual-directed-final/d05-trap-local   gen=ba26cf806e289265 sim=2b522d7cf93ab220
dual-directed-final/d06-dma-kills    gen=bb0f90bff91bec6f sim=00b27219fc4c3f24
dual-directed-final/d07-partial      gen=42c2e47e4fda6979 sim=d6d4935f56efbfe5
dual-directed-final/d08-failed-sc    gen=bb6594fe67881c4f sim=cd79ca9af7101044
dual-directed-final/d09-paths        gen=147d704c3e39b9bc sim=67869e141caccf1b
dual-directed-final/d10-amo-contend  gen=b7129616c4de24cd sim=838b4f838d0378bc
dual-directed-final/d11-drain        gen=07bda0e055c4a375 sim=556865ad15838952
dual-directed-final/d12-fair         gen=17b90901960cf05c sim=3371f4f78f633f44
dual-directed-fix/d01-lrsc-race      gen=35f08cbb081f4524 sim=167b9e0d29499fd2
dual-directed-fix/d02-store-kills    gen=51da87662d71b526 sim=3eb0f8290ce81751
dual-directed-fix/d03-granules       gen=fa6f9e9862cdc43a sim=fbd134f274523a80
dual-directed-fix/d05-trap-local     gen=8e3013048e560ea2 sim=3dea739858e5e3d2
dual-directed-fix/d06-dma-kills      gen=47a8db3f820ba850 sim=edefb5b459b9d017
dual-directed-fix/d07-partial        gen=d2ee7b4722141894 sim=879f9d8a3d214378
dual-directed-fix/d08-failed-sc      gen=b71f514cbbb0c136 sim=31a080c84a0641a0
dual-directed-fix/d09-paths          gen=7de8575bfc6e6128 sim=841b6b8dccd2f432
dual-directed-fix/d10-amo-contend    gen=50ef9514559dd7c4 sim=62dfb9c83e413bb9
dual-directed-fix/d11-drain          gen=6a6d70d32d13d29f sim=563a793721ab6c16
dual-directed-fix/d12-fair           gen=60615753eedbc42a sim=fb0593d53692cf9e
dual-directed/d01-lrsc-race          gen=76d02e58ef28c0ff sim=250ef36a7d0f8cbd
dual-directed/d02-store-kills        gen=5b1e035187e9f0aa sim=e801a208299acc16
dual-directed/d03-granules           gen=6c1f0835f0685234 sim=4e8494bd24c17864
dual-directed/d05-trap-local         gen=a9fc14f2bbb9fcb3 sim=0d857bde2ad2f513
dual-directed/d06-dma-kills          gen=5e68763463e07868 sim=4917f95018927e82
dual-directed/d07-partial            gen=92fe92df9ca9d0f7 sim=899c418d9ac70e4a
dual-directed/d08-failed-sc          gen=da541efaae3030d0 sim=296a20b176627eef
dual-directed/d09-paths              gen=a5c1b77304c5d2fa sim=a124c05a6b25d776
dual-directed/d10-amo-contend        gen=b9d7fa098b7333c9 sim=6e663a1b9f0d35e3
dual-directed/d11-drain              gen=f70b35f78c8610a6 sim=ceae6946b981c5e7
dual-directed/d12-fair               gen=bae3170c81b7cc80 sim=36179d46651346de
dual-neg-final/neg-interleave        gen=e2864be288c35fd6 sim=b665288bd665ea1a
dual-neg-final/neg-no-cross-kill     gen=44b23775b29e8458 sim=ecf1f53cfe6fe4f1
dual-neg-final/neg-no-kill           gen=d53e4eae676390e2 sim=9eb91ec3fe9cbacc
dual-neg-final/neg-phys-withdraw     gen=325a0e2f5ee9a094 sim=6451f6be5fd6171e
dual-neg-final/neg-swap-dsource      gen=0134c97882205ac6 sim=79e1960eb5bb8fb2
dual-neg-final/neg-swap-sideband     gen=67d5cb05d2d8ac43 sim=64e6464f3b2016fa
dual-neg-final/neg-tl-withdraw       gen=ed9f9328eb39a6b8 sim=0f376d71a29a8354
dual-neg-final/neg-wrong-src         gen=7f990947020ed5ab sim=c8c43a1e0ed4db3b
dual-neg-fix/neg-interleave          gen=be1961b8d159208d sim=2dd26850832ec439
dual-neg-fix/neg-no-cross-kill       gen=932f6d89921cb218 sim=6f97224d3f666fe0
dual-neg-fix/neg-no-kill             gen=e59dcd7cd7279a00 sim=f7f4ba51ea0a65a2
dual-neg-fix/neg-phys-withdraw       gen=c47125478003d544 sim=e5bb27027a828f42
dual-neg-fix/neg-swap-dsource        gen=2ab420d14316bf93 sim=2c1f8ec12cfe7470
dual-neg-fix/neg-swap-sideband       gen=56c873dee11c82ac sim=eaf0c727b4a6526e
dual-neg-fix/neg-tl-withdraw         gen=76cbee04c52f3443 sim=9df2270e33a30a54
dual-neg-fix/neg-wrong-src           gen=0ff025ad980cebbf sim=852ce36728488839
dual-neg/neg-interleave              gen=09593e7f0fece561 sim=0eff9825be6ea8ff
dual-neg/neg-no-cross-kill           gen=29cae5dc8e7705b5 sim=eac1b31e42f33124
dual-neg/neg-no-kill                 gen=d6ed50086ff46f3d sim=53b2cd77e61d8d32
dual-neg/neg-phys-withdraw           gen=3513d92f14b9af04 sim=84b43f883675fc8f
dual-neg/neg-swap-dsource            gen=277bbf0cd916fee6 sim=aed31a57352515dd
dual-neg/neg-swap-sideband           gen=ff3f4468bb1e59cc sim=2492572bc1303d23
dual-neg/neg-tl-withdraw             gen=67c66b869cc7cad4 sim=50027f3c302127e7
dual-neg/neg-wrong-src               gen=4ea64f389ed7a20e sim=614aebc8c6850c09
dual-random-fix/rnd1                 gen=2da7c4e92894aa4f sim=8564ebc1a1adea79
dual-random-fix/rnd10                gen=fffbc3912c5817f0 sim=c27502575e92d50d
dual-random-fix/rnd2                 gen=b0278af9e364dd45 sim=42916e996be42d92
dual-random-fix/rnd3                 gen=c19f0ffc5c155990 sim=06bd5143321f1fd4
dual-random-fix/rnd4                 gen=651190277e5f445f sim=2434845f0cead914
dual-random-fix/rnd5                 gen=c0e637a78f3cfa50 sim=8423fbb9896711b0
dual-random-fix/rnd6                 gen=d024ca973e9ac5f8 sim=6d987d44b8e10ddb
dual-random-fix/rnd7                 gen=498cb67d448036cf sim=2e92478f7684dc0c
dual-random-fix/rnd8                 gen=a6b933f332c3e7dd sim=e532c8964557d012
dual-random-fix/rnd9                 gen=4941ce517d377bb3 sim=568d03c71e0c69eb
dual-random/rnd1                     gen=bcddf1d0edef9a91 sim=eeda9dbfb1d6348f
dual-random/rnd10                    gen=e6c8ee8425c9bcb4 sim=966734a57ee7f8b9
dual-random/rnd2                     gen=b66ab2d4bb9a4466 sim=29e669bad07abfd4
dual-random/rnd3                     gen=ba348e9d84814ee1 sim=571bed906abdc35a
dual-random/rnd4                     gen=8788376410ef3ae0 sim=46263f5eb7d060e7
dual-random/rnd5                     gen=a6a89321cd72877c sim=f9e49d997089530e
dual-random/rnd6                     gen=9135f66dadf1226b sim=f18aebafcbe7a37b
dual-random/rnd7                     gen=1485b26a6af4b9b9 sim=d145d1484d218071
dual-random/rnd8                     gen=6b08d6f407b1d014 sim=dc466d634b4046c1
dual-random/rnd9                     gen=7390e314c82e4108 sim=2b98a8a0e133a163
dual-topo-fix/rnd1-extra             gen=f8fe3f49b9326f2f sim=16cd55af2a382aae
dual-topo-fix/rnd1-swap-extra        gen=3877ce8ca5528e7d sim=122e64e40ffda852
dual-topo-fix/rnd1-swap              gen=71345c40f59d2836 sim=13e2ab1365e90a28
dual-topo/rnd1-extra                 gen=448ce7ee586ac0af sim=b6e4ac5febe8f7ed
dual-topo/rnd1-swap-extra            gen=5c90b0ce3fc7e8d1 sim=1c012ce65939848c
dual-topo/rnd1-swap                  gen=cac1210650332258 sim=fa9155c762d3c55c
atomic-rerun/amo-basic               gen=34b89036f06950b1 sim=e369057aca1f449b
atomic-rerun/amo-partial             gen=9fabcfa5ad36fff2 sim=d828aa7348ca005e
atomic-rerun/amo-race                gen=6967bd0643fdaf47 sim=062b1d3fd37005fe
atomic-rerun/bp-amo                  gen=068acc3f7dcd47dc sim=7a66a5d2fb2f1cf8
atomic-rerun/bp-drain                gen=42041daa855c774a sim=57bc3fb9aa9b1f8a
atomic-rerun/bp-errors               gen=40b28b5aca3e8d5e sim=5186142c4bc55f3d
atomic-rerun/bp-lrsc-basic           gen=24334f3783015244 sim=66d05180ac57c3cc
atomic-rerun/bp-lrsc                 gen=b1a3b7086889f9c1 sim=57a5ce50bd0cb6c8
atomic-rerun/drain-getd              gen=611b33267cfee918 sim=77fae9ef7859d0bf
atomic-rerun/drain-putd              gen=5d6ae3478ef55166 sim=5081f4d0a6245872
atomic-rerun/drain-resp              gen=c8519cacf5514011 sim=a04a1cea971cfe8b
atomic-rerun/errors                  gen=bb67f03b5a4fe2b5 sim=6a83b85869ce9e6c
atomic-rerun/lrsc-basic              gen=75cb49bb50782cdb sim=c558c18dfff28af5
atomic-rerun/lrsc-race               gen=53909006f9a3848d sim=fc46a34ba937f6f6
atomic-rerun/neg-amo-map             gen=9a3e22b9d3406e68 sim=0a9492dd7252d7f3
atomic-rerun/neg-amo-operand         gen=519d4555f2bf7d55 sim=26465518497c3f99
atomic-rerun/neg-no-kill             gen=f3348e4bc55cf62d sim=e11fc2f43cc2f474
atomic-rerun/neg-readerr-writes      gen=d2dc6d038cd40e8a sim=1f8d00b472b2002e
atomic-rerun/neg-sc-early            gen=a648d8cd082a8ac1 sim=8647ade07030c4ed
atomic-rerun/neg-wrong-source        gen=e7abc58462db0282 sim=97fd83013d51e451
atomic-rerun/progress                gen=329fc33744565e6c sim=32d6433b12409fdc
atomic-rerun/selftest                gen= sim=
atomic-rerun/soc-amo-race            gen=72e71b02a89d9f79 sim=17d9f3d7ecd0cad4
atomic-rerun/soc-errors              gen=a2cb8c16b4b16bf6 sim=8a7deed81107de0c
atomic-rerun/soc-lrsc-race           gen=9ebdc1d944a0787d sim=9e311b92c7a7e057
atomic-rerun/soc-neg-amo-map         gen=7ac5bc36057e9620 sim=249db886597261ef
atomic-rerun/soc-neg-no-kill         gen=e0b53bc056b53c0d sim=eae570dc975d2690
atomic-rerun/soc-partial             gen=53a8c08c0772221e sim=becf5a39f65f18ae
rd2/gen-RD2AtomicBootConfig          gen=842c60c360a6a683 sim=
rd2/gen-RD2AtomicXv6FastConfig       gen=dfaf518233ee09b0 sim=
rd2/probes-fast                      gen= sim=044f959dd0f47401
rd2/probes-trace                     gen= sim=ef8f25de1c4a6375
```

## Programs (M1's frozen set, reused byte-for-byte)

```
69ca91994567a44f9afb0303013bb8412eb6142749c28b631000e92156da61a2  boot01_marker.elf
0c4ebbb7648a34c013bbf77b0c7a5f03f901993fbe0e690732c46f15f8fb2c0f  boot02_clint.elf
3089c7e72514eded26b80b02f9dcd57c0ee74609ca42803dd800e360daff39d0  boot03_ddr.elf
...
elf.sha256 set: 0fc980ad2da365a1  elf-load.sha256 set: c68284c56e64a505
```

## Judges

```
a332e069f38699c190d3565cd2abc9d8f98d53ac7e1b057053f3a75d7850e290  score2.py
6d4f6c7bb0e5b5c377fe314e58602191db1dbbb6d253506811faef35d94be292  score2-selftest.sh
a0f9877df2d5d1699f83ca23228ed0e0f9cc5b9701903ef51a4b3474fa52a14c  score2-drain-selftest.sh
527c141ccb13be4ec01a834fbbac05894354ff85a7a115e88bdc5c07ba7e504b  dual-run.sh
0aa94a3c70e61255f48d56a839d650049412557c8b2f832934be345a0fac7739  dual-all.sh
2df8eb673545192f635650cf28c71682243a66d059e1d770fea27dfe67c2fe91  atomic-rerun.sh
09e501bfe4b20b40999a634b3836bc94d2f4e3a9a12d1baf655e5c498ee05a0a  rd2-regress.sh
c7a47b85227c97a19946eebe29f73bbe935ca3acc97eeeb23208562552206e95  probe_console.py
6b25d66b6b12f0aa55038c38f6e33ecaa25ebca2bbe974205a166c7992d25d12  compare-probes.py
d8da9f5c4badc5544e7a9419888009048fcf09356c47afa479f6c3a209d3518d  rd2-probes.sh
b15edce3366adfe09f1faf69792993817210ec6a44585a89dabc378f01726d35  elf_ident.py
2f9c51206982f1cb09fe63b0cfd5da7c8a799dc071e7437904dfd1ba3a9d5983  freeze-elfs.sh
CPU-A score.py (original, read-only): 16cab22ffe8df97f
```

## Tools

```
Verilator 5.022 2024-02-24 rev conda-forge build 1
Python 3.10.14
docker image for sbt: vivado-env:2025.2-sw (612322e4185a), java-8 inside
sbt-launch: 4a3f4cda74c03aab
```
