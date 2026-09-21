# M1-a/b：旧板级仿真入口与物理口→TileLink 桥（Claude，2026-09-14）

任务书 `.coord/proposals/codex-m1-simulation-bridge.md`；接口 `experiments/teaching-cpu/PHYSICAL_PORT_V1.md`（冻结）。三种完成状态分列：**环境**、**桥单元**、**SoC 集成**。

## 1. 隔离工作树与工具（环境）
- 工作树 `~/fpga/teaching-cpu-work/fpga-zynq`：**纯文件拷贝**（不是 git worktree，原因见 §2 问题 1）于 fpga-zynq `726eb97` 的跟踪文件，子模块 rocket-chip `7cd3352c3`、testchipip `8bf7e85` 以 tar 拷贝（排除 .git/target/riscv-gnu-toolchain/emulator/verilator），板端口 `pynqz1/`（xv6-on-rocket-pynq-z1 `1b5c971` 的 board/，排除 Vivado 工程与比特流）；清单 `evidence/workspace-manifest.md`。共享 checkout 未切分支、未改动；参考系统/比特流/PS rootfs 未动。
- 旧树的 sbt 需 JDK 8：只有 `vivado-env:2025.2-sw` 镜像有（1.8.0_502）；主机 JDK 20 不可用；两镜像都没有 verilator/vcs。因此：RTL 生成在 sw 容器内跑（`gen-testharness.sh`，sbt 缓存独立于共享树 `teaching-cpu-work/.sbt`），Verilator 用主机 5.022（conda）。
- `simulation/Makefile` 是 **VCS-only** 流程（`vcs -full64`、`$(RISCV)/lib/libfesvr.so`），本机无 VCS；替代：`testchipip/csrc/verilator-harness.cc`（testchipip 自带的 Verilator main，顶层 `VTestHarness`，用 `tsi_t` 加载/轮询）+ `SimSerial.cc/SimBlockDevice.cc/blkdev.cc` DPI + 主机原生编译的 fesvr（`riscv-tools/riscv-fesvr` configure/make → `teaching-cpu-work/install/lib/libfesvr.so`，共享树里的 `common/build/libfesvr.so` 是 ARM 版）。`rocket-chip/vsrc/TestDriver.v` 不用（VCS 时序顶层）。
- 脚本：`gen-testharness.sh`（容器内 sbt/firrtl → `simulation/src/verilog/TestHarness.ZynqConfig.v`）、`build-sim.sh`（verilate + 链接）、`run-sim.sh`（跑 ELF，记录退出码/日志/哈希）。

## 2. M1-a 环境：结论与取证

**状态：可用。** 旧板级仿真通路在本机跑通，入口保留为 M1/M2 的集成环境。

- 生成：`gen-testharness.sh` → `simulation/src/verilog/TestHarness.ZynqConfig.v`，294,174 行，sha `d9c2fae9…`（容器内 JDK 8 + sbt 1.1.1/0.13.15 + 预建 firrtl.jar）。
- 构建：`build-sim.sh` → Verilator 5.022 模型 sha `3e0c88da…`（顶层 `zynq.TestHarness`，DPI 用 testchipip 的 `SimSerial.cc`/`SimBlockDevice.cc`/`blkdev.cc`，链接本机源码编译的 fesvr）。
- 运行：`run-sim.sh` → `hello.riscv`（sha `458d934c…`，与板上同一个 ELF）
  ```
  Hello from Rocket Chip on PYNQ-Z1!
  sum(1..100) = 5050 (expected 5050)
  64-bit shift OK (1<<40)
  PASS
  Completed after 6861 cycles
  ```
  进程退出码 **0**；证据 `evidence/hello-run.log`、`evidence/hello-inputs.sha256`。这条路径覆盖了真实的 TSI 加载（fesvr 写 DRAM → 写 CLINT MSIP → bootrom `mret` → 0x80000000）与 HTIF 控制台，与 M0 §4 的启动顺序一致。

**替代 VCS 的部分**（原 `simulation/Makefile` 是 VCS-only，本机无 VCS）：
| 原件 | 替代 | 理由 |
|---|---|---|
| `vcs` + `TestDriver.v` | Verilator 5.022 + 自写 `soc_main.cpp` | 无 VCS 许可；`TestDriver.v` 是 VCS 的时序顶层 |
| `$(RISCV)/lib/libfesvr.so` | `riscv-fesvr` 在本机 configure/make → `teaching-cpu-work/install/lib` | 共享树里的 `common/build/libfesvr.so` 是 **ARM 32 位**（给板上 PS 用的），主机不能链接 |
| testchipip `verilator-harness.cc` | 同结构的 `soc_main.cpp`（自己 include 生成头） | Verilator 5 的预编译头与 `-CFLAGS -include` 冲突 |

**踩到并已解决的五个环境问题**（都记在这里，因为症状与原因相距很远）：
1. `git worktree` 的 `.git` 是文件不是目录，firrtl 的 sbt-git 插件把它当**裸仓库**，`NoWorkTreeException` 直接让构建失败。改成不带 `.git` 的纯文件拷贝。
2. Verilator 5 的运行时头需要 **C++14 以上**，testchipip 沿用的 `-std=c++11` 会在 `verilated_types.h` 报 `std::exchange` 未定义。
3. `AsyncResetReg.v` 在 `RANDOMIZE_REG_INIT` 分支里有 `#0.002`，Verilator 5 要求显式 `--timing/--no-timing`。
4. rocket-chip 的 `PRINTF_COND=$c("verbose","&&","done_reset")` 会把 C++ 标识符内联进**生成的模型**，而模型的翻译单元看不到 main 里的全局量；用 `-include verilator.h` 补声明又撞上预编译头。最终改用 Verilator 自带的 `Verilated::assertOn()` 作 `STOP_COND`，由 main 在复位结束后打开——语义与 `done_reset` 相同且不需要外部符号。（此前用 `!reset` 也不行：`TLMonitor_54` 这类模块只有 `clock` 端口。）
5. testchipip 的 `serial_tick` 用 `vpi_get_vlog_info()` 取回 argc/argv，返回 0 就 `abort()`；必须给 Verilator 加 `--vpi` 用它自带的实现，并且**不能**在 main 里定义同名桩函数把它顶掉。症状是完全没有任何输出的 SIGABRT。

## 3. M1-b 桥与事务测试器

- `src/PhysPort.scala`：`PHYSICAL_PORT_V1` 的 bundle（addr32 / write / size=lgSize / wdata64 / wmask8；resp: rdata64 / error），外加 `laneMask`、`aligned` 两个纯函数。
- `src/ReqRespToTL.scala`：单在途状态机 idle → (illegal | A → D) → resp。请求在接受时锁存，TL A 的载荷来自锁存值，握手前不变；读 `edge.Get`、写 `edge.Put(…, mask)`（PutPartialData）；响应要求 `source=0` 且 opcode 与请求类型匹配（否则断言，不静默归一化）；`TLBundleD.error` 直接转成 `error`；读数据只保留请求字节通道；响应保持到 `resp.fire`，下一拍才回 idle，因此**响应握手当拍不接受新请求**。`faultMode` 1–5 是故意缺陷，用作测试器的正向对照。
- **合法性检查的关键发现**：`edge.Get/Put` 返回的 legal 标志是 `supportsXxxFast`，**只检查传输大小、假定地址已映射**。第一版桥用它做地址检查，未映射地址被交给 crossbar 后被静默路由到某个管理者并正常返回——测试器抓到了（`TB ERR locally illegal request reached TileLink`）。改用 `edge.manager.supportsGetSafe / supportsPutPartialSafe` 后本地拒绝。这一条要写进 M2/M3 的接线要求。
- `src/BusTester.scala`：不依赖 CPU 的主设备。阶段：初始化（写满整块 RAM，避免任何读碰到未初始化内存）→ 定向（每种 size × 每个合法偏移，写后立即读回）→ 随机（LFSR 的 size/偏移/部分掩码、随机间隔、响应背压）→ 错误区（读写错误从设备，期望 error 且**期望有** TL 事务）→ 非法（掩码 0 / 掩码越界 / 4 字节与 8 字节未对齐 / 未映射写 / 未映射读，期望 error 且**期望零** TL 事务）。逐笔影子存储比对地址/数据/掩码；另外检查响应载荷在等待期间不变、响应不在请求握手当拍出现、无在途时不得有响应、每笔恰好一次 A 握手与一次 D 握手（这是"写提前完成"唯一可靠的检测点）。
- `src/BusTest.scala`：`PhysBridgeHarness` = 测试器 → 桥 → `TLDelayer` → `TLXbar` → {`TLRAM` 0x0–0x3ff, `TLError` 0x3000–0x3fff}，未映射地址取 0x40000。**TileLink 监视器保持开启**，桥若违反 TL 由 rocket-chip 自己的 monitor 抓。每个场景一个 Config，失败时能自报家门。

**结果**（`src/bridge-job.sh` → `evidence/bridge-matrix.txt`，逐例日志与输入哈希在 `evidence/bridge-*/`）：**8/8 符合预期，`BRIDGETB_DONE fails=0`。**

| 场景 | 事务 | 错误 | size 0/1/2/3 | 部分掩码 | 读回 | 错误从设备 | 本地拒绝 | resp 背压拍 | A 通道等待拍 | A/D 握手 | 判定 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| clean（无延迟、无背压） | 966 | **0** | 186/221/235/324 | 251 | 416 | 2 | 6 | 0 | 0 | 960/960 | PASS |
| delay（TLDelayer 0.25、随机间隔、resp 掩码 0x99） | 1366 | **0** | 344/327/275/420 | 346 | 616 | 2 | 6 | 1026 | **441** | 1360/1360 | PASS |
| backpressure（resp 掩码 0x11） | 1366 | **0** | 340/417/223/386 | 331 | 616 | 2 | 6 | 1994 | 133 | 1360/1360 | PASS |

每例的 A/D 握手数 = 事务数 − 6 次本地拒绝，逐笔相等，说明非法请求确实零 TL 事务、合法请求恰好一次往返。

**故障正向对照**（每个必须因**指定理由**失败；超时、编译失败或任何其他原因都不算通过）：

| 故障 | 注入 | 实际首条错误 | 判定 |
|---|---|---|---|
| 1 | 等待 a.ready 期间改写数据 | `TB ERR data=0x…89 expected=0x…76 addr=0x0 size=0 mask=0x01`（50 次） | ok |
| 2 | 丢掉第一笔读响应 | `TB ERR response timeout` | ok |
| 3 | 响应多保持一拍 | `TB ERR response with nothing outstanding`（366 次） | ok |
| 4 | 写在 A 握手时就报完成 | `TB ERR response not backed by exactly one TL D handshake, delta=0 write=1`（312 次） | ok |
| 5 | 吞掉 error 位 | `TB ERR error=0 expected=1 addr=0x3000`（2 次） | ok |

说明：`covReqWait`（CPU↔桥之间请求侧等待）恒为 0 且**不作要求**——测试器是单在途主设备，只在收到响应后才提出下一笔，而桥此时已回到空闲，因此 CPU 侧的 `req.valid && !req.ready` 在本结构下不可能出现。请求侧背压实际发生在 **TL A 通道**（TLDelayer 压低 `a.ready`），用桥内 `aWaits` 计数取证（delay 441 拍、backpressure 133 拍）；桥在这些拍里保持载荷不变，由 TileLink 监视器与故障 1 的对照共同守住。

## 3b. 窄修（Codex `codex-m1-bridge-corrections`，2026-09-14）

Codex 复核提出三项，全部修复并有定向证据。**本节结果来自全部重新生成的 RTL**（runner 每个场景先删除已有 `.v`/`.fir` 再生成，并记录 源码 → RTL → 二进制 三级哈希；`evidence/bridge-*/sources.sha256` 与 `inputs.sha256`）。

**1. 零延迟 manager 互等（真实缺陷，已复现并修复）。** 旧桥只在 `sD`/`sDiscard` 拉高 `d.ready`，而进入 `sD` 又要先等 `a.fire`。接上 `TLRegisterNode(concurrency = 0)` 这种合法的组合 manager（`RegMapper` 在 `concurrency = 0` 时 `back = front`，`a.ready` 经 `front.ready` 依赖 `d.ready`）就死锁。
- 定向证据：`bridge-zerolat-legacybridge`（桥的 `legacyDReady = true` 复刻旧行为）——发出 1 笔请求后 A 通道等待 **4004 拍**、0 笔响应，测试器按自己的超时判失败（`TB ERR response timeout`），不是墙钟挂死。
- 修复：`d.ready := state === sA || sD || sDiscard`。`d.ready` 只是状态的函数，**不依赖 `a.ready`**，因此不会造出组合环；同拍 `a.fire && d.fire` 直接进入响应态并计入 `sameCyc`。
- 通过证据：`bridge-zerolat` 704 笔 / 0 错误 / **同拍完成 694 笔**，`bridge-zerolat-bp` 704 笔 / 0 错误 / 同拍 694 笔 / 响应背压 1084 拍。读写、部分掩码、读回、错误从设备、本地拒绝在零延迟下全部覆盖；CPU 侧响应仍不早于 `req.fire` 的下一拍（桥先锁存请求再发 A，最快是 `req.fire + 2`）。没有用"把后端限成 minLatency ≥ 1"绕过。
- 说明：`TLDelayer(0)` 只是随机延迟为 0，manager 本身仍是 `minLatency = 1`，**不能**用它冒充零延迟；这里用的是真实的 `concurrency = 0` 寄存器设备。

**2. 响应保持 checker 漏检撤销（已修）。** 原来只在"本拍 valid 仍为 1"时比对载荷，上一拍 `valid && !ready`、本拍撤销的情况不会报错。改为从**上一拍的待握手条件**出发：`RegNext(valid && !ready)` ⇒ 本拍必须 `valid` 且载荷与上一拍逐位相同（含最终握手那一拍）。两个新故障对照：
| 故障 | 注入 | 首条错误 |
|---|---|---|
| 6 | 等待中撤销 `resp.valid` 一拍再重发 | `TB ERR response valid withdrawn before the handshake cyc=10` |
| 7 | 等待中改写响应载荷 | `TB ERR response payload changed while waiting cyc=10` |
原 3 正向 / 5 反例全部保留并回归通过。

**3. 覆盖与入口收尾。**
- 新增"已映射但该操作/尺寸不被支持"的定向拒绝：自建 manager `TeachingWideOnlyRAM`（只声明 `supportsGet = TransferSizes(8,8)`，不支持写）。对它的写与 1 字节读都是本地拒绝、零 TL 事务；非法用例从 6 个增至 **8 个**，每个正常场景的 `covIllegal` 现为 8。（注：`maxTransfer < beatBytes` 的 manager 被 diplomacy 拒绝，所以"尺寸受限"只能表达成"不支持小于 8 字节"。）
- `run-sim.sh` 末尾补 `exit $ec`；受控失败例：`MAXCYC=200` 跑 hello.riscv → 模拟器 `*** FAILED *** (timeout…)`、**脚本返回 2**（`evidence/run-sim-failure-case.txt`）。修复前最后一条 `echo` 会把非零退出码吞掉。

**窄修后的完整矩阵**（`evidence/bridge-matrix.txt`，13/13，`BRIDGETB_DONE fails=0`）：

| 场景 | 事务 | 错误 | 本地拒绝 | 同拍 A/D | resp 背压 | A 等待 | 判定 |
|---|---|---|---|---|---|---|---|
| clean | 968 | 0 | 8 | 0 | 0 | 0 | PASS |
| delay | 1368 | 0 | 8 | 0 | 977 | 413 | PASS |
| backpressure | 1368 | 0 | 8 | 0 | 1967 | 143 | PASS |
| zerolat | 704 | 0 | 8 | **694** | 0 | 0 | PASS |
| zerolat-bp | 704 | 0 | 8 | **694** | 1084 | 0 | PASS |
| zerolat-legacybridge（旧桥） | 1 | 1 | 0 | 0 | 0 | **4004** | 按预期死锁 |
| fault1…7 | — | — | — | — | — | — | 各按指定理由失败 |

## 4. 三类状态小结

| 项 | 状态 | 证据 |
|---|---|---|
| **环境（M1-a）** | **通过** | `TestHarness.ZynqConfig.v` sha `d9c2fae9…`；模型 sha `3e0c88da…`；hello.riscv PASS、退出码 0、6861 周期 |
| **桥单元（M1-b）** | **通过（含窄修）** | 5 正常（含 2 个零延迟）+ 1 旧桥死锁对照 + 7 故障 = 13/13；0 scoreboard 错误；§3b |
| **SoC 集成（桥进 SoC）** | **未做** | 本任务未要求；需要 `TeachingBusTestZynq` 配置（接线草案见 §5），M1-c 上板同样未做 |

### 4b. 附加取证：真实 xv6 镜像在该环境中启动（非任务要求）

为验证环境不止能跑裸机 ELF，还试了完整 xv6（HTIF 控制台 + testchipip 块设备 DMA）。**软件适配一项，仅供仿真**：`kinit()` 会从 `end` 一路走到 `PHYSTOP`，128 MB 即约 32000 页，在 Verilator 里占满整个启动时间。在隔离副本 `teaching-cpu-work/xv6-sim/` 中把 `PHYSTOP` 改为 `KERNBASE + 16 MB` 后重建内核与 `fs.img`；16 MB 远大于内核、1 MB 文件系统与 shell 所需。**板上镜像与 `xv6-riscv/` 工作树未改动**，两者哈希不同且分别记录（板上 `kernel` sha `f2bc338e…`；仿真副本 sha `c410c978…`、`fs.img` sha `4691ffea…`）。结果（`evidence/xv6-boot.log`、`xv6-inputs.sha256`、`xv6-cmd.txt`）：

```
xv6 kernel is booting

blkdev: 4000 sectors (1 MB), max request 16 sectors
init: starting sh
```

即内核启动 → 经 testchipip 块设备识别并挂载文件系统 → 运行 `init` → exec `sh`，与板上日志同序。xv6 停在交互提示符不会自行退出，进程按预期在墙钟上限前被结束，因此**没有**退出码可作判据，本条只作附加取证，不计入 M1-a 的通过条件（通过条件是 hello.riscv 的退出码 0）。改 PHYSTOP 前同一模型跑了 6 分钟仍停在第一行，改后约 5 分钟到达 shell。用途/范围/代价：只改一个常量，缩小可用物理内存，不影响启动路径、驱动或特权行为；usertests 等大内存用例不能用这个副本跑。

## 5. 未来 `TeachingBusTestZynq` 配置的接线草案（本轮未构建）

把 M1-b 的测试器（或 M2 的 CPU）作为一个 tile 挂进真实 SoC，只换 Rocket，其余保留：

```scala
class TeachingBusTestTop(implicit p: Parameters) extends BaseSubsystem
    with HasMasterAXI4MemPort with HasSystemErrorSlave with HasPeripheryBootROM
    with HasSyncExtInterrupts with HasNoDebug with HasPeripherySerial with HasPeripheryBlockDevice {
  val bridge = LazyModule(new teaching.ReqRespToTL)      // TLHelper.makeClientNode("teaching-phys", IdRange(0,1))
  sbus.fromPort(Some("teaching"))() := bridge.node        // 与 SerialAdapter 相同的挂法
  override lazy val module = new TeachingBusTestTopModule(this)   // 内部实例化 BusTester 或 CPU，接 bridge.module.io.phys
}
```
- `Top.scala` 的两个 AXI 边界、`rocketchip_wrapper.v`、块设计、约束与比特流流程都不动（M0 §5）。
- 中断：`IntSinkNode` 接 CLINT 的 `msip/mtip` 与 PLIC 的 `meip/seip`；本测试器不用，M2 需要。
- 地址：测试器的 RAM 区改为 DRAM（0x8000_0000 起）、错误区用 SoC 自带的 error slave（0x3000）、未映射区取一个确定不在任何管理者范围内的地址；**注意** `edge.Get/Put` 的 legal 不查地址（§3），务必用 `supportsXxxSafe`。
- 冷启动前提：按 CONTRACT §B，只在 fesvr 启动时、总线空闲时复位；测试器由 TSI 写一个 MMIO 触发或直接自启动，需在 M1-c 明确。

## 6. 未做 / 限制

- **未上板**（M1-c）：未跑 Vivado、未出比特流、未碰板卡与 PS rootfs；原 Rocket 比特流与镜像未改。
- **桥未进 SoC**：只在独立单元测试里验证；DRAM/MMIO 真实地址、TSI 与块设备并发、中断接线都还没接触。
- **未覆盖**：跨 8 字节 beat 的访问（契约禁止，CPU 侧保证）、TL 原子/Hint/Acquire（契约不实现）、多在途、热复位（契约不支持）、非 64 位 beat 的宽度转换。
- **测试器是单在途主设备**：CPU↔桥之间的请求侧背压在本结构下不可达（§3 说明），只在 TL A 通道取证。
- 环境依赖两个容器镜像：`vivado-env:2025.2-sw`（JDK 8，生成 RTL）与主机 conda 的 Verilator 5.022；两者版本都记在 manifest 与各结果目录。
