# MC-M1 REPORT — 可替换 hart 封装,单核不退化

claude,2026-09-26,答 `codex-mc-m1-single-wrapper`。**单核、仅 multicycle;不是双核后端,不是板操作。**

未做的事(按任务禁令):未做 Vivado;未碰 board/serial;未改 xv6/host;未改原 `ips-*` worktree、冻结镜像或用户磁盘;未 push,未建 tag。共享的 `teaching-cpu-work/fpga-zynq` 树**未写入**(证据见 §2)。

> 本文在测试链运行期间逐段写成;每个数字后面都标注它来自哪个日志。未完成项在 §9。

---

## 1. 交付物与复跑入口

| 项 | 位置 |
| --- | --- |
| 代码 | worktree `worktrees/mc-single-wrapper`,分支 `mc-single-wrapper`,基于 `ips-v1-icache`(`c16306b`),提交 **`bcf403e`** |
| 本报告 / 测试表 / manifest | `experiments/multicore/m1/{REPORT.md, RESULTS.md, MANIFEST.md}` |
| 每条测试的入口 | `experiments/multicore/m1/tests/*.sh`,§4 逐条给出 |
| 生成/构建链 | `experiments/multicore/m1/gen/{prepare-common.sh, gen.sh, chain-*.sh}` |
| 原始日志 | `experiments/multicore/m1/runs/`,每个 run 自带 `exit`、`inputs.sha256`/`identities.txt`、日志 |

复跑一切(顺序即依赖):

```bash
M1=/home/engineer/fpga/experiments/multicore/m1
bash $M1/tests/hartid-tb/run.sh  worktrees/mc-single-wrapper/rtl/cpu  <out>          # T1.1
bash $M1/tests/lint-stable-obs.sh worktrees/mc-single-wrapper/soc/scala/teaching       # T1.3
bash $M1/gen/prepare-common.sh   worktrees/ips-cache/soc/scala/teaching        $M1/gen/common-before
bash $M1/gen/prepare-common.sh   worktrees/mc-single-wrapper/soc/scala/teaching $M1/gen/common-after
bash $M1/gen/gen.sh RD2Harness RD2AtomicXv6FastConfig $M1/gen/common-{before,after} <out>   # 各一次
bash $M1/gen/gen.sh RD2Harness RD2AtomicBootConfig    $M1/gen/common-{before,after} <out>
bash $M1/tests/freeze-elfs.sh <elfdir>                                                  # 一次冻结程序集
ELFDIR=<elfdir> [ONLY="..."] bash $M1/tests/rd2-probes.sh <gen.v> worktrees/mc-single-wrapper/rtl/cpu <label> <out> [trace]
python3 $M1/tests/compare-probes.py <before-out> <after-out> --expect all|short [--trace] # T1.7
bash $M1/tests/checker-selftest.sh                                                       # 判定器变异自测
python3 $M1/tests/roi-compare.py <before-out> <after-out> <combined>                     # T1.8
bash $M1/tests/run-xv6-m1.sh <after gen.v> worktrees/mc-single-wrapper/rtl/cpu <out>     # T1.10
bash $M1/tests/core-suites/run-cpu-{su,sv39,a,m,c}-rtl.sh <rtl-dir> <out>                # T1.4
bash $M1/tests/atomic-soc-subset.sh $M1/gen/common-after <out>                           # T1.5
```

---

## 2. 构建输入(manifest 摘要;全文 `MANIFEST.md`)

### 2.1 代码身份

| 项 | 值 |
| --- | --- |
| 基线 | tag `ips-v1-icache` → `c16306bcfb40…`;worktree 从它新建,`git diff --stat` 对 `rtl/ soc/` 在改动前为空 |
| 改动 | `rtl/cpu/tcpu_core.v`(+HART_ID 参数,传给 csr)、`rtl/cpu/tcpu_csr.v`(mhartid 读 HART_ID)、`soc/scala/teaching/TeachingCpuBlackBox.scala`(hartId、观察拆分)、`soc/scala/teaching/RD2Soc.scala`(hart 实例化、require、3 个 unsupported 配置)、新 `soc/scala/teaching/TeachingHart.scala` |
| 提交 | `bcf403e`,工作树干净 |
| 工具 | Verilator 5.022;`riscv64-unknown-elf-gcc (gc891d8dc23e) 13.2.0`;sbt 经 `vivado-env:2025.2-sw` 镜像内 java-8(与 `m3-gen.sh`/`atomic-run.sh` 同一路径) |

### 2.2 生成器怎么跑的,以及共享树为什么没被碰

`common/Makefrag` 的生成规则在 `$(common)` 里跑 sbt,源就是 `$(common)/src/main/scala`——也就是 `teaching-cpu-work/fpga-zynq/common`,前几个阶段都在那里就地改。MC-M1 不写它:`prepare-common.sh` 复制出一份**私有 common**(Makefrag、project、lib 里打包好的 rocket-chip jar、非 teaching 的 scala),把 `teaching/` 换成指定目录;`gen.sh` 以 `common=… common_build=…` 覆盖 make 变量,输出落在私有目录的 `build/`,从不进 `simulation/src/verilog`。

第一次跑失败:`NoSuchFileException: ../common/src/main/resources/teaching/bootrom.teaching.rv64.img`——`WithTeachingBootROM` 用的是相对 `$(common)` 的路径。修法是一个**只读**符号链接 `experiments/multicore/m1/gen/common → fpga-zynq/common`,让相对路径解析到共享资源;不复制、不改写。

共享 scala 树 36 个文件的哈希在开工前记录(`gen/shared-scala-before.sha256`),之后逐次核对:**未变**。`simulation/src/verilog/` 下的预生成文件 mtime 仍为 09-19。

### 2.3 生成物

| 生成物 | 来源 scala | sha256 前 16 | 耗时 |
| --- | --- | --- | ---: |
| `RD2Harness.RD2AtomicXv6FastConfig.v`(BEFORE) | tag | `ed021fc06606fc51` | 31 s |
| `RD2Harness.RD2AtomicBootConfig.v`(BEFORE) | tag | `12fffa5c2348dff0` | 38 s |
| `RD2Harness.RD2AtomicXv6FastConfig.v`(AFTER) | wrapper | `c36829afc4e3c6cd` | 27 s |
| `RD2Harness.RD2AtomicBootConfig.v`(AFTER) | wrapper | `5c2801ed9d07d0f2` | 39 s |

**wrapper 的足迹**(BEFORE→AFTER,归一化临时名后逐模块比较,`RD2AtomicXv6FastConfig`):150 → 151 个模块;新增 `TeachingHart`(430 行);`RD2ZynqTop` 改 539 行(2689→2448:CPU/桥/watch 的实例化移入 hart);`TeachingCpuV2` 改 2 行;**其余 147 个模块逐字相同**。BlackBox 实例化为 `tcpu_core #(.RESET_PC(65600), .MISA_A(1), .HART_ID(0))`。

### 2.4 一个必须报告的发现:共享预生成 `.v` 比 scala 旧

`simulation/src/verilog/RD2Harness.RD2AtomicXv6FastConfig.v` 生成于 **09-19 22:48**;`AtomicBackend.scala`、`RD2Soc.scala`、`RD2Watch.scala`、`RD2Serial.scala` 的 mtime 是 **09-20 05:50–05:53**。已验收的单核 xv6 仿真记录(`IPS-campaign/runs/xv6-cache`,09-25 构建)用的是这份 09-19 的 `.v`(`run-xv6.sh` 里 `GEN=` 指向它),其 `identities.txt` 只记录了 `tcpu_core.v` 与 sim 二进制的哈希,**没有记录生成 Verilog 的身份**。

把它和从 tag scala 重生成的 BEFORE 逐模块比较(归一化后):148 个模块相同;`AtomicBackend` 差 183 行——全部来自一个 **`reg [31:0] cyc`** 及其临时量(无 trace 配置下不再保留的周期计数器);`RD2ZynqTop` 差 20 行——两个寄存器 `bdevWrPrev/bdevRdPrev` 变成匿名 `_T_`,逻辑相同。**没有行为差异。** 因此该记录仍然有效,但它的"生成物身份缺失"是个过程缺口:建议以后每个仿真记录都把生成 `.v` 的哈希写进 `identities.txt`(本包的 `rd2-probes.sh`/`run-xv6-m1.sh` 都记了)。板上比特流的 netlist 输入 `RD2BoardTop.RD2AtomicBoardConfig.v` 生成于 09-25,晚于那四个 scala,不受此影响。

---

## 3. 每个入口覆盖什么(任务第 1 条)

| 入口 | 经过 TeachingHart? | 覆盖 |
| --- | --- | --- |
| T1.1 `hartid-tb` | 否 | `tcpu_core`+`tcpu_csr` 的 HART_ID 贯穿,核级 |
| T1.2 四个单元台 | 否 | `tcpu_tlb/icache/ifill/xlate` 子模块(RTL 未改) |
| T1.3 lint | — | SoC 层 scala 文本 |
| T1.4 核级 ISA 套件(su/sv39/a/m/c) | 否 | `tcpu_*` 经 `teaching-cpu-work/cpu/tb` 台;**tag RTL 与 wrapper RTL 各跑一次**以归因 |
| T1.5 atomic SoC 子集 | 否(`AtomicZynqTop` 直接实例化 `TeachingCpuV2`) | BlackBox 改动 + RTL + 未改的 AtomicBackend/RD2BridgeV2 |
| T1.6 R-BOOT 门 | **是** | drain 契约经 wrapper 的 `drain` 透传 |
| T1.7 探针 + trace 比较 | **是** | boot/ext/AMO/Sv39/TLB/I-cache 探针,BEFORE vs AFTER |
| T1.8 ROI | **是** | 四微基准 |
| T1.9 unsupported | — | elaboration 期拒绝 |
| T1.10 xv6 b0apps | **是** | 单核 xv6 功能回归 |

---

## 4. 结果(逐条;`RESULTS.md` 为表格版)

### T1.1 HART_ID(`runs/t1.1-hartid`)— **3/3**

`HART_ID=0` 读 0;`HART_ID=5` 读 5;**负向控制** `HART_ID=5` 期望 0 → `TEACHING-MC1-HARTID-FAIL`(证明检查能失败)。同一 `tcpu_core.v`。

### T1.2 单元台(`runs/t1.2-unit-benches`)— **4/4**

`TLB_TB_OK`、`ICACHE_TB_OK`、`IFILL_TB_OK`、`XLATE_AMO_TB_OK`,从本 worktree 的 tests 目录运行,RTL 解析到本 worktree。

### T1.3 稳定观察接口 lint(`runs/t1.3-lint.txt`)— **0 命中,负向控制命中 1**

SoC 层 scala 无 `.impl.`/`dbg_state`/`dbg_redirect`/`obs.state` 引用;在副本里种一处引用,lint 抓到。

### T1.9 unsupported 配置(`runs/gen-unsupported-*`)— **3/3 拒绝,消息含值**

```
unsupported CORE_IMPL=pipeline: only 'multicycle' is implemented
unsupported NUM_CORES=2: MC-M1 implements exactly 1 (multicore identity is MC-M2)
unsupported NUM_CORES=0: MC-M1 implements exactly 1 (multicore identity is MC-M2)
```

### T1.4 核级 ISA 套件(`runs/t1.4-core-*`)

| 套件 | tag RTL | wrapper RTL | 结论 |
| --- | --- | --- | --- |
| su | `fails=9` | `fails=9` | **归类:参考(tag RTL)与新实现同样失败**——两侧 37 行结果逐字相同。失败的是 `su08_satp_bare`、`su09_warl`、`su11_mip_sw`(各三种存储 profile,自报检查号 1/8/24)。**未诊断,明确延期**(D2):本包没有查这三个检查号对应什么,不声称它们是旧期望 |
| sv39 | 首跑:构建失败 `oldptw`;重跑:**`fails=0`** | 同,**`fails=0`,66 行结果逐字相同** | 首跑失败的是 `oldptw` 负向控制:它把 pre-Sv39 的 `tcpu_ptw.v` 换进构建,而 cache RTL 的 `tcpu_xlate` 驱动它没有的引脚(`leaf_ppn/leaf_level/leaf_r/leaf_w`)→ `PINNOTFOUND`——**对 TLB/cache 核不适用**,不是失败。在 m1 的副本里改为"不适用即跳过"(原套件未动)后重跑:六个 Sv39 程序 × 三种存储 profile 全过,`sv01..sv06`、`sv09` 的退休记录三 profile 逐条相同(495/376/1205/1670/557/683/2220 条),两个 oldptw 场景显式 SKIP |
| a | `scenarios=17 infra=0 fails=0` | `scenarios=17 infra=0 fails=0` | 原子核级回归两侧全过 |
| m | `fails=6` | `fails=6`,**88 行结果逐字相同** | **归类:参考与新实现同样失败**。逐项:**有源码证据的旧期望**——`m01` 检查 410 是 `csrr t0, misa; li t6, -9223372036854771456; CHECK_EQ_R(…, 410)`(`cpu-m/tests/m01_muldiv.S:2060-2062`,即 misa 必须等于 `0x8000000000001100`,只有 I+M),cache 核读 `0x…141104`;`corereset-mul/div` 运行同一程序;`m23/csr-warl` 的日志自报 `CSR CHECK FAIL: misa = 0x8000000000141104, expected 0x8000000000001100`。**未逐项核实、延期**——`m23/csr-illegal`(`TRAP COUNT FAIL: 4 traps, expected 6`;S 模式 CSR 存在导致陷入减少是推测)、`m23/jump-targets`(`CAUSE FAIL: last cause 2`)、`m23/fault-stale-i01`(`INTERRUPT COUNT FAIL: 2, expected 1`)。乘除法本身、IRQ 落在 `S_MUL`、核复位落在乘除中、两个负向控制:全部通过 |
| c | `fails=16` | `fails=16`,**99 行结果逐字相同** | **归类:参考与新实现同样失败**。逐项:**有源码证据的旧期望**——`c01` 检查 34 是 `la t0, misa_expect; csrr t1, misa; …; CHECK_EQ_R(t1, t2, 34)`(misa 期望常量),`corereset-if2-c01` ×3 运行同一程序,`m01` 410 同 m 行,`m23/csr-warl` 日志自报 misa 不符。**机制推断、未逐项核实、延期**——`irq-if2req`/`irq-if2resp` 超时:注入器 `+expect-fire-state=IF2_REQ`/`IF2_RESP` 等待第二个取指 parcel 的状态(`run-cpu-c.sh:45-46,93`),我推断 fetch32 后对齐 32 位指令只发一次取指故该状态不再出现,但未在本包内验证;`m23` 另 2 项同 m 行延期。C 指令本身、跨页 straddle、非法 parcel、`c.ebreak`、取指错误、核复位 mid-fetch、负向控制:全部通过 |

### T1.5 atomic 后端的 SoC 场景(`runs/atomic-soc-subset/*/score.txt`)— **4/4:三个正向 score=0,负向被声明的签名拒绝**

从私有 `common-after`(即 wrapper 的 scala)生成 `AtomicSocHarness.<cfg>.v`,按 `atomic-run.sh` 的 `run_one` 步骤 verilate、运行、用已验收的 `score.py` 评分:

| 场景 | 配置 | sim | score | 计数 |
| --- | --- | --- | --- | --- |
| soc-amo-race | `AtomicSocAmoRaceConfig` | 0 | 0 | amo=16 ext=16 cpu_tx=34 |
| soc-lrsc-race | `AtomicSocLrscRaceConfig` | 0 | 0 | scok=2 scfail=4 kills=4 ext=5 |
| soc-partial | `AtomicSocPartialConfig` | 0 | 0 | amo=12 scok=6 ext=10 |
| soc-neg-no-kill(负向) | `AtomicSocNegNoKillConfig` | 0 | 1 | `FAIL: 30: SC result scfail=0, model says 1` —— 正是声明的签名 |

覆盖边界(§3):这些场景经 `AtomicZynqTop` 直接实例化 `TeachingCpuV2`,覆盖 BlackBox 改动(hartId、观察拆分)、RTL 与未改的后端/桥,**不经 TeachingHart**;wrapper 由 T1.6–T1.8、T1.10 覆盖。

### T1.6 R-BOOT 门:drain 契约经 wrapper(`runs/rboot-before.log`,`runs/rboot-after.log`)— **两侧 `RBOOT_DONE fails=0 infra=0`,九条门逐行相同**

`restart-boot/scripts/rboot-run.sh`(`MAXCYC=300000 WALL=900`)分别对 BEFORE 与 AFTER 的 tracing 仿真器运行:

| 门 | before | after |
| --- | --- | --- |
| g1-boot05-fixed | sim=0 check=ok | sim=0 check=ok |
| g2-read-inflight / g2-write-inflight / g2-queued-unconsumed | sim=0 check=ok ×3 | 同 |
| g2-read-target-neg(负向) | sim=2 check=ok | 同 |
| g3-three-rounds | sim=0 check=ok | 同 |
| g4-stuck-device / g4-late-recovery(超时失停) | sim=2 check=ok ×2 | 同 |
| g4-counterexample | rejected, as it must be: READY never happened | 同 |

软复位请求经 wrapper 的 `drain` 透传到桥,`cpuResetHold` 在 wrapper 内与 `reset` 组合驱动 CPU——R-BOOT 的重启、drain、块设备 hold/flush 与失停在 wrapper 后行为不变。

### T1.7 RD2 集成探针,BEFORE vs AFTER(`runs/probes-*`,`runs/compare-*-recovered.txt`)

两个仿真器都是**本包新构建**的:`build-xv6-sim.sh`(Verilator 5.022,`-O3 -j4`)以本 worktree 的 RTL 分别对 BEFORE 与 AFTER 的生成 Verilog 构建,`sim/inputs.sha256` 记录了生成 `.v`、每个 RTL 文件与 sim 二进制的哈希;AFTER 的 `.v` 含 `module TeachingHart`,BlackBox 实例化带 `.HART_ID(0)`。构建 17 s(trace-free)/ 70 s(tracing)。

**trace-free 配置(`RD2AtomicXv6FastConfig`),18 个程序,两侧全部 `exit=0` 且各自的 OK 标记出现;完成周期数 18/18 逐个相等:**

| 程序 | 标记 | 周期(before = after) |
| --- | --- | ---: |
| boot01_marker / boot02_clint / boot03_ddr / boot04_badaddr | `TEACHING-CPU-M3-OK` / `M3-CLINT-OK` / `M3-DDR-OK` / `M3-BADADDR-OK` | 6 386 / 44 469 / 16 323 / 6 895 |
| ext01_m / ext02_c / **ext03_a** / ext04_sv39 | `TEACHING-EXT-{M,C,A,SV39}-OK` | 7 021 / 6 460 / **7 154** / 17 834 |
| boot11_sv39 / **boot12_amo** | `M3-SV39-OK` / **`M3-AMO-OK`** | 45 709 / **49 519** |
| tlb01_sfence / tlb02_canonical / cache01_smc | `TEACHING-TLB-SFENCE-OK` / `TEACHING-TLB-CANON-OK` / `TEACHING-CACHE-SMC-OK` | 31 432 / 51 894 / 9 009 |
| perf02_sv39 / perf03_fetch / perf04_where / perf06_iws | `TEACHING-PERF-*-OK` | 1 739 980 / 406 606 / 544 525 / 1 103 822 |
| hello.riscv | `PASS` | 10 293 |

`ext03_a`(原子扩展探针)在这个带原子后端的 RD2 harness 上**完成并通过**;IPS 战役的仿真门用的是无原子路径的 V1 harness,那里它跑不完——两者不矛盾。`boot12_amo`(S 模式 Sv39 自旋锁、LR/SC 循环、跨 ROM/TSI/DDR/HTIF 的 AMO)通过,即"含 AMO、Sv39"。

**tracing 配置(`RD2AtomicBootConfig`),13 个短程序:COMMIT/TRAP 序列(去周期号)13/13 逐条相同**,包括 `boot02_clint`(6 856 条退休/陷入记录,含定时器中断)——异步事件在两侧落在同一位置;探针自身的控制台文本相同;完成周期相同。这是任务第 4 条"固定可控输入时比较退休/异常/内存效果"的直接证据;内存效果由每个探针自己的校验(标记)覆盖。

两处工具缺陷,如实记录:① `rd2-probes.sh` 的 `summary.txt` 把周期数记成了路径里的数字(grep 跨两个文件带上了文件名前缀),已用 `tools/fix-summary.sh` 从控制台重算为 `summary-fixed.txt`,原文件保留;② tracing 配置下 harness 把探针的 HTIF 字符与自己的 `AT/RD2/RBOOT` 行交错输出,聚合器保留的控制台里标记被拆散,`rd2-probes.sh` 的逐程序判定因此对 13 个程序都报"无标记"(**假失败**,`exit=0` 说明程序自己是成功退出的);`tests/compare-probes.py` 用 `run-soc-a.sh` 同样的方法(剥掉 trace 行文本再拼接)恢复了控制台,13/13 标记齐全。两个判定都在 `runs/compare-*-recovered.txt`。

比较脚本报 `fails=1`:**只有**"programs identical"一项——`boot11_sv39.elf`/`boot12_amo.elf` 是每次运行现场用 gcc 构建的,两次构建的 ELF **文件**哈希不同;查明差异只在 ELF 元数据里 gcc 的临时目标文件名(`ccbtV2Su.o` vs `ccJKxNc9.o`),**`objcopy -O binary` 得到的加载镜像(.text/.data)逐字节相同**。其余 16 个程序是冻结二进制或可重复构建,哈希一致。所以比较的输入确实固定;这一项计为工具的 manifest 缺口(应记录加载镜像哈希而非 ELF 哈希),不是输入差异。

### T1.8 四微基准 ROI,BEFORE → AFTER(`runs/roi-compare.txt`)

用战役自己的提取器(`gen_stage_metrics.py`:周期取自探针的计数器读数,退休数按工作负载描述符核对):**12 个 ROI,12 个 Δ = 0,0 个拒绝**。

| ROI | 周期 | CPI |
| --- | ---: | ---: |
| perf02 bare_alu / bare_load | 180 026 / 251 294 | 6.00 / 8.38 |
| perf02 k4_alu / k4_load | 240 016 / 332 496 | 8.00 / 11.08 |
| perf02 mega_alu / mega_load | 240 016 / 332 488 | 8.00 / 11.08 |
| perf03 insn16 / insn32 | 180 033 / 180 026 | 6.00 / 6.00 |
| perf04 load_clint / load_dram | 250 012 / 251 273 | 8.33 / 8.38 |
| perf06 iws_exceeds / iws_resident | 629 903 / 420 136 | 9.58 / 6.00 |

零差异符合预期:wrapper 没有改任何时序路径(§5)。按任务第 5 条,零差异**不是**功能回归的替代——功能回归是 T1.7 的标记与序列、T1.10 的 xv6。

### T1.10 单核 xv6 `b0apps`,经 wrapper(`runs/xv6-after`)— **`XV6_RC=0`,`BOARD_RUN stages=6 failed=0 host_exit=0`,三应用校验和与板上记录一致**

仿真器:AFTER 生成物 `c36829afc4e3c6cd…` + 本 worktree RTL,`build-xv6-sim.sh` 构建 20 s;内核 `kernel-4mib` `6ad5c233…`、原始磁盘 `6bdd8148…` **先核哈希再用**,每次新拷贝;经生产 runner(`board-runner.py --workload b0apps`,`--channel multiplexed`)驱动,与已验收的 `runs/xv6-cache` 记录同一条路径。

| 阶段(`stages.txt`) | 墙钟 s |
| --- | ---: |
| kernel banner | 4.1 |
| init started / first prompt | 513.7 |
| shell prompt | 574.9 |
| command b0compute | 727.2 |
| command b0array | 911.8 |
| command b0file | 2607.1 |

`# host exit: 0`,`# stop: deliberate-stop-after-all-commands`,`# remote exit confirmed: yes`。校验和:`B0-COMPUTE-CHECKSUM=5ADF55920BF7696`、`B0-ARRAY-CHECKSUM=88133D5BD386DB60`、`B0-FILE-CHECKSUM=62E55F5326378000`——与板上 B0 战役记录(`b0-apps-board`)三者逐一相同。已验收的检查器对本次运行:**`XV6_CHECK segments=4 prompts=4 stages=6 console_bytes=625 fails=0`**(`runs/xv6-after/check.txt`),与 `runs/xv6-cache` 记录的 `fails=0` 同款。

会话总周期 **464 079 384**(墙钟 2 609 s,约 178 k cycles/s)。已验收的 `runs/xv6-cache` 记录是 463 881 498——差 0.04 %。**这不是受控比较,也不作 IPS**:xv6 会话是主机交互式的,周期随会话而变(`XV6-COMPARISON.md` 自己就这样声明),而且那份记录用的是 09-19 的共享生成物(§2.4)。它只说明:wrapper 下的单核 xv6 走完了同一条生产路径、同样的三件应用、同样的校验和。

---

## 5. 设计要点(为什么这样切)

* **HART_ID 是参数不是端口**:每个实例编译期确定,与 RESET_PC 同层;BootROM 第一条分支就读 `mhartid`,所以它是双核的前提而非装饰。
* **观察接口拆成两层**:`TeachingCpuObs`(commit/trap/pc/irqEnabled/isFetch/halted)是任何 CORE_IMPL 都必须发布的契约;`TeachingCpuImplObs`(FSM state、redirect)是多周期实现细节,只给核内测试用,SoC 层禁止引用(lint)。`isFetch` 留在契约里,因为 SoC 的 `busy` 定义依赖它。
* **TeachingHart 只是边界,不是行为改动**:client 名 `teaching-phys`、单侧带、AtomicBackend、桥、watch/throttle、响应时延、TLB/I-cache 容量全部原样;软复位 `reset || cpuResetHold` 在 hart 内组合,与原来一致。`require(hartId == 0)`——接受 hart 1 会让 CONTRACT B1 的错误 SC 语义 elaborate 出来,所以拒绝。
* **V1 路径一字未动**:`atomic = false` 的配置走原来的 `RD1Bridge + TeachingCpu`,`RD2BootConfig`/故障配置照旧。

---

## 6. 与任务条款的对照

| 条款 | 位置 |
| --- | --- |
| 1 manifest / commit / dirty / 工具 / 每入口覆盖 | §2、§3、`MANIFEST.md` |
| 2 HART_ID、unsupported、lint、握手与异常回归 | T1.1、T1.9、T1.3、T1.4/T1.7 |
| 3 单元台、ISA/特权/原子回归、桥 drain | T1.2、T1.4、T1.5、T1.6 |
| 4 新构建 RD2 集成仿真经 TeachingHart,boot/ext 探针含 AMO、Sv39,固定输入比较 | §2.3(生成物身份)、T1.7 |
| 5 四微基准 ROI 前后周期差 | T1.8 |
| 6 单核 xv6 b0apps,内核/磁盘哈希固定 | T1.10 |
| 7 命令、退出码、日志、未完成项 | `runs/`、§9 |

---

## 7. 裁决请求

| # | 事项 | 建议 |
| --- | --- | --- |
| D1 | 共享预生成 `.v` 未被记录身份(§2.4) | 以后仿真记录写入生成 `.v` 哈希;本包已如此 |
| D2 | SU 套件三程序在 cache RTL 上失败(先于 M1) | 另立小任务诊断;不阻塞 M1 |
| D3 | sv39 的 `oldptw` 控制对 TLB/cache 核不适用 | 在原套件里同样改为"不适用即跳过"(原套件未动) |

---

## 8. 超时与预算(实际)

| 步骤 | 预算 | 实际 |
| --- | --- | --- |
| 生成(每配置) | 墙钟 10 min | 27–39 s(sbt + firrtl,私有 common) |
| 单元台 | 各 5 min | 3–9 s |
| 核级套件 | 各 15 min | su/sv39/a 40–44 s;m 122 s;c 156 s |
| RD2 仿真器构建 | 墙钟 30 min | 17 s(trace-free)、70 s(tracing)、20 s(xv6) |
| RD2 探针每程序 | 墙钟 1800 s;周期预算 `cycles_for`(boot 4 M、ext/AMO/Sv39 6 M、perf02 60 M、perf06 18 M、perf03/04/tlb 12 M、cache01 6 M、ext03_a 40 M) | 最长 perf02 9 s(1.74 M 周期);其余 ≤ 5 s |
| R-BOOT 门 | `MAXCYC=300000 WALL=900` | 两侧各约 3 min |
| atomic SoC 子集 | 每场景 gen + verilate + run(`+max-cycles=800000`,墙钟 900 s) | 四场景共约 8 min |
| xv6 | 墙钟 4 h;2e9 周期;stage 7200 s | **2 609 s,464 M 周期** |

所有超过 2 分钟的工作都以 coord job 运行(`mc-m1-gen-*`、`mc-m1-chain-{all,runs,tail,sv39}`、`mc-m1-unit-benches`),一次一个重型任务;编译 ≤ 4 worker(verilator `-j 4`/`-j 3`/`-j 2`);无重试。

---

## 9. 未完成项与工具缺陷(如实)

**实际状态**:任务第 1–7 条每项都有结果与日志;**延期项**(不在本包诊断):su 三程序、m 三项、c 两项(T1.4 表逐项标注)。这些是参考实现与新实现同样失败的旧套件项,不是本包引入的,但也**不全是已核实的旧期望**。

**过程中发现并记录的工具缺陷(均已在本包内处理,不影响结论):**

1. `rd2-probes.sh` 的 `summary.txt` 把完成周期记成了路径里的数字(`grep` 跨两个文件带上文件名前缀)。已用 `tools/fix-summary.sh` 从控制台重算为 `summary-fixed.txt`,原件保留;REPORT 与 RESULTS 引用重算值。
2. tracing 配置下 harness 把探针的 HTIF 字符与 `AT/RD2/RBOOT` 行交错输出,`rd2-probes.sh` 的逐程序判定对 13 个 tracing 运行报"无标记"(**假失败**;它们的 `exit=0` 是程序自己成功退出)。`tests/compare-probes.py` 按 `run-soc-a.sh` 的方法恢复控制台后 13/13 标记齐全;两个判定都留在 `runs/`。下一包应把这个恢复放进 `rd2-probes.sh` 本身(本包运行期间不能改正在执行的脚本)。
3. 每次运行现场 gcc 构建的 `boot11_sv39.elf`/`boot12_amo.elf` 文件哈希不可重复(ELF 元数据里的临时目标文件名),加载镜像逐字节相同。manifest 应记录加载镜像哈希。
4. 共享预生成 `.v` 的身份从未被记录(§2.4)。

**磁盘**:`experiments/multicore/m1/runs` 2.3 GB(六个 Verilator 仿真器与 atomic 子集的四个),`gen/` 272 MB(两份私有 common,各含 45 MB 的 rocket-chip jar)。不在 `/tmp`。

---

## 10. 验收闭环(答 `codex-mc-m1-verification-closeout`)

六项必修,每项给出改在哪里、怎么证明。**"重跑"与"仅重评"分开标注。**

| # | 要求 | 改动 | 证据 |
| --- | --- | --- | --- |
| 1 | 周期误解析与 trace 控制台恢复进入口本身;统一恢复函数 | `tests/probe_console.py`:唯一的读取/恢复/判定模块(逐行判断是否带 trace 文本:带则为片段、不带则保留换行;显式的每程序预期标记表 `EXPECT`;判定 = exit 0 ∧ 预期标记在 ∧ 无任何 `-FAIL`/`FAIL` ∧ 有周期数)。`rd2-probes.sh` 的 summary 与 verdict 都调用它;`tests/retired/compare-probes.sh` 退役 | 重跑:§10.2 |
| 2 | 比较器不只判相等 | `tests/compare-probes.py` 重写:两侧各自必须 ok(见上);程序集合与 `--expect` 集合**完全相等**(无多无缺非空);`--trace` 下每个运行必须有非空 `commits.txt`,缺即拒;周期缺失即拒;周期差只报告 | `runs/checker-selftest.txt` |
| 3 | ELF 身份 | 采纳"一次构建冻结、两侧复用":`tests/freeze-elfs.sh` 产出 `elf.sha256`(整文件)与 `elf-load.sha256`(`tests/elf_ident.py`:entry、每个 PT_LOAD 的 vaddr/paddr/filesz/memsz/flags/文件字节/零填充、`tohost`/`fromhost`/`_start`/`htif_*` 符号地址,纯 Python);`rd2-probes.sh` 以 `ELFDIR=` 复用并校验;比较器两者都比 | 自测:改入口、改内容各自改变摘要;对真实探针 strip/加 note 改变整文件 sha 而**不**改变加载摘要 |
| 4 | hartid tb 判退出码;真正省略参数的默认值 | 实测本机 Verilator:`$finish(1)` 退出 0、`$fatal` 退出 134,故失败路径改用 `$fatal`;`run.sh` 四例 `omitted-default`(无 `-GHART_ID`)、`explicit-0`、`nonzero-5`、`negctl-5-vs-0`,每例要求构建成功、退出码等于该例声明值(0 / 134)、标记匹配;124 永不算通过 | 重跑:§10.2 |
| 5 | checker 变异测试 | `tests/checker-selftest.sh`:合成 before/after,基线必过,变异各自被拒且原因对应——两侧同样非零退出、缺一个/全部程序、多余程序、去掉 trace、成功后追加 FAIL、错误标记、去掉周期、改 ELF 入口、改 ELF 内容;另测 `elf_ident` 对入口/内容敏感、对元数据不敏感;`probe_console` 对 124 拒绝 | **16/16**,`runs/checker-selftest.txt`。写它时抓到自己一个 bug:恢复函数原先把所有行无分隔拼接,相邻标记会粘成一个 token(case 5 先失败后修) |
| 6 | REPORT 实际状态 | §9 改为实际状态;T1.4 的 su/m/c 只归类"参考与新实现同样失败",有源码证据的逐项列出,其余标明延期 | §4、§9 |

### 10.1 仅重评(原始记录不动)

原始记录 `runs/probes-{before,after}-{fast,trace}` 过新比较器(`runs/reeval-*.txt`):逐程序判定全部 ok/ok/same,**但被拒**——`boot11/boot12` 当时逐次现场构建、整文件 sha 不同,且当时没有加载摘要文件。这正是新比较器该做的事:旧记录不能靠"两侧相等"过关,输入身份必须闭合。

### 10.2 重跑(新目录,原记录保留)

### 10.2 重跑(`runs/closeout2-*`,新目录,原记录保留)

**程序集一次冻结**(`runs/closeout2-elf`,`freeze-elfs.sh`):18 个程序,`elf.sha256`(整文件)与 `elf-load.sha256`(加载摘要)同时记录;`rd2-probes.sh` 以 `ELFDIR=` 复用并在拷贝后核对整文件 sha。摘要头两行:

```
69ca91994567a44f9afb0303013bb8412eb6142749c28b631000e92156da61a2  boot01_marker.elf
0c4ebbb7648a34c013bbf77b0c7a5f03f901993fbe0e690732c46f15f8fb2c0f  boot02_clint.elf
--- load identity ---
4aaa53ed02ceb5373481999cfefd019e984d92dfb433f8187c4f3e2287656c88  boot01_marker.elf
317741f09ea55f07ce5707c463b850b83d75e60c3dbc32d55744c1332a56c28b  boot02_clint.elf
```

**四组短探针经正式入口**(修复后的 `rd2-probes.sh` → `probe_console.py` 判定):

```
PROBES label=before fails=0
PROBES label=after fails=0
PROBES label=before fails=0
PROBES label=after fails=0
```

**trace-free(`RD2AtomicXv6FastConfig`),`compare-probes.py --expect short`**(`runs/closeout2-compare-fast.txt`):

```
programs (whole-file sha256): identical (13 files)
programs (load-semantic identity): identical (13 files)
rtl:      identical (tcpu_core.v 66fa67036efd3ef0)
generated: ed021fc06606fc51 (before) vs c36829afc4e3c6cd (after) -- the one intended difference
program set: 13 expected, before has 13, after has 13
```

| 程序 | 预期标记 | before | after | 控制台 | trace | 周期 |
|---|---|---|---|---|---|---|
| boot01_marker | `TEACHING-CPU-M3-OK` | ok | ok | same | (untraced) | 6386->6386 (d=+0) |
| boot02_clint | `M3-CLINT-OK` | ok | ok | same | (untraced) | 44469->44469 (d=+0) |
| boot03_ddr | `M3-DDR-OK` | ok | ok | same | (untraced) | 16323->16323 (d=+0) |
| boot04_badaddr | `M3-BADADDR-OK` | ok | ok | same | (untraced) | 6895->6895 (d=+0) |
| ext01_m | `TEACHING-EXT-M-OK` | ok | ok | same | (untraced) | 7021->7021 (d=+0) |
| ext02_c | `TEACHING-EXT-C-OK` | ok | ok | same | (untraced) | 6460->6460 (d=+0) |
| ext04_sv39 | `TEACHING-EXT-SV39-OK` | ok | ok | same | (untraced) | 17834->17834 (d=+0) |
| boot11_sv39 | `M3-SV39-OK` | ok | ok | same | (untraced) | 45709->45709 (d=+0) |
| boot12_amo | `M3-AMO-OK` | ok | ok | same | (untraced) | 49519->49519 (d=+0) |
| hello | `PASS` | ok | ok | same | (untraced) | 10293->10293 (d=+0) |
| tlb01_sfence | `TEACHING-TLB-SFENCE-OK` | ok | ok | same | (untraced) | 31432->31432 (d=+0) |
| tlb02_canonical | `TEACHING-TLB-CANON-OK` | ok | ok | same | (untraced) | 51894->51894 (d=+0) |
| cache01_smc | `TEACHING-CACHE-SMC-OK` | ok | ok | same | (untraced) | 9009->9009 (d=+0) |

```
COMPARE fails=0  (cycle deltas are reported, not judged)
```

**tracing(`RD2AtomicBootConfig`),`compare-probes.py --expect short --trace`**(`runs/closeout2-compare-trace.txt`):

```
programs (whole-file sha256): identical (13 files)
programs (load-semantic identity): identical (13 files)
rtl:      identical (tcpu_core.v 66fa67036efd3ef0)
generated: 12fffa5c2348dff0 (before) vs 5c2801ed9d07d0f2 (after) -- the one intended difference
program set: 13 expected, before has 13, after has 13
```

| 程序 | 预期标记 | before | after | 控制台 | COMMIT/TRAP(before/after, 差异) | 周期 |
|---|---|---|---|---|---|---|
| boot01_marker | `TEACHING-CPU-M3-OK` | ok | ok | same | 726/726 d=0 | 6386->6386 (d=+0) |
| boot02_clint | `M3-CLINT-OK` | ok | ok | same | 6856/6856 d=0 | 44469->44469 (d=+0) |
| boot03_ddr | `M3-DDR-OK` | ok | ok | same | 1909/1909 d=0 | 16323->16323 (d=+0) |
| boot04_badaddr | `M3-BADADDR-OK` | ok | ok | same | 725/725 d=0 | 6895->6895 (d=+0) |
| ext01_m | `TEACHING-EXT-M-OK` | ok | ok | same | 726/726 d=0 | 7021->7021 (d=+0) |
| ext02_c | `TEACHING-EXT-C-OK` | ok | ok | same | 575/575 d=0 | 6460->6460 (d=+0) |
| ext04_sv39 | `TEACHING-EXT-SV39-OK` | ok | ok | same | 1631/1631 d=0 | 17834->17834 (d=+0) |
| boot11_sv39 | `M3-SV39-OK` | ok | ok | same | 4236/4236 d=0 | 45709->45709 (d=+0) |
| boot12_amo | `M3-AMO-OK` | ok | ok | same | 4500/4500 d=0 | 49519->49519 (d=+0) |
| hello | `PASS` | ok | ok | same | 1119/1119 d=0 | 10293->10293 (d=+0) |
| tlb01_sfence | `TEACHING-TLB-SFENCE-OK` | ok | ok | same | 2848/2848 d=0 | 31432->31432 (d=+0) |
| tlb02_canonical | `TEACHING-TLB-CANON-OK` | ok | ok | same | 4773/4773 d=0 | 51894->51894 (d=+0) |
| cache01_smc | `TEACHING-CACHE-SMC-OK` | ok | ok | same | 1045/1045 d=0 | 9009->9009 (d=+0) |

```
COMPARE fails=0  (cycle deltas are reported, not judged)
```

两份比较:输入身份闭合(整文件 sha 与加载摘要两侧相同,RTL 相同,生成物是唯一差异);每程序两侧各自 exit 0、预期标记在、无 FAIL、有周期;程序集合与期望集合完全相等;tracing 侧每个运行都有非空 COMMIT/TRAP 且逐条相同;周期两侧相等(报告,不判定)。**含 `boot11_sv39`(Sv39)、`boot12_amo`(AMO)与 `boot02_clint`(定时器中断)。**

**hartid tb 重跑**(`runs/t1.1-hartid-closeout`,`tests/hartid-tb/run.sh`):

```
ok   : omitted-default -> exit 0, TEACHING-MC1-HARTID-OK   (HARTID_TB param=0 expect=0 sentinel=0000600d mhartid=0)
ok   : explicit-0 -> exit 0, TEACHING-MC1-HARTID-OK   (HARTID_TB param=0 expect=0 sentinel=0000600d mhartid=0)
ok   : nonzero-5 -> exit 0, TEACHING-MC1-HARTID-OK   (HARTID_TB param=5 expect=5 sentinel=0000600d mhartid=5)
ok   : negctl-5-vs-0 -> exit 134, TEACHING-MC1-HARTID-FAIL   (HARTID_TB param=5 expect=0 sentinel=0000600d mhartid=5)
HARTID_TB pass=4 fail=0
```

### 10.3 第一遍 closeout(`runs/closeout-*`)为什么保留

第一遍在 `probe_console.py` 修正之前跑了 trace-free 组:程序全部正确完成,但判定器把 `hello` 的 `PASS` 与紧随的 harness 行粘连而判"预期标记缺失"(`runs/closeout-compare-fast.txt`:`REJECT: hello before/after: expected marker PASS absent`,fails=2)。修正(逐行判断片段/整行、恢复 harness 行边界)后,同一遍的 tracing 组与第二遍全部 `fails=0`。第一遍是这个判定器缺陷的原始证据,按要求保留。

