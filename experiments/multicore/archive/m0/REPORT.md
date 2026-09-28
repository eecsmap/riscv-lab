# MC-M0 REPORT — 冻结身份、分层面积、40 MHz 风险、修改点与裁决请求

claude,2026-09-26,答 `codex-mc-m0-contract-audit`。**审计验收,不是双核实现。** 三份文档:`CONTRACT.md`(契约与逐项状态)、本文、`TESTPLAN.md`。原始摘录在 `evidence/`。

未做的事(按任务禁令):未改生产 RTL/Scala/xv6/host;未碰板子、串口、复位、烧写、`/tmp`;未做综合或长仿真;未切换共享 checkout;未 push/tag。所有证据来自已存在的源码、分层报告、构建日志与已部署二进制的反汇编。

---

## 1. 冻结身份(核实,不是抄录)

### 1.1 参考点

| 项 | 值 | 如何核实 |
| --- | --- | --- |
| tag `ips-v1-icache` | 带注释 tag,对象 `eef0b4cb95f842eed3e196d4629768d35d256694` | `git cat-file -t` = `tag` |
| 它指向的 commit | `c16306bcfb40ead07a0375826527e9b871997f37` | `git rev-parse ips-v1-icache^{commit}`;与方案 §2 一致 |
| 工作树 HEAD | `0bdd7c6`(领先 tag 5 个提交,全是 `experiments/` 下的文档与脚本) | `git diff --stat c16306b..HEAD -- rtl/ soc/` **为空** |
| `tcpu_core.v` | sha256 `96586a6f2261ae2c…` | 与 `experiments/IPS-campaign/IDENTITIES.json` 的 `ips-cache.rtl.tcpu_core.v` 逐字一致 |
| RTL 模块集(13) | `tcpu_cacheable/cdecode/core/csr/defs.vh/icache/ifill/muldiv/permcheck/ptw/regfile/tlb/xlate` | `IDENTITIES.json` |
| `soc/scala/teaching/` | 与 `riscv-lab` `main` 逐文件相同 | `diff -rq` 为空 |

### 1.2 实际部署的构建

| 项 | 值 |
| --- | --- |
| 配置类 | `RD2AtomicBoardConfig`(`soc/scala/teaching/RD2Soc.scala:767-773`):`WithoutTLMonitors ++ WithAtomicHub(trace=false) ++ WithRD2(atomic=true, traceEvents=false, atomicTrace=false, bdevTrace=false, busInstrumentation=false) ++ WithTeachingCpu(traceEvents=false, extraDelay=false, bridgeFault=0, tailIntercept=false) ++ WithTeachingBootROM ++ zynq.WithZynqAdapter ++ DefaultConfig` |
| netlist 输入 | `build-cache/inputs/RD2BoardTop.RD2AtomicBoardConfig.v` |
| 顶层实例树 | `rocketchip_wrapper → top/RD2BoardTop → target/RD2ZynqTop → {cpuV2/TeachingCpuV2 → core/tcpu_core, bridgeV2/RD2BridgeV2, backend/AtomicBackend, bh/TLBroadcast, rd2clint/RD2Clint, plic/TLPLIC, rd2serial/RD2SerialAdapter, controller/RD2BlockDeviceController, sbus, pbus, mbus, …}` + `adapter/ZynqAdapterRD2` + `system_i`(PS7 块设计) |
| `.bit` | `e546c0ddb1eda90e…`(`BUILD-TABLE.md`);`.bit.bin` `79a114aed6ab0895…`(`board/payloads/payloads.tsv`,五次上板会话逐次回读一致) |
| 时序(post-route) | WNS **0.424 ns**,WHS 0.036 ns,24 530 端点,0 违例(`build-cache/reports/post_route_timing_summary.rpt`) |
| 面积(post-route) | **14 554 LUT / 7 011 FF / 0 BRAM / 0 DSP**(`BUILD-TABLE.md`;这是**单核整机**,不是每核) |

**一个必须记录的事实**:方案 §2 引用的 `tcpu_core.v` 与 `TeachingCpuSoc.scala` 并不是上板的那条路。`TeachingCpuSoc.scala` 是测试用的另一个顶层(`TeachingCpuZynqTop`,V1 端口);**上板的是 `RD2Soc.scala` 的 `RD2ZynqTop`**,V2 桥 + 原子后端 + `RD2Clint`/`RD2Serial`/`RD2BlockDevice` 的 RD2 副本。M1 起所有 wrapper 工作应落在 `RD2Soc.scala` 这条链上。

### 1.3 实际部署的 xv6 内核与磁盘

| 构件 | sha256 | 来源 |
| --- | --- | --- |
| `kernel-4mib`(交互会话与仿真用) | `6ad5c2338a31d59e5fb3fab74365c7f0334cf46e928f3baa20bf40e2df4a6a88` | `experiments/teaching-cpu/xv6-board-prep/artifacts/kernel-4mib`,同 `/tmp/b0simrun/kernel-4mib` |
| `kernel-128mib`(B0 上板战役用) | `e990fb31fad483b805aaeae77ecaebb3111abcec012d70447c620c9e9b289c2c` | 同目录;`deploy-bundle/MANIFEST.sha256` |
| 源码树 | `teaching-cpu-work/xv6-teaching/`(**非 git**,无 commit id) | `artifacts/build-4.log` 第 1 行:`-ffile-prefix-map=/home/engineer/fpga/teaching-cpu-work/xv6-teaching=. -DTEACHING_SIM_MEM_MIB=4`;其余关键标志 `-DTEACHING_NO_PMP -march=rv64gc -mcmodel=medany` |
| 树与已部署二进制的漂移 | **仅内存尺寸宏** | `objdump -d` 树内 `kernel` vs `kernel-4mib`(`evidence/kernel-drift.diff`):diff 共 14 行 = 1 个文件名头 hunk + **3 个代码 hunk**(`0x800009d6`、`0x80000a7a`、`0x800011da`,各 `li`+`slli` 两条指令),全部是 PHYSTOP 常量:树内当前 `129<<24` = `0x8100_0000`(MEM_MIB=16),部署 4mib `513<<22` = `0x8040_0000`,128mib `17<<27` = `0x8800_0000`;`INTEGRATION-REPORT.md:125-131` 记录相同。**除此之外逐指令相同。** |
| 磁盘 | `fs-b0-pristine.img` `6bdd8148b79e5983…` | `/tmp/b0simrun/`(被我在 /tmp 清理里标为必须保留的目录,正是因为它) |
| BootROM | `bootrom.teaching.rv64.img` 156 B,sha256 `1ca1cbf08c789878…`,`hang=0x10040` | `teaching-cpu-work/fpga-zynq/common/src/main/resources/teaching/`;反汇编 `evidence/bootrom.dis` |

**判定(按裁决 D8 收窄)**:xv6 树**可以作为代码路径的审计对象**——已部署二进制与树内旧 ELF 的反汇编只差 PHYSTOP 常量。但反汇编接近**不能证明当前源码能复现该二进制**(树非 git,无法证明自那次构建后源码未变);这一点留到后续软件构建阶段验证。本轮已冻结:源文件清单与逐文件 sha256、树摘要、构建参数、工具链身份——`evidence/xv6-source-freeze.txt`(49 个文件;`riscv64-unknown-elf-gcc (gc891d8dc23e) 13.2.0`;树摘要 `43beb55475604879…`)。

---

## 2. 分层面积:共享 / 每核私有(实测),与双核估计(估计)

数据源:`build-cache/reports/post_synth_utilization_hier.rpt`(cache 构建**综合后**分层;该构建没有 post-route 分层报告,只有 `post_route.dcp`)。校准(**只用于 LUT,且只作观察值**):同一设计 baseline 构建有 synth 与 route 两份分层,逐模块 LUT 差异 −0.5 %(`core` 6196→6162,`backend` 1138→1132,`rf` 3217→3205);整机 cache 构建 synth 15 062 → route 14 554 LUT(−3.4 %,主要在 PS7 块设计与顶层胶合)。**FF 不套用这一比例**(裁决 D9):FF 的 route 数只给整机实测 7 011,分模块 FF 以 synth 值列出、不折算。route 口径的分模块数据可后补,本轮无需 Vivado。

### 2.1 每核私有(实测,synth)

| 实例 | 模块 | LUT | FF | 说明 |
| --- | --- | ---: | ---: | --- |
| `cpuV2` | `TeachingCpuV2` | **7 486** | **3 460** | 含以下全部子项 |
| ├ `core`(self) | `tcpu_core` | 440 | 838 | FSM、请求寄存器、commit/trap 记录 |
| ├ `csrfile` | `tcpu_csr` | 1 167 | 848 | |
| ├ `ifill` | `tcpu_ifill` | 1 087 | 321 | 其中 `ic/tcpu_icache` 338 LUT(200 LUTRAM)/64 FF |
| ├ `muldiv` | `tcpu_muldiv` | 1 123 | 466 | |
| ├ `ptw` | `tcpu_xlate` | 725 | 987 | 其中 `tlb` 417/643(8 项),`ptw` 292/212 |
| └ `rf` | `tcpu_regfile` | **2 946** | 0 | LUT 实现(88 LUTRAM),**每核最大单项** |
| `bridgeV2` | `RD2BridgeV2` | 314 | 251 | |
| `cpuWatch` | `RD2Watch` | 0 | 0 | **不在综合层级中**:`busInstrumentation=false` 且 trace 关闭时是纯连线(报告里只有 `bdevWatch/RD2Watch_1` 65/50) |
| **每核私有合计** | | **7 800** | **3 711** | |

### 2.2 共享(实测,synth;按残差计算避免重复计数)

| 范围 | LUT | FF | 计算 |
| --- | ---: | ---: | --- |
| `target/RD2ZynqTop` 整体 | 13 906 | 6 156 | 报告行 |
| 减 每核私有 | −7 800 | −3 711 | |
| **`target` 内共享** | **6 106** | **2 445** | 后端、TLBroadcast、ROM、CLINT×2、PLIC、串口、块设备、sbus/pbus/mbus、TLToAXI4 等 |
| `target` 之外(`adapter` 709/545、`system_i` 447/500、`bdev_serdes` 101/205、顶层胶合) | 1 156 | 1 045 | 15 062 − 13 906 |
| **共享合计** | **7 262** | **3 490** | |

共享项明细(报告行,含各自子层;各行之间有嵌套,**不可直接相加**,故上面用残差):`backend` 1 139/235,`bh/TLBroadcast` 555/225,`bootrom` 365/0,`clint`(停放的子系统 CLINT)0/64,`rd2clint` 35/129,`plic` 47/63,`rd2serial` 585/231,`controller`(块设备)647/452,`sbus` 731/114(`system_bus_xbar` 683/108),`pbus` 1 495/402,`mbus` 256/394,`tl2axi4` 137/138,`atomics/TLAtomicAutomata` 399/190,`axi4frag` 239/165。

### 2.3 双核估计(**估计**,synth 口径;方法:共享 + 2×私有 + 增量,**不是整机×2**)

| 项 | LUT | FF | 依据 |
| --- | ---: | ---: | --- |
| 共享(§2.2) | 7 262 | 3 490 | 实测 |
| 私有 × 2 | 15 600 | 7 422 | 实测 × 2 |
| 第二 sbus master 口(TLXbar 4 入) | +200 | +20 | `system_bus_xbar` 683 LUT 承 3 master;线性外推 +1/3 ≈ +230,取整 |
| 后端 per-hart:第二预约 + 比较器 + 第二 mark 队列 + `cpuIdx` 译码 | +120 | +40 | `resvWord` 29 位 + valid;重叠比较约 60 LUT;队列深 1 |
| `RD2Clint` 第二 tile | +35 | +65 | `timecmp` 64 FF + `ipi` 1 FF;regmap 增量 |
| PLIC 第二上下文 | +30 | +30 | 无设备源,仅上下文寄存器 |
| 中断 sink、复位聚合、状态位 | +20 | +10 | |
| **双核 synth 估计** | **≈ 23 270** | **≈ 11 080** | |
| **双核 post-route 估计** | **≈ 22 480** | **(不折算;synth ≈ 11 080)** | LUT 按整机观察到的 −3.4 %;FF 不套用同一比例(D9) |
| 器件 XC7Z020 | 53 200 | 106 400 | ≈ **42 % LUT**,≈ 10 % FF |
| 对照:整机 × 2(**错误方法**,只为说明差距) | 29 108 | 14 022 | 高估 6.6 k LUT |

四核外推(仅 elaboration 目标,不承诺上板):≈ 7 262 + 4×7 800 + ≈1 000 ≈ **39.5 k LUT synth**(≈ 75 %),布线拥塞风险高;与方案"4 核只做 elaboration/仿真"一致。

**可选的面积杠杆(不在本包范围,记录供裁决)**:`tcpu_regfile` 2 946 LUT/核为 LUT 阵列;改为 LUTRAM/BRAM 双端口可省约 2.5 k LUT/核。这是核内改动,会改变 M1"单核不退化"的基线,若做应单独立项。

---

## 3. 40 MHz 风险

### 3.1 现状的最差路径(实测)

`build-cache/reports/post_route_timing_worst.rpt`:

```
Slack (MET) : 0.424 ns
Source      : top/teaching_board_top/target/rd2serial/addr_reg[4]/C
Destination : top/teaching_board_top/target/backend/resvValid_reg/D
Data Path   : 24.364 ns  (logic 11.113 ns 45.6 %, route 13.251 ns 54.4 %)
Logic Levels: 50  (CARRY4=27 LUT2=3 LUT3=2 LUT4=5 LUT5=5 LUT6=8)
```

第二差路径同源 `rd2serial/addr_reg` → `bh/TLBroadcastTracker_3` RAM,slack 2.978 ns。

**解读**:串口适配器的地址寄存器经 sbus 仲裁进入后端,与预约 `resvWord` 做**区间重叠**判定(`AtomicBackend.scala:111-112`:`aLo < wHi && aHi > wLo`,两次 32 位比较,27 级 CARRY4 就是它们的进位链),再决定 `killResv` → `resvValid`。**双核要改的恰恰是这条路径上的比较逻辑。**CPU 侧路径目前至少有 ≈3 ns 余量(未出现在前两名)。

### 3.2 双核带来的变化(估计)

* TLXbar A 仲裁多一个输入 → 进入后端的 `in.a` 多一级 mux(≈ +0.4–0.6 ns)。
* per-hart 预约:两个比较器**并行**,深度不增;但 `cpuIdx(a.source)` 译码要参与"是否自己的写"判定(≈ +1 级 LUT,+0.3 ns)。
* 合计对最差路径的增量**推测**为 +0.7–0.9 ns——这是**未经双核布局布线验证的推测,不能作为失败预测**(裁决 D2)。可以确定的只有:该路径是现状最差路径、余量 0.424 ns、双核改动落在这条路径上。

### 3.3 处理选项(裁决 D2)

| 选项 | 做法 | 代价 | 效果 |
| --- | --- | --- | --- |
| **A(推荐先做)** | 在 `rd2-serial` 的 TL client 节点后加一级 `TLBuffer`(仅串口路径) | 串口不在性能路径;+≈100 LUT/+≈130 FF;**CPU 零延迟代价** | 直接切断当前最差路径的源头;CPU 路径余量 ≈3 ns 可吸收 +0.9 ns |
| B | 后端内侧 edge 加 `TLBuffer`(所有 DRAM 事务) | **每笔 DRAM 事务 +1 周期**;I-cache 命中的取指不受影响;load 密集 ROI 最坏 +1 CPI | 彻底把比较逻辑与仲裁分开;M4 若 A 不够再上 |
| C | 把重叠判定改为 `size ≤ 3` 时用 `addr[31:3] == resvWord` 等值比较,只对多拍 DMA 走区间 | 逻辑改动,需重跑原子负向测试 | 去掉 27 级进位链;可与 A 叠加 |

按裁决 D2:**暂不预先插入 TLBuffer**;A/B/C 保留为候选,由 M4 的实际综合/布线证据驱动是否实施及选哪个;若实施,记录其对**单核对照**的影响(M1 基线上的周期与面积变化)。**任何选项都不允许静默降频**(方案 §5 M4)。

### 3.4 其他时序相关事实

* 40 MHz = 125 MHz 振荡器经 MMCM ×8/25,不变。
* `TLAtomicAutomata`(mbus,399 LUT)对本设计是死逻辑(后端已把 AMO 拆为 Get/Put),但仍在时序图里;可在配置中去掉(rocket-chip `WithoutTLMonitors` 同类的开关),属可选清理。

---

## 4. 代码修改点(文件:行,按最小实现顺序)

### 4.1 M1 — 可替换 wrapper,单核不退化

| # | 文件:行 | 改动 | 为什么 |
| --- | --- | --- | --- |
| 1 | `rtl/cpu/tcpu_core.v:2-31` | 加 `parameter [63:0] HART_ID = 0`,传给 `tcpu_csr` | CONTRACT C1.1 |
| 2 | `rtl/cpu/tcpu_csr.v:165` | `CSR_MHARTID: rdata = HART_ID` | 同上 |
| 3 | `soc/scala/teaching/TeachingCpuBlackBox.scala`(V2 封装,≈:100-127) | `hartId: Int` 构造参数 → BlackBox `params`;`io.obs` 拆为契约观察(`commit/trap/halted/pc/irqEnabled/isFetch`)与 `impl`(`state/redirect`) | C1.2 禁令 |
| 4 | 新文件 `soc/scala/teaching/TeachingHart.scala` | `class TeachingHart(hartId, cfg)`:内含 `TeachingCpuV2 + RD2BridgeV2 + RD2Watch`,对外 `node`(TL)、`drain`、`irq`、`obs`。**M1 保持 client 名 `"teaching-phys"` 与单套侧带不变**——现后端 `find + require` 精确要求该名(`AtomicBackend.scala:60-62`),改名会让 M1 直接失败;多核身份迁移在 M2(#10)统一做 | 裁决"实施顺序";C7 |
| 5 | `RD2Soc.scala:29-53` | `RD2Params` 加 `numCores: Int = 1`,`coreImpl: String = "multicycle"`;`require(coreImpl == "multicycle", s"unsupported CORE_IMPL=$coreImpl")` | 方案 §1"未实现组合明确 unsupported" |
| 6 | `RD2Soc.scala:108-128, 184-210` | 用 `Seq.tabulate(numCores)(new TeachingHart(_))` 替换单实例;`sbus.fromPort(Some(s"teaching-cpu-$i"))` | |
| 7 | `RD2Soc.scala:133-136, 206-209` | 中断 sink 与接线按核数生成 | C8.3 |
| 8 | `RD2Soc.scala:166-169, 182, 190-192, 224-225` | drain 扇出/聚合(C7.1)、`applyReset` 取 `applying_all`、每核 `withReset(reset \|\| holdAll)`、`pendingWork = OR` | C7 |
| 9 | `RD2Soc.scala:87` | `status.msip` 语义(D5) | |

M1 验收对象 = `numCores = 1` 下所有现有回归(TESTPLAN T1.*)逐一不退化;**这一步不动后端**;`numCores = 2` 在 M1 **允许**被 `require` 拒绝,**不得**以它能 elaborate 暗示可用。

### 4.2 M2 — 双核互连与原子后端

| # | 文件:行 | 改动 |
| --- | --- | --- |
| 10 | `AtomicBackend.scala:60-70` | **显式绑定**(D4):对 `0 until numCores` 逐个按精确名 `s"teaching-phys-$i"` 解析 client → `cpus(i) = (lo, hi)`;`require` 每名恰 1 个、数量 = numCores、区间不重叠、所有 `teaching-phys*` client 都被解析、侧带 Vec 长度一致;`cpuIdx(s)` 查表。同时桥名与侧带 Vec 下标在 `TeachingHart` 中由同一 `hartId` 决定 |
| 11 | `AtomicBackend.scala:72-79` | `markQ` → `Seq.fill(n)(Queue(…,1))`;断言逐队列 |
| 12 | `AtomicBackend.scala:89-93` | `resvValid/resvWord` → `Vec(n)`;`killResv(h, why)` |
| 13 | `AtomicBackend.scala:98-140` | 事件按 `cpuIdx` 分派(CONTRACT C5.2);`aOverlaps` 对每个 `h` 计算;SC 判定用 `resv[h]` |
| 14 | `AtomicBackend.scala:139` | `io.sb(h).resvClear → killResv(h)` |
| 15 | `PhysPortV2.scala:40-43` | `AtomicSideband` → `Vec(n, …)` 或每 hart 一个 bundle |
| 16 | `AtomicHub.scala:20-32` | 传 `n`;`AtomicHub.last` 保持 |
| 17 | 时序:`RD2Serial.scala:45` 节点后 `TLBuffer`(D2-A);`AtomicBackend.scala:111-112` 等值/区间分路(D2-C) | |
| 18 | `cpu-atomic-backend/scripts/score.py:60-70, 98-120` | `CPU_SOURCE` 改为多区间;`cpu_open` 按 hart;新增"错投/串核"检查。**这是 M2a 的第一步,先于任何双核测试**(裁决:oracle 不能在 M2c 才升级) | TESTPLAN T2 的 oracle |

### 4.3 M3 — 软件

| # | 文件:行 | 改动 |
| --- | --- | --- |
| 19 | `teaching-cpu-work/xv6-teaching/kernel/trap.c:183` | `uartintr()` 套独立的 `if (cpuid() == 0)` 分支——它已在 `release(&tickslock)` 之后,**不得放进持锁区**(D6) |
| 20 | 同树 | 记录树的身份(§1.3 缺口);其余启动/中断/维护路径**不需要改**(CONTRACT C8、C10、C11) |

### 4.4 不需要改的(审计明确排除)

`RD2Clint.scala`(按 sink 数生成)、`RD2Serial.scala`(冷域,无软复位)、`RD2BlockDevice.scala`(与 hart 数无关)、BootROM(已支持多 hart 唤醒,C8.1)、`tcpu_tlb/xlate/icache/ifill`(每核私有,语义本地)、fesvr/host(只唤醒 hart 0,ROM 负责其余)、xv6 的 `entry.S/start.c/main.c/kernelvec.S/trampoline.S/plic.c`(已按 `mhartid` 工作)。

---

## 5. 最小实现顺序(建议)

1. **M1a**:#1–#4(HART_ID、wrapper、bundle 拆分),`numCores=1`,跑 T1 全部 → 单核不退化。
2. **M1b**:#5–#9,仍 `numCores=1`,坏配置(`coreImpl="pipeline"`、`numCores=3`)必须 elaboration 失败并给出原因。
3. **M2a**:**先 #18(多核 oracle)**,再 #10–#16,用**两个协议驱动器**(非真核)跑 T2.1–T2.8,含负向注入。
4. **M2b**:两个真核裸机(T3.1–T3.4)。
5. **M2c**:#17 时序改动**仅在 M4 证据要求时**实施;重跑 `cpu-atomic-backend` 的 run8 全部场景不退化。
6. **M3**:#19,双核 xv6 仿真(T4.*)。
7. **M4**:综合;先看 §3 路径;不满足则 D2-B,再综合;不静默降频。

---

## 6. 关键阻断与建议裁决

| # | 事项 | 严重度 | 建议 |
| --- | --- | --- | --- |
| **D1**(= CONTRACT **B1**) | 后端按名字 `find` 只识别一个 CPU client(`AtomicBackend.scala:60`);第二 hart 的 SC 会被当普通 Put **无条件写入** | **阻断(正确性)** | 采纳 CONTRACT C3.1–C3.2、C5.1–C5.4 的 per-hart 表与预约数组;这是 M2 的核心改动 |
| **D2** | 最差路径 `rd2serial → backend/resvValid` 余量 0.424 ns;双核增量为**未验证推测** | 风险(时序) | **已裁决**:不预插 TLBuffer;A/C/B 保留为候选,由 M4 证据驱动,并记录单核对照影响 |
| D3 | SC 对他 hart 预约的作用 | 设计选择 | **已裁决**:成功的 SC 是写,使其他 hart 的重叠预约失效;失败的 SC 只清自己的预约。(此前"清他人必然双失败/违反前进性"的无条件论断已删除) |
| D4 | hart 索引来源 | 设计选择 | **已裁决:拒绝排序赋号**。显式精确身份绑定 hart→source 区间→侧带,elaboration 检查数量/唯一/非重叠/完整;测试交换连接顺序与加入非 CPU client(CONTRACT C3.1) |
| D5 | `status.msip`(`RD2Soc.scala:87`)含义 | 小 | **已裁决**:保持 hart 0;文档限定它不证明所有核已启动;各核启动以每核启动/退休记录验收 |
| D6 | `uartintr()` 每 hart 轮询 `fromhost`(`trap.c:183`) | **中(软件正确性)** | **已裁决**:限 hart 0;不入 `tickslock` 持锁区(现已在 release 之后,加独立分支即可);回归用受控竞态 |
| D7 | wrapper 对外 bundle 含 `dbg_state`(FSM 状态) | 契约卫生 | **已裁决**:拆入 `impl` 子 bundle,SoC 层禁止引用;**不**为证明私有字段增加重型编译测试框架 |
| D8 | xv6 源码树无版本标识 | 过程 | **已裁决并完成冻结**:`evidence/xv6-source-freeze.txt`(文件清单+哈希、树摘要、构建参数、工具链);"树可复现二进制"的声称已收窄(§1.3) |
| D9 | cache 构建无 post-route 分层报告 | 证据完整性 | **已裁决:本轮无需 Vivado**;synth 分层足以估计,route 数据可后补;LUT 折算率不套用到 FF(§2 已改) |

**没有发现需要重写 host 或磁盘路径的情况**:ROM 已做多 hart 唤醒,host 只写 `msip[0]`,块设备与 TSI 都经后端且与 hart 数无关。**没有发现需要大规模软件改造的情况**:内核改动是一行(D6)。

---

## 7. 未确认项(如实标注)与最小补证

| # | 事项 | 为什么未确认 | 最小补证 |
| --- | --- | --- | --- |
| U1 | ROM 的 msip 回读探测在 `i = NHARTS` 处停止(依赖对不存在偏移的读返回 0) | regmapper 行为未在本项目源码里 | M2 elaboration 后仿真 ROM,断言 hart 0 写 `msip[2]` 后回读 0 |
| U2 | PLIC 对不存在上下文的写被 ack 而非 fault | 同上;单核实践(hart 0 写 S 上下文)暗示 ack | 仿真里对 `0xC002080` 写读一次,断言无 access fault |
| U3 | TLXbar 仲裁的锁定与公平 | 框架代码,本项目内无源码引用或测试证据,**不标已证明** | T2.3 驱动器测试;有限完成不给固定上界,需限定最大下游延迟 |
| U4 | **双核** xv6 从未运行(仿真亦无)。**单核** xv6 已在仿真中通过三个变体:`runs/xv6-cache` 的 `tcpu_core.v` = `96586a6f…`(即已部署 RTL),`runs/xv6-tlb` = `ed5739de…`;`XV6-COMPARISON.md`:cache 463 881 498 周期 `fails=0`——此前我写"tlb/cache 从未跑过"不实,系漏看 tag 提交信息本身 | 事实 | M3 |
| U5 | 双核时序 | 未综合 | M4 |
| ~~U6~~ | `cpuWatch` 面积 | **已确认为 0**:实例不在综合层级中(纯连线) | — |

---

## 8. 与方案 §5 M0 验收条款的对照

| 条款 | 交付位置 |
| --- | --- |
| CONTRACT.md | `CONTRACT.md` C1–C12 |
| 接口/修改点清单 | 本文 §4 |
| 资源分层表(共享/每核,估计标明) | 本文 §2 |
| 测试矩阵 | `TESTPLAN.md` |
| 软件与 host 单核假设清单 | CONTRACT C11 + C9 |
| source/hart 映射 | C3(实证 `CPU_SOURCE lo=2 hi=3 clients=3`) |
| 原子保护范围与预约事件 | C5 |
| 启动入口、中断 | C8(ROM 反汇编) |
| host 内存写 | C9 |
| 跨核维护 | C10(附实际代码路径) |
| 全局复位 | C7 |
| 部署内核/磁盘来源与 hash | §1.3 |
| "无未决正确性问题才进 M1" | **D1、D6 为已识别、有明确修法的正确性问题**;进入 M1 不需要先解决 D1(M1 单核不触后端),但 M2 前必须裁决 |
