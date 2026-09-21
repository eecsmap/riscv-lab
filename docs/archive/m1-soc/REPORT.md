# M1 集成仿真：无 CPU 事务发生器接入旧 SoC（Claude，2026-09-15）

任务书 `.coord/proposals/codex-m1-soc-integration.md`；接口 `experiments/teaching-cpu/PHYSICAL_PORT_V1.md`（冻结）；桥与测试器沿用已验收的 M1-b 实现。本轮**只做仿真**：未跑 Vivado、未烧板、未改 PS/rootfs、未启动 M2。

## 1. 结论

被测通路真实走通：**事务发生器 → PHYSICAL_PORT_V1 → ReqRespToTL → 旧 SoC 的 sbus → mbus → TL/AXI4 转换 → `SimAXIMem`**。三个配置全部符合预期（`evidence/soc-matrix.txt`，`SOCTB_DONE fails=0`）：

| 配置 | 退出码 | 事务 | 错误 | size 0/1/2/3 | 部分掩码 | 读回 | error 从设备 | 本地拒绝 | resp 背压 | A 等待 | AXI ar/r | AXI aw/w/b |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| basic | **0** | 768 | 0 | 147/147/157/317 | 190 | 317（其中 **315 笔是 DRAM 数据比对**） | 2 | 7 | 0 | 0 | 315/315 | 443/443/443 |
| backpressure | **0** | 768 | 0 | 217/185/125/241 | 144 | 317 | 2 | 7 | 1157 | 243 | 315/315 | 443/443/443 |
| fault-payload（故障对照） | **1** | 768 | 84 | 171/163/143/291 | 177 | 317 | 2 | 7 | 0 | 279 | 315/315 | 443/443/443 |

**这不是** DDR 性能实验，也不代表 xv6、HTIF/DMA 并发或 CPU 中断接线已验证；内存模型是 `SimAXIMem`，不是板上 PS DDR。

## 2. 接线（实测的真实映射）

`TeachingBusTestZynqTop` = `RocketSubsystem`（`RocketTilesKey = Nil`，**不实例化 Rocket**）+ `HasMasterAXI4MemPort` + `HasSystemErrorSlave` + `HasPeripheryBootROM` + `HasSyncExtInterrupts` + `HasNoDebug` + `HasPeripherySerial` + `HasPeripheryBlockDevice`——与 Rocket 版 `FPGAZynqTop` 的 trait 列表逐项相同，**没有删除任何外设**。教学 master 用与 testchipip 块设备相同的写法挂总线：`sbus.fromPort(Some("teaching"))() := bridge.node`（背压配置在其前插一个 `TLDelayer(0.25)`，仅在测试路径上）。

精化时打印的真实地址图（`evidence/*/addrmap.txt`）：

```
Interrupt map (1 harts 3 interrupts):
       0 -     1000 ARWX  debug-controller@0
    3000 -     4000 ARWX  error-device@3000
 2000000 -  2010000 ARW   clint@2000000
 c000000 - 10000000 ARW   interrupt-controller@c000000
10015000 - 10016000 ARW   blkdev-controller@10015000
```
DRAM 不在此列，因为它在 mbus 之外经 AXI4 主口出去——正是本轮要证明的通路。测试窗口取 DRAM 内 `0x8000_0000 + 0..0x3FF`（128 个 64 位字，先整块初始化再读）；error 从设备取 SoC 自带的 `0x3000`；未映射地址取 `0x5000_0000`，由上表确认无任何管理者覆盖；`beatBytes = 8`，桥为单 source（`IdRange(0,1)`）。

**AXI 通路证据**：在 `mem_axi4.head` 上按通道独立计数（AR/R/AW/W/B 各自握手，不假设同拍），三个配置一致为 **AR=R=315、AW=W=B=443**，读写均非零；运行结束时 `outstandingAr = 0`、`outstandingAw = 0`，无遗留事务。若把 DRAM 换成桥旁的 TLRAM，这些计数会全为 0——所以它同时是"没有用旁路 RAM 冒充"的证据。

## 3. 零 tile 带来的三处必要适配（如实记录，均只在测试配置内）

旧子系统的若干部件假定至少有一个 tile。按任务书要求**不删外设**，改为在测试配置里补一个替身：

| 部件 | 报错 | 适配 | 含义 |
|---|---|---|---|
| PLIC | `require(nHarts > 0)`（`Plic.scala:133`） | `IntSinkNode` 替身接 `plic.intnode` | PLIC 仍在设计中；**不代表** CPU 外部中断已验证 |
| CLINT | 同类（无中断目的地） | `IntSinkNode` 替身接 `clint.intnode` | CLINT 仍在；msip/mtip 未被任何核消费 |
| Debug module | `Vec.fill(nComponents)` 在 0 时 require 失败（`Debug.scala:352`） | `IntSinkNode` 替身经 `IntSyncCrossingSink(3)` 接 `debug.intnode` | 调试模块仍在；DMI 仍由 `HasNoDebug` 置闲 |
| `HasTilesModuleImp.resetVectorBits` | 零 tile 时读 `tiles.head` → `tail of empty list` | 在测试模块里 `override def resetVectorBits = 32` | 复位向量线仍由 BootROM 驱动，只是无人消费 |

这些适配只存在于 `TeachingBusTestZynqTop`/`TeachingSocHarness`；Rocket 配置、`Top.scala` 的板级接口、比特流流程一律未改。

## 4. 判定与门禁

- **done/failed 直连独立 harness**（`TeachingSocHarness`），`soc_tb_main.cpp` 返回 0 = done 且 !failed、1 = done 且 failed、2 = 超时；Chisel 断言自行 abort（非零）。不引入 tohost/ELF/fesvr 依赖；TSI 与块设备端口保留但合法置闲，**不声称** HTIF/DMA 并发已测。
- 沿用 M1-b 的逐笔 scoreboard 与协议检查：请求/响应握手前保持、响应不与请求握手同拍、单在途、写必须有对应 TL D 才算完成、错误与写响应 `rdata = 0`、协议断言开启（`STOP_COND=1`）。
- 非法/受限用例在**真实 SoC** 上的可构造性（如实报告）：
  - 本地非法（掩码 0、掩码越界、4/8 字节未对齐）：4 例，零 TL 事务 ✓
  - 未映射地址（`0x5000_0000`）读写：2 例，零 TL 事务 ✓
  - **已映射但操作不支持**：对 BootROM（`0x10000`，只读）的写 → 本地拒绝、零 TL 事务 ✓（这是 SoC 里真实存在的限制，没有伪造设备）
  - **已映射但尺寸不支持**：本 SoC 的管理者都支持 1..8 字节，**无法构造**，故本配置不含该用例；对应覆盖保留在 M1-b 单元测试（自建的只支持 8 字节读的 manager），引用 `experiments/teaching-cpu/m1/evidence/bridge-*`。
  - 合计 `covIllegal = 7`（单元配置为 8，差的就是上面这条）。
- **读回计数的口径**（Codex 复核指出）：`covReadback = 317` 是"读事务"的总数，其中 **315 笔是 DRAM 上逐字节比对过数据的读回**（15 笔定向 + 300 笔随机），另外 2 笔分别是 BootROM 的一次合法窄读（内容未比对，只验证它不被本地拒绝）和 error 从设备的一次读（只验证 error 位）。不能把 317 都称作数据比对。
  - 真实 error 从设备（`0x3000`）读写 → 转发 `error`，`covErr = 2` ✓
- **故障对照**：`TeachingSocFaultConfig` 用桥的 faultMode 1（A 通道等待期间改写载荷），在集成环境里命中 84 次数据错误，首条 `TB ERR data=0x0000000000400000 expected=0x0000000000bf0000 addr=0x80000002 size=0 mask=0x04`，退出码 1。注意：该故障只有在 A 侧确实等待时才会发生，因此故障配置必须开启测试路径上的延迟器（首轮忘了开，测试通过 = 反例无效，已更正）。
- **超时入口**：`soc_tb_main.cpp` 的 timeout 返回 2；首轮因为在循环外重新采样脉冲式 `done` 而误报超时（测试器其实已 PASS），已改为在循环内锁存 done/failed，两处都留在报告里。

## 5. 复跑与身份

- 入口：`src/soc-tb-run.sh <outdir> <name> <config> <expect> ...`，每个场景**先删除已有 `.v`/`.fir` 再生成**（禁止按"文件存在"复用），新目录拒绝覆盖。作业脚本 `src/soc-job.sh`（claim `fpga-zynq-build-sbt`）。
- 身份记录：每例 `sources.sha256`（teaching 包 8 个源文件）+ `inputs.sha256`（生成的 RTL + 可执行文件），`tools.txt` 记 Verilator 版本；生成日志含完整地址图与中断图。
- 隔离树与版本沿用 M0/M1 的 `teaching-cpu-work`（清单 `experiments/teaching-cpu/m1/evidence/workspace-manifest.md`）。
- **单元配置仍可复跑**：本轮对共享代码的唯一改动是给 `BusTester` 增加 `narrowReadUnsupported` 参数（默认 `true` = 单元配置原行为），用于表达"smallBase 的窄读在 SoC 里是合法的（BootROM 支持窄读）、在单元测试里不支持"。桥 `ReqRespToTL` 功能未改。**M1-b 的 13 例已在此改动后完整回归通过**，见 §6。

## 5b. 复核后的窄修（Codex `m1-soc/CODEX_REVIEW.md` 的三项非阻断观察）

1. **`tools.txt` 为空**：版本查询写在加载工具环境之前且忽略了失败。已把采集移到 `source chipyard-env.sh` 之后，并同时记录 Verilator、riscv gcc 与时间戳。
2. **AXI 闭合未自动门禁**：原 runner 只检查计数下限，闭合由人工核验。现在每个场景自动要求 `AR == R`、`AW == W == B` 且读写均非零（本测试都是单 beat 传输），故障场景同样要求闭合——数据错了总线也必须收干净。
3. **`covReadback` 口径**：317 是读事务总数，其中 315 笔是 DRAM 上逐字节比对的读回，另 2 笔是 BootROM 合法窄读（只验不被拒绝）与 error 从设备读（只验 error 位）。报告 §1 表格与 §4 已注明。

新门禁用合成反例验证（`evidence/axi-gate-negative.txt`，`SOCGATE_NEG fails=0`）：真实通过日志被接受；`ar≠r`、`b` 少一笔、读计数为零、整行缺失四种伪造日志各按对应理由被拒。**这些是对 checker 的验证，不是新的 RTL 运行**；§1 的三例结果仍来自已验收的那一轮，未重跑、未覆盖。

## 6. 未做 / 待办

- ~~M1-b 13 例回归~~ **已完成**：加参数后强制重生成 RTL 重跑 13 例，`BRIDGETB_DONE fails=0`，逐例数值与验收时一致（`evidence/m1b-regression.txt`；如 clean 968 笔 0 错误、zerolat 同拍 694、旧桥对照 A 等待 4004 拍、七个故障各按指定理由失败）。
- 桥进 SoC 后**未测**：TSI/块设备与教学 master 的并发、CPU 中断接线、bootrom 启动序列、热复位。
- M1-c 上板（Vivado/比特流/PS 侧触发）未做，按任务书不在本轮。
- `SimAXIMem` 是功能模型：不反映 PS DDR 的真实时序或带宽。
