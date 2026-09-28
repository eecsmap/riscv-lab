# MC-M0 CONTRACT — 可替换 hart wrapper 与双核后端契约

claude,2026-09-26,答 `codex-mc-m0-contract-audit`。**审计,不是实现。** 未改任何生产 RTL/Scala/xv6/host,未碰板子、串口、复位、烧写或 `/tmp`。

审计对象是**实际部署**的构件,不是仓库里的另一副本(身份在 `REPORT.md §1`,此处只列关键项):

| 项 | 值 |
| --- | --- |
| tag | `ips-v1-icache`(带注释 tag 对象 `eef0b4cb95f8…`)→ commit `c16306bcfb40ead07a0375826527e9b871997f37` |
| RTL / soc 自 tag 至工作树 HEAD `0bdd7c6` | `git diff --stat c16306b..HEAD -- rtl/ soc/` 为空 |
| 已部署配置 | `RD2AtomicBoardConfig`(`soc/scala/teaching/RD2Soc.scala:767-773`):`WithAtomicHub`,`atomic = true`,`busInstrumentation = false`,`WithoutTLMonitors` |
| netlist 输入 | `build-cache/inputs/RD2BoardTop.RD2AtomicBoardConfig.v` |
| 比特流 | `.bit e546c0ddb1eda90e…` → 板上 `.bit.bin 79a114aed6ab0895…` |

**审计的是 `RD2Soc.scala` 的 `RD2ZynqTop`,不是 `TeachingCpuSoc.scala` 的 `TeachingCpuZynqTop`** —— 分层报告(`build-cache/reports/post_synth_utilization_hier.rpt`)的实例树是 `target|RD2ZynqTop` → `cpuV2|TeachingCpuV2`、`bridgeV2|RD2BridgeV2`、`backend|AtomicBackend`、`bh|TLBroadcast`、`rd2clint|RD2Clint`、`rd2serial|RD2SerialAdapter`、`controller|RD2BlockDeviceController`、`plic|TLPLIC`。

路径约定:`rtl/` 与 `soc/` 相对 `worktrees/ips-cache/`;xv6 相对 `teaching-cpu-work/xv6-teaching/kernel/`(它就是已部署内核的源,证据见 REPORT §1.3);`DESIGN.md` 指 `riscv-lab/docs/archive/cpu-atomic-backend/DESIGN.md`。

标记:**已存在** = 现有代码已满足,给出行号;**需修改** = 双核必须改,给出改哪里;**未确认** = 没找到决定性证据,给最小补证步骤。

---

## C1. 统一 hart wrapper:端口与参数

### C1.1 参数

| 参数 | 状态 | 证据 / 修改点 |
| --- | --- | --- |
| `RESET_PC` | **已存在** | `rtl/cpu/tcpu_core.v:2`,默认 `0x8000_0000`;板上由 `romParams.hang` 传入(`RD2Soc.scala:190-192` `new TeachingCpuV2(romParams.hang)`),即 BootROM 的 `0x10040` |
| `HART_ID` | **需修改** | `mhartid` 存在但**硬连 0**:`rtl/cpu/tcpu_csr.v:81` `CSR_MHARTID = 12'hF14`,`:137` read-only,`:165` `rdata = 64'd0`。需加 `parameter [63:0] HART_ID` 贯穿 `tcpu_core` → `tcpu_csr`,并由 `TeachingCpuBlackBox.scala` 的 V2 封装按实例传入 |
| `TLB_ENTRIES`, `ICACHE_BYTES` | **已存在** | `tcpu_core.v:3-4`;每实例独立,天然每核私有 |
| `MISA_A` | **已存在** | `tcpu_core.v:25`;板上为 1(`ext03_a` 门通过) |
| 故障注入参数(`FAULT_*`, `REQ_WITHDRAW`, `EARLY_IRQ` …) | **已存在,契约外** | `tcpu_core.v:5-31`。契约规定:wrapper **不得**向外暴露这些;它们只在单核负向测试中使用 |

**为什么 `HART_ID` 是硬前提而不是"锦上添花"**:BootROM 第一条分支就是 `csrr a0,mhartid; beqz a0,…`(`evidence/bootrom.dis` 0x10004-0x10008),两个 hart 都读到 0 就都走 hart-0 路径,都去唤醒别人、都跳内核入口;`_entry` 也按 `mhartid` 算栈(`entry.S`:`csrr a1,mhartid; addi; mul; add sp`)。**没有真实 `mhartid`,双核在 ROM 阶段就已错误。**

### C1.2 端口(PHYSICAL_PORT_V2,沿用)

字段定义 `soc/scala/teaching/PhysPortV2.scala:15-32`;核侧对应 `tcpu_core.v:50-66`。

| 方向 | 信号 | 状态 |
| --- | --- | --- |
| out | `req.valid/addr[31:0]/write/size[1:0]/wdata[63:0]/wmask[7:0]/amo[3:0]/lrsc[1:0]` | **已存在** |
| in | `req.ready` | **已存在** |
| in | `resp.valid/rdata[63:0]/error/scFail` | **已存在** |
| out | `resp.ready` | **已存在** |
| out | `resvClear`(脉冲:trap 或核复位) | **已存在**,`tcpu_core.v:181` `= rst \|\| (state == S_TRAP)` |
| in | `irq.msip/mtip/meip`(电平) | **已存在**,`tcpu_core.v:92-94`;封装 `TeachingCpuBlackBox.scala:110-112` |
| out | 观察:`commit_*`, `trap_*`, `halted`, `dbg_*` | **已存在**,`tcpu_core.v:68-100`;封装 `TeachingCpuBlackBox.scala:115-127` |

**契约新增的禁令**(为未来流水线):wrapper 外部**只能**使用上表;`dbg_state`(`tcpu_core.v` 4 位 FSM 状态)与 `dbg_redirect` 属于多周期实现细节,**M1 起从 wrapper 的对外 bundle 移除或改名为 `impl_*` 并禁止 SoC 层引用**。当前 `RD2Soc.scala` 对 `cpuObs.state` 的使用需在 M1 审查(仅追踪打印则移入实现内部)。

---

## C2. 严格 req/resp

| 条款 | 状态 | 证据 |
| --- | --- | --- |
| C2.1 `valid` 提出后握手前不得撤销、负载不得改变 | **已存在** | `tcpu_core.v:614` 注释 "payload held until the handshake";撤销仅在 `REQ_WITHDRAW != 0` 的自测参数下发生(`:615-617`)。桥侧 `RD2BridgeV2.scala:73` 断言 D 必对应在途 A |
| C2.2 响应最早在请求握手的**下一周期** | **已存在** | 桥状态机 `sA → sD → sResp`(`RD2BridgeV2.scala:69,161`),响应经寄存器;核在 `S_*_WAIT` 采样 `ic_resp_valid`(`tcpu_core.v:618, S_MEM_WAIT`) |
| C2.3 每 hart **单在途** | **已存在** | 桥 `outstanding = state === sD`,单个状态(`RD2BridgeV2.scala:69`);后端 mark 队列深度 1 并断言不溢出(`AtomicBackend.scala:72-79`) |
| C2.4 响应背压时同样保持 | **已存在** | 桥 `sResp` 保持到 `resp.fire`;核 `resp_ready` 常为 1(多周期核每次只等一个) |
| C2.5 唯一响应、不得串核 | **需修改** | 单核下由 `RD2BridgeV2.scala:149` `assert(tl.d.bits.source === 0.U)` 保证。双核:每桥仍只有本地 source 0,TLXbar 按 client 重映射并按 source 路由 D 回对应桥——**这是 rocket-chip TLXbar 的语义,不是本项目代码**;M2 用两个独立协议驱动器验证"无错投/无重复"(TESTPLAN T2.1) |

---

## C3. 跨核 source 路由与 hart 标识

### 现状(单核)

* 桥声明 client `"teaching-phys"`,`IdRange(0, 1)`(`RD2BridgeV2.scala:28`)。
* TLXbar 给每个 client 分配全局 source 区间;后端在其内侧 edge 上**按名字**找 CPU client,读其 `sourceId.start/end`(`AtomicBackend.scala:60-65`),并在首周期打印 `CPU_SOURCE lo= hi= clients=`。
* 实测:`cpu-atomic-backend/run8/amo-basic/run.log` 首行 `CPU_SOURCE lo=2 hi=3 clients=3`——CPU 是 3 个 client 之一(另两个是 `rd2-serial` 与块设备 tracker),**hart 0 的 source 是 2,不是 0**。这正是方案 §3 "不得假设 hart ID 等于 TL source ID"的实证。

### 阻断项 B1(必须改,否则 SC 语义错)

`AtomicBackend.scala:60`:

```scala
val cpuClient = edgeIn.client.clients.find(_.name == cpuClientName)
```

两个桥同名 `"teaching-phys"` 时,`find` 只命中第一个:hart 1 的所有事务被 `isCpuSrc` 判为**非 CPU**(`:70`)。后果不是"性能差",而是:hart 1 的 LR 不建预约、hart 1 的 SC 走 `aIsSC = aMark && …`(`:105`)中 `aMark` 为假 → 被当作**普通 Put 直接写入**(`:118` `in.a.ready := Mux(acceptNew, Mux(aIsAmo || aIsSC, true, out.a.ready) …`,非 AMO/SC 直通)→ **SC 永远成功且不检查预约**;同时 hart 1 的 mark 永远不会被 `markQ.io.deq` 消费(`:120` 要求 `aIsCpu`)→ 队列满 → `:79` 断言触发(仿真)或静默错乱(板上)。

**契约 C3.1(需修改;按裁决 D4)**:hart→source 区间→侧带索引必须是**显式绑定**,不是排序也不是前缀匹配。做法:每个 `TeachingHart(hartId)` 用**唯一精确** client 名 `s"teaching-phys-$hartId"` 声明其 TL client,并把同一个 `hartId` 用于其侧带 `Vec` 下标;后端在 elaboration 时对 `0 until numCores` 逐个按**精确名**在内侧 edge 上解析 client(不是 `find` 前缀),得到 `cpus(hartId) = (lo, hi)`,并 `require`:(a) 每个期望名恰好解析到 1 个 client;(b) 数量 = `numCores`;(c) 区间两两不重叠;(d) 内侧 edge 上所有名字以 `teaching-phys` 开头的 client 都被解析到(完整性,防止漏接);(e) 侧带 `Vec` 长度 = `numCores`。运行时 `cpuIdx(s)` 由这张表给出。**排序只能唯一编号,不能证明与 wrapper 的 hartId 及侧带顺序一致,故被拒绝。**验证:交换两个 `sbus.fromPort` 的连接顺序、再加入一个非 CPU client(如第二个 DMA),elaboration 与 T2.5 仍正确(TESTPLAN T2.7)。

**M1 的边界(按裁决"实施顺序")**:M1 **保持**旧的单核 client 名 `"teaching-phys"` 与单套侧带不变——现后端 `find + require` 精确要求该名(`AtomicBackend.scala:60-62`),M1 改名会直接 elaboration 失败。显式多核身份迁移**统一在 M2** 执行。M1 不得以 `numCores = 2` 能 elaborate 暗示可用。

**契约 C3.2(需修改)**:mark 侧带(`PhysPortV2.scala:39-43` `AtomicSideband`)与 `scResult` **每 hart 一套**;后端 mark 队列 **每 hart 一个**(仍各深 1,断言不变)。`markQ.io.deq.ready`(`AtomicBackend.scala:120`)按 `cpuIdx(a.source)` 选队列。

**契约 C3.3(已存在,保持)**:CPU 不携带事务 ID;`txid` 仅是桥内追踪计数(`RD2BridgeV2.scala:59`)。

---

## C4. 仲裁与公平

| 条款 | 状态 | 证据 / 修改点 |
| --- | --- | --- |
| C4.1 仲裁锁住已提出未握手的选择 | **未证明(框架)** | 两桥各挂 `sbus.fromPort`(现 `RD2Soc.scala:126-128` 单个);TLXbar 的 A 仲裁由 rocket-chip 实现,其锁定与轮转行为**在本项目内没有源码引用或测试证据,不标为已证明**;M2 以驱动器测试(TESTPLAN T2.3)取证 |
| C4.2 AMO 两半之间不释放原子保护 | **已存在** | 后端 `acceptNew = state === sIdle`(`AtomicBackend.scala:117`);AMO 走 `sGet → sPut → sResp` 全程 `acceptNew` 为假,`in.a.ready` 在非 idle 时只对 `sPass && !kindSC` 放行(`:118`)。**任何 source** 的 A 都无法插入,包括另一 hart 与 DMA |
| C4.3 SC 检查与提交不可被写插入 | **已存在** | 同上;SC 在 `sScCheck/sPass` 期间 `!kindSC` 条件关闭内侧 ready(`:118`) |
| C4.4 全局串行完成 | **已存在** | `acceptNew` 单状态;方案接受其吞吐上限。**量化**:后端串行 + `TLBroadcast`(4 tracker)+ 单 AXI HP0 口;两核共享同一串行点,DRAM 密集负载下 S2 上限受此支配(REPORT §4.4) |
| C4.5 公平性:下游最终响应、各消费者最终接收 ⇒ 每 hart **最终**被服务 | **需测试** | "有限完成"假设只给出最终性,**不自动给出固定周期上界**;要得到上界还需限定最大下游延迟(AXI/DDR 响应上限)。TESTPLAN T2.3 在给定的最大下游延迟下测量每 hart 最大等待并记录,不预设常数 |

---

## C5. 原子性:每 hart 预约

### 现状

单预约 `{resvValid, resvWord[28:0]}`(`AtomicBackend.scala:89-90`),事件表(`:122-137` 与 `DESIGN.md:66-74`):

| 事件 | 动作 | 行 |
| --- | --- | --- |
| CPU LR(marked Get)被接受 | `valid←1, word←addr[31:3]` | `:127` |
| CPU SC(marked Put)被接受 | 消费 mark;成败在下方判定;无论成败预约清除 | `:129`, `DESIGN.md:61` |
| **CPU 自身**写(Put/AMO)与 word 重叠 | `killResv("cpu-write")` | `:131-132` |
| **非 CPU** source 写与 word 重叠 | `killResv("external-write")` | `:133-134`(`faultNoKill` 为负向控制) |
| 侧带 `resvClear`(核 trap/复位) | `killResv("core-clear")` | `:139` |
| LR 的 D 带 error | 清预约 | `DESIGN.md:57` |
| 粒度 | 8 字节 granule,重叠按 `[addr, addr+2^size)` 与 `[word, word+8)` 区间判定 | `:111-112` |

### 契约(需修改)

**C5.1** 预约数组 `resv[NHARTS]`,每项 `{valid, word[28:0]}`;`resvClear`、mark、`scResult` 按 hart 索引。

**C5.2 失效规则(逐条)**——写来源 `w` 与预约 `resv[h]` 重叠时:
* `w` 是 hart `h` 自己的 Put/AMO → 清 `resv[h]`(现 "cpu-write");
* `w` 是**另一 hart** 的 Put/AMO/**成功的 SC** → 清 `resv[h]`(新:现代码里另一 hart会被当 external,行为恰好正确,但只是巧合,须显式);
* `w` 是 `rd2-serial`(TSI)或块设备 DMA → 清所有重叠的 `resv[*]`(现 "external-write",推广到数组);
* hart `h` 的 SC:**失败的 SC 没有执行写**,只清 `resv[h]`;**成功的 SC 是一次写**,按上一条对其他 hart 的重叠预约生效(使之失效),同时清 `resv[h]`(按裁决 D3;TESTPLAN T2.5 覆盖)。

**C5.3 SC 判定**:`resv[h].valid && resv[h].word == addr[31:3]`,在 `sIdle` 接受时一次性判定并锁定 `kindSC`(现 `:129` 结构不变),期间 `in.a.ready` 关闭 ⇒ 另一 hart 的写不能插在"检查"与"提交"之间(C4.3)。

**C5.4 trap/reset**:核 `resvClear`(`tcpu_core.v:181`)只清**自己**的 `resv[h]`;全系统复位(`RD2ZynqTopModule` 的 `reset`)清全部——后端 `RegInit(false.B)`(`:89`)本就如此。

**C5.5 错误路径**:AMO 读错不写(`DESIGN.md:58` `RESP_ERR`)、AMO 写错一次报告、LR 错清预约——**已存在**,与 hart 数无关;仅需 per-hart 化 `scResult` 回送。

**C5.6 partial store 与 .W**:重叠判定用字节区间(`:111-112`),partial Put(mask 不满)也按 size 区间 → **保守正确**;`.W` 的老值符号扩展在核内(`tcpu_core.v` CPU-A 路径),与 hart 数无关。

**C5.7 所有写入来源的清单(审计结论)**:进入后端内侧 edge 的 client = `teaching-phys`(CPU)、`rd2-serial`(`RD2Serial.scala:45`)、`RD2BlockDeviceController` 的 tracker(`post_synth_utilization_hier.rpt` 行 `controller`);后端位于 sbus 之后、`TLBroadcast` 之前(`DESIGN.md:10-24`),**只有 DRAM 流量经过它**,ROM/MMIO/error slave 不经过——它们不是 DRAM,不影响预约。**PS(ARM)自身的 DDR 访问在任何硬件串行化之外**(`DESIGN.md:38`)——见 C9。

---

## C6. 顺序与可见性

| 条款 | 状态 | 证据 |
| --- | --- | --- |
| C6.1 可见性以事务完成点(后端 `sIdle` 回到、D 发出)定义,不以 `req.fire` 定义 | **已存在(结构)** | 后端串行:一笔 DRAM 事务在前一笔 D 完成前不被接受(`AtomicBackend.scala:117-118`)。因此**任何两个 DRAM 事务在后端处全序**,顺序 = 后端接受顺序 |
| C6.2 `aq/rl` | **已存在,无效果** | `tcpu_core.v:288` "aq/rl are accepted … no further effect (one in-order …)";核每次一笔在途,后端全序 ⇒ 单核上 aq/rl 隐含满足。双核:后端全序 + 每 hart 单在途 ⇒ 任一 hart 观察到的他核写顺序 = 后端顺序 ⇒ **强于 RVWMO**;第一版采纳"比 ISA 更强的串行化"(方案 §3) |
| C6.3 `FENCE` | **已存在,无效果** | 同上(`is_fence` 仅退休,`:754`);在全序后端上正确 |
| C6.4 哪些通路仍可能乱序 | **审计结论** | (a) **不经后端的通路**:ROM/MMIO/CLINT/PLIC 走 pbus,与 DRAM 事务之间**无全序**——但它们都是设备寄存器,ISA 本就不要求与普通内存全序;xv6 对 CLINT/PLIC 的访问是自包含的。(b) `TLBroadcast` 4 个 tracker 在后端**之后**并发,但后端一次只放一笔进去 ⇒ 无并发。(c) `mbus` 的 `TLAtomicAutomata`(`atomics` 399 LUT)在 `TLToAXI4` 前,处理后端**已拆成 Get/Put** 的 AMO——后端不下发 Arithmetic/Logical(`DESIGN.md:58`),该模块对本设计是死逻辑,不构成乱序源 |
| C6.5 loader/磁盘写入的可见性 | **已存在** | TSI 与块设备 DMA 都经后端,与 CPU 事务全序;fesvr 在 `request_restart_and_wait` 期间不发 TSI(`fesvr_teaching.cc:82-86`),即 ELF 装载与 CPU 运行不重叠 |

---

## C7. 复位、drain、全局 quiesce

### 现状(单核,RD1 契约)

`BridgeDrainIO`(`RD1Bridge.scala:33-41`):`softReset` 电平 → 桥 `rIdle → rDrain → rApply`(`RD2BridgeV2.scala:53-70`);`cpuResetHold = effReset || (phase =/= rIdle)`;核以 `withReset(reset || drain.cpuResetHold)` 实例化(`RD2Soc.scala:190-192`)。`cpuRestartSafe := drain.applying && applyCnt ≥ 1 && !pendingWork`,`pendingWork = drain.pendingA || drain.outstanding`(`RD2Soc.scala:224-225`)⇒ **在途事务完成后才宣告可重启**,已提交写不会被丢弃为"完成"。`RD2Clint.io.applyReset` 在 `drain.applying` 上升沿脉冲一次(`:182`),清 msip、保留 mtime、不复位 mtimecmp(`RD2Clint.scala:13-17`)。串口适配器**无软复位**(`RD2Serial.scala:16-18`),块设备 hold 后 flush 完成队列(`RD2BlockDevice.scala:9-11, 63-66`)。

### 契约(需修改)

**C7.1** `softReset` 扇出到**每个**桥;`cpuResetHold_i` **各自**驱动各核的复位——但为满足"统一 quiesce/drain 后复位所有 hart",apply 阶段须**对齐**:`applying_all = AND(bridge_i.applying)`,`pendingWork = OR(bridge_i.pendingA || bridge_i.outstanding)`,`cpuRestartSafe = applying_all && applyCnt ≥ 1 && !pendingWork`。**在 `applying_all` 之前任何核都不得脱离复位**——否则先释放的核开始发请求,`pendingWork` 永不清零。实现:各桥的 `cpuResetHold` 与一个全局 `holdAll = OR(cpuResetHold_i)` 取或后驱动每核复位。

**C7.2** `RD2Clint.applyReset` 仍**一次**脉冲,取 `applying_all` 上升沿;清全部 `ipi[*]`。

**C7.3 不支持单 hart 热复位**(方案 §3):`softReset` 是唯一复位请求,无 per-hart 变体。`status.msip`(`RD2Soc.scala:87`)**保持为 hart 0 的 msip**(裁决 D5);它只说明 host 已唤醒 hart 0,**不证明所有核已启动**——各核是否启动以每核的启动/退休记录验收(TESTPLAN T3.1、T4.1)。

**C7.4 R-BOOT 块设备 drain**(`RD2Soc.scala:257-276`)与 hart 数无关,保持。

---

## C8. 启动与中断

### C8.1 BootROM(已存在,**已支持多 hart**)

`evidence/bootrom.dis`(156 字节,sha256 `1ca1cbf08c789878…`,来源 `teaching-cpu-work/fpga-zynq/common/src/main/resources/teaching/bootrom.teaching.rv64.img`,`hang = 0x10040`):

```
10040  mtvec ← 0x10000 ; mie ← MSIE ; mstatus.MIE ← 1 ; wfi/j 空转      ← 所有 hart 从此复位向量起
10000  a1 ← 0x2000000(CLINT) ; a0 ← mhartid ; beqz a0 → 10010 ; else → 10064
10010  hart0: a2 ← msip[1] ; 循环 { msip[i] ← 1 ; 回读 ; 若回读非 0 则 i++ 继续 } → 10074
10064  hart≠0: 自旋直到 msip[0] == 0 ; a1 ← &msip[hart]
10074  msip[hart] ← 0 ; mepc ← 0x80000000 ; a0 ← mhartid ; a1 ← dtb ; 清 MPIE ; mret
```

* host 唤醒 = `tsi_t::reset()` 写 `MSIP_BASE 0x2000000`(`riscv-fesvr/fesvr/tsi.cc:26-33`),在 `load_program()` 之后(`htif.cc:85-95`)—— **只写 hart 0**。
* hart 0 被软中断带到 `0x10000` 后**自己**唤醒 hart 1..N(以回读探测 msip 是否存在),再清自身 msip;hart≠0 等 hart 0 清零后再走。**因此双核不需要 host 改动,也不需要内核发 IPI。**
* 前提:`RD2Clint` 有 `nTiles = 2`(`RD2Clint.scala:53-55` 按 `intnode.out.size` 生成 `ipi`/`timecmp`),即 SoC 为第二个核再接一个 `IntSinkNode`。回读探测依赖"不存在的 msip 回读 0"——**未确认**(依赖 regmapper 对未映射偏移的行为);最小补证:M2 elaboration 后仿真 ROM,断言 hart 0 的探测循环在 `i = NHARTS` 处停止。
* 核的 `wfi` 是**空操作**(`tcpu_core.v:361-363`),ROM 的 `wfi; j` 即忙等;中断在 `S_IF_REQ` 边界采样(`:470-473`)⇒ 行为正确,只是不省电。

### C8.2 内核入口(已存在)

* `entry.S`:`sp = stack0 + 4096 × (mhartid + 1)`;`param.h:2` `NCPU 8` ⇒ 栈区足够。
* `start.c:62-66`:`timerinit(); w_tp(r_mhartid())`;`main.c:13-48`:`cpuid()==0` 做全局初始化,`__atomic_store_n(&started,1,RELEASE)`;其他 hart `while(load_acquire(&started)==0)`,再 `kvminithart/trapinithart/plicinithart` → `scheduler()`。**xv6 原生启动协议在此内核中完整保留。**

### C8.3 每核 timer / msip(已存在)

* `RD2Clint` 在 `0x0200_0000` 挂 pbus(`RD2Clint.scala:84-88`);子系统自带 CLINT 被**停放**到 `0x0300_0000` 且无人接线(`RD2Soc.scala:678-682` 注释)。内核二进制常量:`lui 0x2000`/`0x2004`(`evidence/kernel-4mib.dis`)⇒ 一致。
* `msip_i` / `mtimecmp_i` 按 hart 索引(`RD2Clint.scala:66-70`);`memlayout.h:34,38` `CLINT(hart)`、`CLINT_MTIMECMP(hartid)`;`start.c:85-96` 每 hart 以 `r_mhartid()` 设 `mtimecmp` 与 `mscratch`;`kernelvec.S:122-127` `timervec` 从 `mscratch[3]` 取本 hart 的 `CLINT_MTIMECMP(hart)` 重装。
* 接线 **需修改**:`RD2Soc.scala:133-134` `clintSink := rd2clint.intnode` 一个 sink ⇒ 第二核再声明一个 `IntSinkNode` 并各接 `cpuIrq_i.msip/mtip`(现 `:206-209`)。

### C8.4 设备中断(已存在,**当前无任何设备中断**)

* PLIC 存在(`plic|TLPLIC` 47 LUT/63 FF),1 个上下文接 `plicSink`(`RD2Soc.scala:135-136`),**无设备驱动它**(`TeachingCpuSoc.scala:53-54` 同款注释)。
* 内核:`plicinithart()` 写 S 模式上下文(`plic.c:20-29`),`devintr()` 的 PLIC 分支(`trap.c:189-199`,`UART0_IRQ=10`/`VIRTIO0_IRQ=1`)**在本平台是死代码**——控制台是 HTIF、磁盘是轮询式 `blkdev.c`,二者都无中断线。
* 双核:PLIC 需第二上下文(再接一个 sink),仅为让 hart 1 的 `plicinithart()` 写到存在的寄存器;功能上仍无中断。**未确认**:对不存在上下文的 PLIC 写是否被 ack 而非 error(单核时 hart 0 写 S 上下文 `0xC002080`,PLIC 只有 1 个上下文却启动正常,推断 regmapper 对未映射偏移 ack)。最小补证:仿真中对 `0xC002080` 做一次写读,断言无 access fault。

### C8.5 定时器节拍来源

`clockintr()`(`trap.c:167-184`)由 M 模式 `timervec` 反射为 S 软中断(`start.c:79`)——每 hart 独立;`ticks++` 仅 hart 0(`:169-173`)。**已存在。**

---

## C9. host / loader / 磁盘对目标 DDR 的写入

| 通路 | 是否经后端 | 证据 | 契约 |
| --- | --- | --- | --- |
| ELF 装载(fesvr → TSI) | **是** | `rd2-serial` 是 sbus client(`RD2Serial.scala:45`);后端在 sbus 之后 | 与 CPU 事务全序;且装载期间 CPU 在复位(`fesvr_teaching.cc:82-86, 95-102` 先 `request_restart_and_wait`,后释放) |
| host 唤醒写 msip | 否(pbus) | `tsi.cc:33` | 设备寄存器,不涉及普通内存 |
| 块设备 DMA | **是** | tracker 是 sbus client;完成队列在 `RD2BlockDeviceRouter`(`RD2BlockDevice.scala:52-70`) | 写入 `pa` 指定的缓冲;内核在 `blkdev_lock` 下同步等待完成(`blkdev.c:68,142-148`),完成前不读缓冲 ⇒ 无 D-cache,读到的即 DMA 写入值 |
| fesvr `/dev/mem` | **只映射 MMIO 寄存器** | `fesvr_teaching.cc:43-45, 87` `teaching_mmap_regs` | 不触碰 DDR 窗口 |
| PS(ARM Linux)自身 | **在串行化之外** | `DESIGN.md:38` 平台规则 | **运行时所有权**:目标 DDR 窗口(HP0 映射 512 MB 的上 256 MB,`rocketchip_wrapper.v:261` `{4'd1, addr[27:0]}`)由 Linux 保留、不作普通内存;每次会话前 `MEM_PREFLIGHT` 读 `/proc/iomem`、设备树与内存证据核对(`board/session-*/mem-preflight.json`,IPS 战役五次会话均 `refusals=0`)。**这是"允许区域"的实际机制:不是硬件,是预检 + 平台约定。**双核不改变它 |

**审计结论(收窄)**:在**已审计的软件路径**(fesvr/TSI 装载、块设备 DMA、`/dev/mem` 仅映射 MMIO)内,没有绕过后端的并发普通内存写通路。PS 自身处于硬件串行化之外;`MEM_PREFLIGHT` 核验的是**保留内存配置**(该区域不作 Linux 普通内存),**不证明运行期间不存在任意 PS 写入**——那是平台所有权假设,不是测量。双核不改变这一假设的性质。

---

## C10. 维护操作:satp / SFENCE.VMA / FENCE.I

### 硬件语义(已存在,均为**本地**)

| 操作 | 核内动作 | 行 |
| --- | --- | --- |
| `satp` 写 | 全 TLB 清空 | `tcpu_core.v:508` `tlb_flush = satp_write \|\| (S_ARCH && is_sfence)`;`tcpu_tlb.v:9` "conservative full flush on every sfence.vma and every satp write, so no ASID" |
| `SFENCE.VMA`(任何形式) | 全 TLB 清空 | 同上 |
| `FENCE.I` | 全 I-cache 失效,且**在途 refill 作废** | `tcpu_core.v:160` `icache_flush`;`tcpu_ifill.v:21-26` `killed` |
| store 命中 I-cache 行 | **不**失效 | `tcpu_ifill.v:92-93` 写直通、`tcpu_icache.v` 无写侦听。I-cache 物理标记,`tag = pa[31:10]`,64 行(`tcpu_icache.v:1-4,38,57`) |
| 非规范 VA 命中 TLB | 不使用 | `tcpu_xlate.v:104-119` `hit_usable = tlb_hit & canonical` |

### 内核代码路径(已存在)与跨核结论

**页表更新与 TLB**(方案 §3 要求给出实际路径,不得无据要求或省略 shootdown):

* 用户页表只在**本进程上下文**中修改:`growproc`(`proc.c:236-250` → `uvmalloc/uvmdealloc`)、`exec`(`exec.c:72,91` 建新表,`:138` 释放旧表)—— 都由该进程自己的系统调用在其所在 hart 执行。
* 他核释放本进程页表的唯一路径:父进程 `wait()` → `freeproc`(`proc.c:156-162`)→ `proc_freepagetable` → `uvmunmap(do_free=1)`(`vm.c:205`)。此时子进程已是 ZOMBIE,**不在任何 hart 上运行**;曾运行它的 hart 在切走时已装入别的 `satp`,而 `satp` 写 = 全清(上表)⇒ 该 hart 不可能持有子进程的陈旧项。
* 内核页表在 `kvminithart()`(`vm.c:85-93`)之后不再修改(无 `kvmmap` 运行时调用)。
* **结论:在"每次 satp 写全清 + 无 ASID"的硬件上,xv6 现有代码路径不产生跨核陈旧 TLB 项;不需要远程 shootdown,也没有被"暂不支持"掩盖的情形。**这是对**当前内核**的结论;若未来引入 ASID 或不再逢 satp 写全清,须重新审计。

**代码可见性与 I-cache**:

* 用户程序代码进入内存的路径:`exec` → `loadseg` → `copyout`(CPU store),不是 DMA 直写用户页;块设备 DMA 只写 `bio` 缓冲。
* `trampoline.S:100-107` `userret` **每次返回用户态都执行 `fence.i`**("in case this is the first time we're running this proc on this hart"),随后 `sfence.vma; csrw satp; sfence.vma`。⇒ 任一 hart 在执行任何用户代码之前都已清空自己的 I-cache。**exec、fork、迁移三种情形全部被这一条覆盖,无需新增跨核同步。**代价是每次 `userret` 丢掉 1 KiB I-cache(REPORT §4.3 记为已知性能项,不是正确性项)。
* 内核代码启动后不变;`riscv.h:384` 提供 `fence.i` 封装。

### 契约(已存在,保持)

**C10.1** 本地 `SFENCE.VMA`/`FENCE.I` **不是**跨核广播,契约不承诺广播。
**C10.2** 未来流水线实现必须保持"`satp` 写全清 TLB"或提供等价的跨核语义证明;否则 C10 的内核结论失效。

---

## C11. 双核下内核/host 的单核假设清单

| 项 | 现状 | 判定 | 修改点 |
| --- | --- | --- | --- |
| HTIF 输出 `tohost` | `uartwrite` 持 `htif_tx_lock`(`htif.c:44,66,84-87`);`printk` 持 `pr.lock`(`printk.c:71,132`);`panic` 置 `panicked=1` 冻结他核输出(`:143`) | **安全** | 无 |
| HTIF 输入 `fromhost` | `htif_getc` 读后清零(`htif.c:95-100`)由 `uartintr` 调用(`:117-122`),而 `uartintr()` 在 `clockintr` 中位于 `if (cpuid()==0)` 块**之外**(`trap.c:167-184`,第 19 行)⇒ **每个 hart 的节拍都轮询 `fromhost`** | **缺陷**:两 hart 可各读到同一字符再各自清零 → 输入重复;或一方清零另一方漏读 → 无丢失但不确定 | 限定 hart 0 轮询(裁决 D6),但**不得放进 `tickslock` 持锁区**:现代码 `uartintr()` 已在 `release(&tickslock)` 之后(`trap.c:173-183`),改法是在其外再套一个独立的 `if (cpuid() == 0)` 分支。回归须**构造受控竞态**(TESTPLAN T4.2),不以随机交互必现重复为准 |
| 块设备 | `blkdev_rw` 全程持 `blkdev_lock`,内部同步轮询完成(`blkdev.c:142-148, 92-130`) | **安全(串行)** | 无;吞吐由锁串行 |
| `ticks` | 仅 hart 0 累加(`trap.c:169-173`) | 安全 | 无 |
| 调度器空闲 | `proc.c:476` "Deliberately no wfi() here" 忙等;核的 wfi 也是 NOP | 安全 | 无 |
| `exit`/停机 | 板上"刻意停止"是 host 端 Ctrl-C(exit 130),不是目标端 `tohost` exit;`init` 不退出 | 安全 | 无 |
| 磁盘镜像 | 每样本新拷贝(`campaign.sh`),交互用 `fs-interactive.img` | 与 hart 数无关 | 无 |
| `NCPU` | 8 | 足够 | 无 |

---

## C12. 未来流水线约束(契约条款,现无实现)

* **C12.1** 仅使用 C1.2 端口;`dbg_state/dbg_redirect` 移出对外 bundle(C1.2)。
* **C12.2** 已提出请求不得因 flush 撤销(C2.1);错误路径取指的响应到达后丢弃、不提交异常;当前多周期核在响应前不进入 `S_TRAP`(`tcpu_core.v:470-473` 仅 `S_IF_REQ` 采中断;`S_IF_WAIT`/`S_MEM_WAIT` 的 trap 都在 `ic_resp_valid` 之后,`:618-620`)——流水线须保持"无响应不 trap"的等价物。
* **C12.3** store/AMO/MMIO 仅在不可能成为错误路径时发出。
* **C12.4** 每 hart 单在途(C2.3)在流水线上意味着结构冲突;明确记录,不承诺 1.x CPI。

---

## 决策请求(汇总,详见 REPORT §6)

已裁决(`codex-mc-m0-review-fixes`):D1 批准 per-hart 方向、映射按 D4;D2 最差路径仅认可为风险,增量为未验证推测,不预插 TLBuffer;D3 成功 SC 作为写使他 hart 重叠预约失效、失败 SC 只清自己;D4 拒绝排序赋号,改显式精确绑定 + elaboration 检查;D5 `status.msip` 保持 hart 0 且不证明全核启动;D6 限 hart 0 轮询、不入 `tickslock` 区、受控竞态回归;D7 批准稳定观察接口,不做重型编译测试框架;D8 冻结源文件清单/哈希/构建参数/工具身份,收窄"树可复现二进制"的声称;D9 本轮无需 Vivado,LUT 折算率不套用到 FF。
