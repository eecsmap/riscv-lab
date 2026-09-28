# MC-M0 TESTPLAN — 逐条契约的正向/负向测试、oracle、超时与通过条件

claude,2026-09-26,答 `codex-mc-m0-contract-audit`。沿用方案 §5 的阶段(M1–M5),**不重做测试框架**:每条测试都指明复用哪个现有入口。契约编号见 `CONTRACT.md`。

## 0. 复用的现有框架(入口与其已知结果)

| 代号 | 入口 | 现状 |
| --- | --- | --- |
| F-TB | `experiments/IPS-campaign/tests/run-{tlb,icache,ifill,xlate-amo}-tb.sh <fresh outdir>`(Verilator 单元台) | tlb 31/31,ifill 28/28,icache/xlate-amo `_OK`(`verify_all.sh` 全绿) |
| F-ISA | `experiments/teaching-cpu/cpu-{m,c,a,su,sv39}/` 的回归与故障注入(`FAULT_*` 参数作负向控制) | 各自 `CODEX_REVIEW*.md` 已验收 |
| F-ATOM | `soc/scala/teaching/AtomicTest.scala`(`WithAtomic(scen, latency, aStall, …)`)+ `AtomicSoc.scala` 配置 + `cpu-atomic-backend/scripts/score.py` 检查器 | run8 全部 24 场景 + 9 自测通过;`score.py` 的三条守卫已被变异证明会开火(`codex-review/rescored-20260925/`) |
| F-DRV | `soc/scala/teaching/BusTest.scala` / `BusTester.scala`(协议驱动器)、`RD1Regress.scala`、`RD2ThrottleTest.scala`(桥 drain 契约) | 已有 |
| F-XV6 | `tests/run-stage1-xv6.sh` → `board-runner.py --workload b0apps` + `check-xv6.py`(`segments=4 prompts=4 stages=6 fails=0`) | **三个变体都已在仿真中通过**(`XV6-COMPARISON.md`;`runs/xv6-{fetch32,tlb,cache}/`):fetch32 3 244 693 508 周期、tlb 728 106 109、cache 463 881 498,各 `fails=0`、三应用校验和与板一致。这是**仿真功能证据**,不是板测或 ROI 性能证据。身份见 `evidence/INDEX.md` |
| F-PERF | `perf02_sv39/perf03_fetch/perf04_where/perf06_iws` 探针 + `gen_board_metrics.py` | 四变体上板数据已验收 |
| F-BOARD | `board/ips-precycle.sh → 用户断电 → ips-record-power-cycle.sh → ips-install.sh`,八项门 `boot01..ext04`,`rehearsal.sh` 37/37 | 已验收 |

通用规则(按裁决校正):
* 每条负向测试必须**断言失败的原因**(退出码 + 消息片段),不接受"非零即通过";守卫首次落地时做一次变异验证(把守卫删掉,看测试转红)。
* **随机负向注入必须证明实际激活**:测试自身要断言注入条件至少触发一次(计数 ≥ 1),不得宣称"必现"。
* 超时分三类分别给出:**仿真周期预算**(按 ≈6–15 CPI 的实测量级加 ≥3× 余量)、**编译/elaboration 墙钟**、**运行墙钟**;超时即失败,不重试。下表"超时"列为仿真周期预算,墙钟另在各阶段脚本中设定。
* 仿真结果新目录存放,不覆盖历史(`runs/<date>-<name>/`)。

---

## T1 — M1:可替换 wrapper,单核不退化(`numCores = 1`)

| ID | 契约 | 正向 | 负向 | oracle | 超时 | 通过条件 |
| --- | --- | --- | --- | --- | --- | --- |
| T1.1 | C1.1 `HART_ID` | `csrr mhartid` 在 `HART_ID=0` 读 0;单元台中 `HART_ID=5` 读 5 | 无参数时默认 0 | 退休记录 `commit_rd_data` | 1 k 周期 | 精确相等 |
| T1.2 | C1.2 端口不变 | F-TB 四个台全绿 | — | 各台自带 `_OK` | 各台原超时 | 计数与 tag 时一致(tlb 31、ifill 28…) |
| T1.3 | C1.2 禁令 | 轻量 lint:`grep` SoC 层源码(`RD2Soc.scala` 等)不得出现 `impl.state`/`dbg_state`/`dbg_redirect` 的引用 | 故意加一处引用 → lint 报错 | grep 退出码 | — | 不引入编译测试框架(裁决 D7) |
| T1.4 | C2.1–C2.4 | F-ISA 全部回归在 wrapper 后重跑 | `REQ_WITHDRAW=1`、`EARLY_IRQ=1` 等故障注入仍被各自监视器检出 | 各套件 oracle | 各套件原超时 | 逐套件计数不变 |
| T1.5 | C4–C6 单核 | F-ATOM 24 场景 + 9 自测 | `AtomicSocNegNoKillConfig` 等负向配置仍被 `score.py` 检出 | `score.py fails=0`/负向 `fails>0` 且原因匹配 | 每场景原超时 | 与 run8 逐场景一致 |
| T1.6 | C7 | `RD1Regress` / `RD2ThrottleTest`:softReset 在各状态下 drain→apply | 在 `outstanding` 时 apply 必须**不**发生(断言) | `cpuRestartSafe` 时序、`nDrained` 计数 | 原超时 | 与 tag 时一致 |
| T1.7 | 方案 §5 M1"退休序列/异常/内存效果相同" | 对同一 ELF(perf02/03/04/06 + boot0x + ext0x)比较 wrapper 前后:退休 PC 序列、trap 序列、最终内存镜像 | — | 逐项 diff | 每 ELF 原超时 | **全等**;周期数允许不同但须记录 Δ |
| T1.8 | 方案 §5 M1"记录性能变化" | F-PERF 四探针在仿真中重跑 | — | 12 个 ROI 的周期 | 原超时 | Δcycle 记入 M1 报告;不设阈值 |
| T1.9 | 方案 §1 unsupported | `coreImpl="pipeline"`、`numCores=3`、`numCores=0` | 每个必须 elaboration 失败 | 异常消息含 `unsupported` 与该值 | — | 三个都失败,且**不是**静默退化为 multicycle/1 |
| T1.10 | F-XV6 单核 | `numCores=1` 上 b0apps 全程 | — | `check-xv6.py fails=0`,三应用校验和 | 现有 1800 s 阶段界 | 与 STAGE1 记录相同校验和 |

---

## T2 — M2a:双核后端,**两个独立协议驱动器**(非真核)

驱动器基于 F-DRV `BusTester`,每个驱动器实现 PHYSICAL_PORT_V2 + 侧带,带随机请求/背压/延迟;至少 **10 个固定种子 × ≥10 000 笔完成事务**(方案 §5 M2)。

| ID | 契约 | 正向 | 负向(注入) | oracle | 超时 | 通过条件 |
| --- | --- | --- | --- | --- | --- | --- |
| T2.1 | C2.5 唯一响应不串核 | 两驱动器并发随机 | 注入:后端把 D 的 source 改成另一区间 | 升级后的 `score.py`:每 `CPU_RESP` 的 `txid` 必属发起 hart;`D_OUT src` 必在发起区间 | 每种子 200 k 周期 | 0 错投、0 丢失、0 重复;负向必检出 |
| T2.2 | C2.3 每 hart 单在途 | 同上 | 注入:驱动器在 `sD` 期间再**提出**一笔且下游放行——**仅提出并被 ready 背压不算违例**,检查的是**第二次被接受** | 桥断言 + `score.py`:同一 hart 在前一笔 D 到达前出现第二次 `A_ACC` | 同上 | 第二次接受被检出;仅提出未接受不报错(正向控制) |
| T2.3 | C4.5 最终服务 | 一驱动器持续发、另一驱动器间歇发;下游随机 `d.ready`,**最大下游延迟设定为 Dmax** | 注入:仲裁对 hart 1 的 grant 被屏蔽 N 周期(N > 观察窗口)——固定优先在每 hart 单在途下**不必然饥饿**,故不用它作负向 | 每 hart 从 `req.valid` 到 `req.fire` 的最大等待,以 Dmax 为参照 | 同上 | 间歇 hart 每笔都完成;记录最大等待/Dmax 比值(不预设常数);负向:等待超过窗口被检出 |
| T2.4 | C4.2/C4.3 AMO/SC 不被插入 | hart A 做 AMO,hart B 同时向同地址狂写 | 注入:后端在 `sGet→sPut` 之间放行 B 的 A | `score.py` 内存模型:AMO 结果 = f(old, opd) 且 B 的写不落在两半之间 | 同上 | 模型与 manager 写序一致;负向必检出 |
| T2.5 | C5 每 hart 预约(**核心**) | ① A LR x;B LR x;A SC x 成功;B SC x 失败 ② A LR x;B store x;A SC 失败 ③ A LR x;B LR y(不同 granule);两 SC 都成功 ④ A LR x;A 自己 store x;A SC 失败 ⑤ A LR x;A trap(`resvClear[A]`);A SC 失败,**B 的预约不受影响** ⑥ A LR x;DMA(串口驱动器)写 x;A SC 失败 ⑦ A LR x;B partial store 与 x 重叠 1 字节;A SC 失败 | 注入:漏清预约(`faultNoKill` 推广到 per-hart)、SC 清了他人预约、`cpuIdx` 错位 | `score.py` 的 `resv[h]` 模型 + `scfail` 期望 | 每场景 50 k 周期 | 七个场景全对;每个注入被点名检出 |
| T2.6 | C7 全局 drain | 两 hart 各有在途时 softReset | 注入:一桥先 apply | `cpuRestartSafe` 仅在两桥都 `applying` 且 `pendingWork=0` 后;`nDrained` 分桥计数 | 100 k | 无写被丢弃:drain 前发出的 Put 全部在内存模型中落地 |
| T2.7 | C3.1 显式绑定(D4) | elaboration 打印每 hart 一条 `CPU_SOURCE hart=<i> lo= hi=`;**三种接法都必须正确**:(a) 正常顺序;(b) **交换**两个 `sbus.fromPort` 的连接顺序;(c) 再加入一个非 CPU client(第二个 DMA 驱动器)。T2.5 在三种接法下结果相同 | 注入:① 两桥同名且后端仍用 `find`;② 某 hart 的精确名缺失;③ 两 client 区间重叠(伪造);④ 侧带 Vec 顺序与 hartId 错位 | elaboration `require` 消息 + `score.py` 按 hart 读公告 | — | ①③④ 在 elaboration 或 T2.5 中被点名检出;② `require` 报缺名;正向三接法全等 |
| T2.8 | C3/C5 mark 队列 | 随机 LR/SC/AMO 混合 | 注入:mark 推给错的 hart | 后端断言(逐队列)+ `score.py` | 同 T2.1 | 断言触发 |

---

## T3 — M2b:两个真核,裸机

复用 F-ISA 的裸机 ELF 框架(HTIF `tohost` 标记),每核以 `mhartid` 分支。

| ID | 契约 | 内容 | oracle | 超时 | 通过条件 |
| --- | --- | --- | --- | --- | --- |
| T3.1 | C8.1 ROM 唤醒(**兼 U1**) | 只写 `msip[0]`;两核都到达 `0x80000000` | 退休 PC 序列:hart 0 先到,hart 1 在 `msip[0]` 清零后到;hart 0 的探测循环在 `msip[2]` 回读 0 处停止 | 20 k 周期 | 两核各退休一条入口指令;探测停在 `NHARTS` |
| T3.2 | C1.1/C8.2 | 每核独立栈:两核各写自己的栈并互相读 | 内存镜像 | 10 k | 无交叉污染 |
| T3.3 | C8.3 每核 timer/msip | 各核设自己的 `mtimecmp`,统计各自 mtip 次数;hart 0 写 `msip[1]` 触发 hart 1 软中断 | trap 记录(`trap_cause`, `trap_interrupt`) | 200 k | 各核计数独立;IPI 到达正确核 |
| T3.4 | C5/C6 | 锁保护计数器(`amoswap` 自旋锁)两核各加 10 000;消息传递发布/获取(`sw data; fence; sw flag` / `lw flag; fence; lw data`) | 最终计数 = 20 000;消费者读到的 data 永远是发布值 | 2 M | 精确;至少 10 种子 |
| T3.5 | C6.4 | 两核交替访问 CLINT/PLIC(pbus)与 DRAM | 无 access fault;**兼 U2**:对 `0xC002080` 写读无 fault | 50 k | 通过 |
| T3.6 | C10 | 核 A 写代码到 X;核 B `fence.i` 后执行 X | B 执行到新代码 | 20 k | 正确;**负向**:B 不 `fence.i` 且 B 的 I-cache 已缓存 X 旧内容 → 执行旧代码(证明测试非空) |
| T3.7 | 长期进度 | 两核各跑 1 M 条独立指令流 | 退休计数 | **≥ 60 M**(1 M × 2 核 × ≈6–15 CPI 共享串行后端,再 ≥3× 余量) | 都完成;记录仲裁等待事件 |
| T3.8 | 4 核 | `numCores=4` elaboration + T3.1/T3.3/T3.4 缩小规模 | 同上 | 同上 | 通过即可,不列上板 |

---

## T4 — M3:双核 xv6 仿真

| ID | 契约 | 内容 | oracle | 超时 | 通过条件 |
| --- | --- | --- | --- | --- | --- |
| T4.1 | C8/C11 | `numCores=2` 启动到 `$` | **每核执行证据**:每核退休 PC 落入 `scheduler` 地址范围;控制台上 hart 0 打印 `xv6 kernel is booting`(`main.c:17`),hart ≥1 打印 `hart N starting`(`main.c:42`)——两种字符串各自对应,不要求同款 | 600 s 阶段界(沿用) | 两核都到达调度器(以退休 PC 为准,字符串为辅) |
| T4.2 | C11 D6 | 修改 `trap.c:183` 后,输入无重复 | **受控竞态**:仿真台在两核同时处于 `clockintr` 时(以两核 `mtimecmp` 对齐并在 trap 记录上确认同周期进入)投递一个 `fromhost` 字符,比对 `consoleintr` 调用次数 | 200 k 周期 | 修后:每字符恰 1 次;**负向**:修前同一受控场景出现 2 次(测试须断言竞态窗口确实构造成功,不以随机交互为准) |
| T4.3 | 方案 §5 M3 | b0apps 三应用 + `fork/wait` 树、`exec` 链、迁移(用 `sleep` 让进程在两核间跳)、`sbrk` 循环、磁盘读写校验 | `check-xv6.py` 扩展:每应用校验和 + 每核至少运行过 ≥1 个用户进程(退休 PC 落入用户地址且 `dbg_priv==U`) | 1800 s | 全部校验和正确;两核都执行过用户代码 |
| T4.4 | C10 | exec 密集:`usertests`(含 exec/fork 子测试)与 `forktest`、`grind`(`user/` 中现存,均调用 `exec`);**不用 `sh -c`**(当前 `sh.c` 不支持) | trap oracle **区分**:预期的 `ecall`/定时器中断计入正常;`CAUSE_INSN_ACCESS`/非法指令/取指页错误计为故障 | 1800 s | 0 故障类 trap;程序自报 PASS |
| T4.5 | 单核不退化 | `numCores=1` 重跑 T4.3 | 同 T1.10 | 1800 s | 校验和不变 |

---

## T5 — M4:构建与上板门禁

| ID | 内容 | oracle | 通过条件 |
| --- | --- | --- | --- |
| T5.1 | 综合/布局布线 `numCores=2` | `post_route_timing_summary.rpt` | WNS ≥ 0,WHS ≥ 0,0 fail;**不降频**;先报 §3 路径 |
| T5.2 | 面积 | `post_route_utilization_hier.rpt`(**要 route 口径分层**) | 与 REPORT §2.3 估计的偏差记录;不设阈值 |
| T5.3 | 上板门禁 | F-BOARD 八项门在双核比特流上——**不能无条件复用**:8 个探针是单核 ELF,两核同入口会争用栈与 `tohost`。M4 须二选一:(a) 探针入口加 hart 停放 stub(`mhartid≠0` 自旋),或(b) 门禁用 `numCores=1` 构建 | 8/8(`ext03_a` 在内),并注明采用 (a) 还是 (b) |
| T5.4 | 双核 xv6 上板 | T4.1/T4.3 在板上 | 同 T4 |
| T5.5 | 恢复 | 已验收单核载荷烧回,八项门 | 8/8,`PD=1 FESVR=0 NO_LOCK` |

上板每一步遵守既有规则:pin → 用户断电具结 → 冷启动核验;租约;不热重载。

---

## T6 — 未来核替换的契约一致性套件

目的:任何 `CORE_IMPL` 都能用同一套测试判定是否守约。全部只用 CONTRACT C1.2 的对外端口。

| ID | 契约 | 内容 | 通过条件 |
| --- | --- | --- | --- |
| T6.1 | C2.1 | 监视器:`req.valid` 高且未 fire 时,下一周期 `valid` 仍高且负载不变 | 0 违例(复用 `RD2Watch` 的检查) |
| T6.2 | C2.2 | `resp.valid` 不早于 `req.fire` 的下一周期 | 0 违例 |
| T6.3 | C2.3 | 任一时刻在途 ≤ 1 | 0 违例 |
| T6.4 | C12.2 | 分两例:(i) **正确路径**取指得到错误响应 → 必须产生精确的取指异常(`CAUSE_INSN_ACCESS`,`epc` 正确);(ii) **已确认被冲刷的错误路径**取指得到响应 → 丢弃、不提交、不 trap。两例都要求:响应到达前不 trap | trap 记录时序与 `epc` |
| T6.5 | C10.2 | `satp` 写后对旧映射的访问必 miss(TLB 全清)或等价语义 | 用 F-TB tlb 台的 flush 用例 |
| T6.6 | C1.1 | `mhartid` = 实例参数 | 同 T1.1 |
| T6.7 | 观察端口 | `commit_*`/`trap_*` 精确、互斥 | 复用 F-ISA 的退休监视器 |

流水线实现进入前必须先在单核上通过 T6 + T1,再进 T2–T4。

---

## 覆盖矩阵(契约 → 测试)

| 契约 | 测试 |
| --- | --- |
| C1 | T1.1 T1.3 T1.9 T3.2 T6.6 |
| C2 | T1.4 T2.1 T2.2 T6.1–T6.3 |
| C3 | T2.7 T2.8 |
| C4 | T2.3 T2.4 |
| C5 | T2.5 T3.4 |
| C6 | T3.4 T3.5 |
| C7 | T1.6 T2.6 |
| C8 | T3.1 T3.3 T4.1 |
| C9 | (审计结论;上板由 `MEM_PREFLIGHT` 每会话核验) |
| C10 | T3.6 T4.4 T6.5 |
| C11 | T4.2 T4.3 |
| C12 | T6.4 |
| 未确认 U1/U2 | T3.1 / T3.5 |
