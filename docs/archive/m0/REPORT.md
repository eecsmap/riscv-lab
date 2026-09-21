# M0：现有 Rocket/xv6 板级体系替换契约审计（Claude，2026-09-14）

任务书 `.coord/proposals/codex-m0-rocket-replacement-contract.md`。只读审计；证据在 `evidence/`（索引 `evidence/README.md`，两个可重跑采集脚本）。本轮未上板、未重建、未改任何源码。

## 0. 结论先行

1. **可运行基线是确定的、可复现的**：`fpga-zynq@726eb97`（rocket-chip `7cd3352c3` / testchipip `8bf7e85` / Chisel 3.1.0-RC2 / priv-1.7 riscv-tools）+ 未跟踪的板端口 `fpga-zynq/pynqz1/`（来自 `xv6-on-rocket-pynq-z1@1b5c971` 的 `board/`）；生成 RTL `pynqz1/src/verilog/Top.ZynqFPGAConfig.v`（sha `781b7117…`，2026-09-08 生成）；比特流 `bitstream-impl1-validated.bit`（Vivado 2025.2.1，40 MHz，WNS +1.542 ns）；硬件日志 `xv6-2025.2.1-hardware-run.log`（2026-09-08）证明 hello.riscv PASS、xv6 启动到 shell 并 `ls`；xv6 README 记录 usertests 64 项全过（**日志证明曾运行；本轮没有重新上板验证**）。
2. **软件契约：RV64、S/U 特权、sv39、C 扩展被实际使用、A 只有 amoswap、M 少量、F/D 完全未用**（内核 8369 条指令中压缩 5186、M 7、A 4、Zicsr 74、fence 7、fence.i 1、sfence.vma 6；所有 22 个用户 ELF 中 F/D 指令数为 0，A 为 0）。ELF 标 lp64d ABI 但无浮点指令。CSR 需求见 §2 表。
3. **平台契约：核心复位向量是 bootrom 的 `_hang` = **0x10040**（不是 ROM 基址 0x10000），在 ROM 里等 MSIP，经 M-trap 到 0x10000 再 `mret` 落到 0x80000000 的 M-mode；CLINT 0x2000000（mtime/mtimecmp/msip）、块设备 0x10015000（testchipip，DMA 主设备）、无 UART（控制台走 HTIF tohost/fromhost，由 PS 侧 fesvr-zynq 经 TSI 轮询）、PLIC 0xC000000 存在但无中断源。** 除 CPU 外还有两个总线主设备（TSI SerialAdapter、BlockDevice 两个 tracker），它们直接写 DRAM。
4. **真实替换位置在 `FPGAZynqTop`（`fpga-zynq/common/src/main/scala/Top.scala`）内部的 Rocket tile**：`Top` 模块的两个 AXI 边界（`io.mem_axi` 64 位 AXI4 → PS HP0；`io.ps_axi_slave` ← PS GP0 0x43C00000）、`rocketchip_wrapper.v`、块设计、时钟/复位与比特流流程都不用动。新 CPU 以一个 **TL-UL 客户端**（像 SerialAdapter 那样 `TLHelper.makeClientNode`）挂到同一 TileLink 总线，保留 bootrom/CLINT/PLIC/Serial/BlockDevice/AXI4 mem port。单时钟域（40 MHz `ext_clk_in`，PS 两侧 AXI 同钟），PL 内无 CDC；复位 = `!FCLK_RESET0_N || !mmcm_locked`，CPU 另受 ZynqAdapter `sys_reset`（fesvr 加载完成后释放）。
5. **推荐路线：新写顺序多周期 RV64 核（不改 Sodor）**。Sodor 是 RV32、无 S/U、无 VM、无 A/C/M/FPU、I/D 双口结构，差距覆盖数据通路宽度、译码、特权、MMU 全部四类；改造成本高于按冻结契约新写一个单口 FSM 核。核心最小集：RV64IMAC_Zicsr_Zifencei（F/D 不需要；C 可通过重编译内核+用户程序去掉，但那是软件适配，默认保留 C）+ M/S/U + sv39 串行页表遍历（首版无 TLB）+ CLINT 定时/软件中断 + 精确同步异常。
6. **主要风险**：(a) 契约中若干值靠 Rocket 行为隐性决定（medeleg 可委派集 0xB109、PTE A/D 由软件置位、misaligned 陷入、PMP CSR 存在），新核必须显式选择并写进 CONTRACT；(b) 时间基准不一致：RTC 分频按"总线 100 MHz/1 MHz"生成，40 MHz 实钟下 mtime≈400 kHz，而 xv6 README 注释写"25 MHz 实测 250 kHz"——需上板核对；(c) 块设备 DMA 要求 64 字节对齐目标，xv6 已适配；(d) 2025.2.1 时序余量比 2024.1 少 1.85 ns，新核必须比 Rocket 简单才不会更糟；(e) 无仿真级 xv6 环境证据（fpga-zynq `simulation/` 未验证），M1/M2 要先建。

## 1. 工程基线（`evidence/repos.txt`、`generated-rtl.txt`、`ps-side-and-build.txt`）

| 项 | 值 | 证据 |
|---|---|---|
| 板级顶层仓库 | `fpga-zynq` HEAD `726eb97`，脏项只有子模块指针与未跟踪 `pynqz1/` | repos.txt |
| rocket-chip | `7cd3352c3`（子模块 chisel3 `a86e388` = v3.1.0-RC2、firrtl `1d4914c`、hardfloat、riscv-tools `8ad8d48` priv-1.7），脏项为子模块指针 | repos.txt |
| testchipip | `8bf7e85`（未跟踪 `project/`） | repos.txt |
| PS 软件 | linux-xlnx `6fd59fe`（v2014.2 系）、u-boot-xlnx `f634657`（v2014.3）、busybox 1.36.1；补丁在 `xv6-on-rocket-pynq-z1/patches/` | repos.txt, ps-side-and-build.txt |
| 板端口 | `xv6-on-rocket-pynq-z1@1b5c971`（干净）→ `fpga-zynq/pynqz1/`：`src/verilog/{rocketchip_wrapper.v,clocking.vh,plusarg_reader.v,Top.ZynqFPGAConfig.v}`、`src/tcl/pynqz1_bd.tcl`、`build_2025.tcl`、`run_impl_2025.tcl` 等 | board-rtl.txt |
| Rocket 配置 | `ZynqFPGAConfig` = `WithoutTLMonitors ++ WithZynqAdapter ++ WithBootROM(testchipip/bootrom/bootrom.rv64.img) ++ rocket-chip DefaultConfig`（1 个 BigCore：XLen 64、useVM、FPU、mulDiv、useAtomics、useCompressed、nPMPs 8、nBreakpoints 1、sv39；ExtMem idBits 改 6；BlockDevice nTrackers 2） | fpga-zynq-scala.txt, rocket-config-grep.txt |
| 生成 RTL | `Top.ZynqFPGAConfig.v` 202,482 行，sha `781b7117…`，由 `scripts/build-rtl.sh`（JDK 8 + sbt，firrtl 先放 `rocket-chip/lib`）生成；可行性报告记录本机重生成与参考机逐字节相同 | generated-rtl.txt, xv6-bitstream-feasibility.md |
| 比特流 | `bitstream-impl1-validated.bit` 4,045,696 B，sha `34270f88…`；Vivado 2025.2.1 `run_impl_2025.tcl`，WNS +1.542 ns @40 MHz，0 失败端点，LUT 57.6%、Slice 72.4% | 可行性报告 §结果 |
| 时钟 | `clocking.vh`: ZYNQ_CLK_PERIOD 8.0（125 MHz）× RC_CLK_MULT 8 ÷ RC_CLK_DIVIDE 25 = **40 MHz**；README 中 "25 MHz" 为上游文字 | board-rtl.txt |
| 工具链（RISC-V） | 内核与用户 ELF `.comment` = GCC 13.2.0（Ubuntu 13.2.0-11ubuntu1+12，vivado-env:2025.2-sw 镜像）；`-march=rv64gc -mcmodel=medany`，未指定 -mabi（默认 lp64d） | elf-headers.txt, xv6-port.txt |
| 最近成功记录 | `xv6-2025.2.1-hardware-run.log` 2026-09-08 07:41（hello PASS + xv6 boot + ls）；`xv6-selfbuilt-hardware-run.log` 同类 | 本地日志 |
| 可运行镜像 | xv6 内核 `xv6-riscv/kernel/kernel` sha `f2bc338e…`、`fs.img` sha `ea947185…`；PS rootfs 副本 `rd-*/root/{xv6-kernel,fs.img}` | elf-headers.txt |
| 最小复现路径 | `xv6-on-rocket-pynq-z1/scripts/{build-rtl,build-fsbl,build-linux,build-userland,build-rootfs,build-boot}.sh` + `fpga-zynq/pynqz1/run_impl_2025.tcl`；容器 `~/vivado-docker`（vivado-env:2025.2 / 2025.2-sw） | ps-side-and-build.txt, 记忆 |

## 2. 软件架构契约（`evidence/isa-usage.txt`、`isa-details.txt`、`elf-headers.txt`、`xv6-port.txt`）

| 需求 | 现状/证据 | 新核 |
|---|---|---|
| XLEN | ELF64；内核入口 0x80000000；`-march=rv64gc` | RV64 |
| 基础整数 | RV64I 全部（ld/sd、w 后缀） | 必需 |
| C | 内核 62% 指令为 16 位；所有用户 ELF 同样 | **必需**（或软件适配：全部以 `-march=rv64ima_zicsr_zifencei -mabi=lp64` 重编译内核+用户，代价：重建 fs.img、体积↑、与上游 diff↑） |
| M | 内核 7、用户 2–20 条 mul/div/rem | 必需（多周期实现即可） |
| A | 内核仅 `amoswap.w`×3 + `amoswap.w.aq`×1（spinlock）；用户 0 | 必需 amoswap（建议实现完整 AMO/LR/SC 以免 gcc 变化），可为 CPU 内 RMW（§3） |
| F/D | 0 条（内核与全部用户）；ABI 标 lp64d 只影响调用约定，不产生指令 | 不需要；misa 不置 F/D；若程序含 FP 指令则非法指令陷入 |
| Zicsr/Zifencei | csr* 74 条；fence.i 1 条；fence 7 条；sfence.vma 6 条 | 必需（fence/fence.i 在无 cache 核上为 NOP，但必须合法译码；sfence.vma 需使 TLB/遍历缓存失效） |
| 特权级 | 入口 M（bootrom `mret` 不改 MPP）；内核 `start.c` M→S；用户 U；`ecall` 22 处/用户 ELF | M/S/U 三级 |
| CSR（内核实际引用） | mstatus medeleg mideleg mie mepc mcause mtval mtvec mscratch mhartid **pmpaddr0 pmpcfg0**；sstatus sie sip stvec sepc scause stval sscratch **satp** | 全部必需；pmp* 至少可写不陷（见 CONTRACT 决策） |
| 中断 | 定时：M-mode `timervec` 由 CLINT mtimecmp 触发，重设 mtimecmp 后置 SSIP 反射给 S（`SIE_SSIE`）；无外部中断（HTIF 轮询、blkdev 轮询）；`mideleg` 委派软件中断 | mtip/msip/ssip 必需；meip/seip 接线保留 |
| 异常 | ecall(U)、page fault（12/13/15）、非法指令、断点；Rocket `medeleg` 可委派掩码 0xB109（bit 0,3,8,12,13,15），非法指令**不**委派→port 的 timervec 处理非定时器 M-trap | 精确同步异常；委派集为 CONTRACT 决策 |
| MMU | satp sv39（3 级，4 KB 页）；`PTE_A|PTE_D` 由软件置位（Rocket PTW 不写 A/D，缺失即 page fault）；SUM/MXR 未见使用（待细查 sstatus 写值） | sv39 遍历必需；A/D 处理为决策 |
| misaligned | Rocket 陷入（causes 4/6）；xv6 无处理 | 陷入即可 |
| 控制台 | `tohost/fromhost` 64 字节对齐全局，自旋等 host 清零；只有读有回复 | 普通 64 位 ld/sd 到 DRAM，对 TSI 读可见（无 cache 即满足） |
| 磁盘 | `blkdev.c`：MMIO 0x10015000 寄存器 + DMA 到内核缓冲（64 字节对齐） | MMIO 8 字节访问顺序完成 |
| 定时器 | `CLINT_MTIMECMP = CLINT_MTIME + interval`（start.c），mtime 频率见风险 (b) | 64 位 MMIO 读写 |

## 3. MMU 与原子（`evidence/details-2.txt`、`isa-details.txt`）

- sv39、3 级、PA 在本 SoC 内 32 位足够（TL 地址位 32：`SerialAdapter` `edge.bundle.addressBits`；AXI 地址 32 位，DRAM 0x8000_0000–0x8FFF_FFFF）。PTE PPN 超出 32 位物理空间 → 访问故障。
- 权限：U/S 页权限检查、R/W/X、SUM/MXR 位需实现（内核 copyin/copyout 用 `walkaddr` 软件查表，不依赖 SUM——待用 sstatus 写值细查，列为未知）。
- A/D：软件置位；Rocket 语义"缺 A（或写时缺 D）→ page fault"。新核最简：同样陷入，不写 PTE。
- 串行遍历足够（xv6 usertests 在 Rocket 上 25 分钟主要受 DRAM 分配限制）；无 TLB 时每次访存 3 次额外 DRAM 读，正确性优先，首版可无 TLB，M3 视需要加 1–4 项微 TLB。
- 原子：内核 spinlock 用 `amoswap.w(.aq)`；对象在内核私有内存，DMA（BlockDevice 写缓冲）与 TSI（读写 tohost/fromhost、加载 ELF）**不触碰锁字**。因此 AMO 可在 CPU 内以"读—改—写、期间不发其他请求"实现，总线上是两笔 TL-UL 事务；**这不是总线原子**，若将来有第二个 CPU 或 DMA 与锁同址，需改用 TL 原子操作（rocket-chip 在 AXI 侧无法原子，需 `TLAtomicAutomata`）。竞争边界写入 CONTRACT。
- LR/SC：内核未用；实现为 CPU 内保留位（单核足够）。

## 4. 启动与平台（`evidence/bootrom.txt`、`details-2.txt`、`soc-devices.txt`、`wrapper.txt`）

- **复位向量 = 0x10040**：`BootROM.scala:18-20` `address = 0x10000, hang = 0x10040`，`:70` `resetVector = params.hang`，`:81` `global_reset_vector := resetVector`；生成 RTL `Top.ZynqFPGAConfig.v:75466`（`module Frontend`）`s2_pc <= 40'h10040`。ROM 布局 `testchipip/bootrom/linker.ld`：`.text.start` 在 ROM_BASE、`.text.hang` 在 ROM_BASE+0x40（`evidence/details-4-rom.txt` 反汇编：0x10040 `auipc/addi → mtvec=0x10000; mie=8(MSIE); mideleg=0; csrs mstatus,8(MIE); wfi; j`）。
- **真实启动顺序**（`evidence/details-4-boot-chain.txt`、`details-6-start.txt`）：
  1. `fesvr_zynq.cc main`：构造 `tsi_t`（创建 host 协程，尚不运行）→ 构造 `zynq_driver_t`：`zynq_driver.cc:46` **`write(SYSTEM_RESET,1); write(SYSTEM_RESET,0)`** → target 立刻出复位，核心从 0x10040 执行，进入 `wfi` 循环等 MSIP（此时 DRAM 里还没有程序）。
  2. `driver->poll()` → `tsi.tick()`（`tsi.cc:108`）→ 切到 host 协程 → `htif_t::run()`（`htif.cc:156` 调 `start()`）→ `load_program()`（`htif.cc:85`：TSI `write_chunk` 把 ELF 段写入 DRAM，记录 `tohost/fromhost` 符号地址）→ `tsi_t::reset()`（`tsi.cc:29-35`）= **TSI 写 1 到 `MSIP_BASE 0x2000000`**。
  3. 核心在 M-mode 取软件中断 → `mtvec=0x10000` `_start` → hart0：向 msip[1..] 写 1 直到读回 0（单核时 0x2000004 读 0，一次退出）→ `0x10074` 清 msip[0] → `mepc=0x80000000`、清 `MPIE`、`mret`。MPP=M 是因为陷入发生在 M-mode，不是“未改所以是 M”。
  4. host 循环用 TSI `read_chunk/write_chunk` 轮询 `tohost/fromhost`（控制台、退出码）、服务块设备 FIFO。
  对新核的要求：复位 PC=0x10040、`mhartid=0`、`mtvec/mie/mideleg/mstatus/mepc` 可写、M-mode 软件中断可被取（`mip.MSIP` 来自 CLINT）、`wfi`（可为 NOP，但取中断必须仍然发生）、`mret`。
- 内存映射：DRAM 0x8000_0000 + 256 MB（AXI 到 PS HP0，地址 `{4'd1, a[27:0]}` → Zynq 0x1000_0000）；bootrom 0x10000；CLINT 0x0200_0000；PLIC 0x0C00_0000（2 个顶层中断，`tieOffInterrupts`）；error slave 0x3000；blkdev 0x1001_5000；无 UART。xv6 PHYSTOP=128 MB。
- 时间源：CLINT mtime 由 `HasRTCModuleImp` 用 `PeripheryBusKey.frequency`（默认 100 MHz）/`DTSTimebase`（1 MHz）= 每 100 拍一 tick；实钟 40 MHz → 400 kHz（xv6 README 注释"25 MHz 实测 250 kHz"与 clocking.vh 不一致，需上板测）。
- 中断：无外部源；CLINT mtip/msip 直连 tile。
- 磁盘：`fs.img` 是 PS 侧文件，`+blkdev=fs.img`；testchipip BlockDevice：前端 MMIO（addr/offset/len/write/tag，读 `allocate` 触发；complete/ncomplete/nsectors/max_req_len）+ 两个 tracker 以 64 字节 Put/Get DMA。
- debug/JTAG：`HasNoDebug`；无 Debug Module；JTAG 文档针对 PS。
- 复位/时钟域：单域 40 MHz；PS AXI 两侧同钟；`reset = !FCLK_RESET0_N || !mmcm_locked`；目标复位 = ZynqAdapter `sys_reset`（`Top.scala` `target.reset := adapter.io.sys_reset`，只复位 target 子系统；**PS 侧 DDR 与 AXI 互连不随之清空**，复位时若有在途 AXI 事务其后果未定义——现有流程只在 fesvr 启动时、任何 TSI/DMA 流量之前复位一次）。

## 5. 真实替换位置（`evidence/fpga-zynq-scala.txt`、`wrapper.txt`）

| 组件 | 文件/符号 | 处置 |
|---|---|---|
| Rocket tile（core、I$/D$、PTW、FPU、BTB） | `FPGAZynqTop extends RocketSubsystem`（`Top.scala:38`）→ rocket-chip `HasRocketTiles` | **替换**：自定义子系统 `TeachingZynqTop extends BaseSubsystem with HasPeripheryCLINT/PLIC + 自研 tile（TL-UL client）` |
| BroadcastHub / 内存总线 / `HasMasterAXI4MemPort` | rocket-chip subsystem | 保留（无 cache 客户端不需要一致性，但 hub 存在无害） |
| BootROM / CLINT / PLIC / ErrorSlave | `HasPeripheryBootROM`、CLINT/PLIC traits | 保留 |
| SerialAdapter（TSI）/ BlockDevice | `HasPeripherySerial`、`HasPeripheryBlockDevice`（testchipip） | 保留 |
| ZynqAdapter（PS 寄存器、sys_reset、FIFO） | `ZynqAdapter.scala` | 保留 |
| `Top` 模块边界（`io.mem_axi`、`io.ps_axi_slave`） | `Top.scala` | 保留端口，内部 `FPGAZynqTop` 换成新子系统 |
| rocketchip_wrapper.v / bd / 约束 / 比特流脚本 | `pynqz1/` | 不动 |
| 中断 sink | tile `intNode`（CLINT mtip/msip、PLIC meip/seip） | 新 tile 提供 |
| 暂不能判定 | `simulation/`（fpga-zynq 自带 Verilator 环境）是否可跑本配置；M1 先验 | — |

新 tile 最小接入：`LazyModule` 含 `TLHelper.makeClientNode(name="teaching-cpu", sourceId=IdRange(0,1))` 挂 `sbus`（与 SerialAdapter 同法），中断 `IntSinkNode`，模块内实例化 CPU（Verilog BlackBox 或 Chisel 3.1）+ req/resp→TL-UL 适配器。

## 6. 最小 req/resp 契约草案 → `CONTRACT.md`

## 7. 核心实现路线

| 维度 | Sodor（3 级/1 级） | 需要 | 差距 |
|---|---|---|---|
| XLEN | 32 | 64 | 数据通路/regfile/ALU/ld-sd 全部改宽 |
| ISA | RV32I + Zicsr（无 C/M/A/FPU） | RV64IMAC_Zicsr_Zifencei | 译码器、乘除、AMO、C 展开全新 |
| 特权 | M only（useSupervisor/useUser false） | M/S/U + 委派 | CSR 文件参数、trap 路径、sret |
| MMU | 无（useVM false） | sv39 遍历 + 权限/故障 | 全新，且 Sodor 取指/访存路径无翻译挂点 |
| 存储口 | I/D 双口（单端口配置靠仲裁） | 单口串行（取指/数据/PTW） | 结构重排 |
| 中断 | 上游缺陷已由 recordInterrupt 修（RW9） | 精确 | 可借鉴 |

结论：Sodor 可作**测试资产与经验来源**（协议监视器、保持型请求、中断安全窗口、RW 系列门禁），不作为新核基础。新核为顺序多周期 FSM：fetch(可能两次以处理跨 8 字节的 32 位指令) → decode(C 展开) → execute → mem(含 PTW 子状态机与 AMO RMW) → writeback/trap，一次一条指令，单在途；先 M-mode 裸机（M2），再 S/U + sv39（M3）。实现语言为 Codex 裁定项：Verilog（工具无关、可直接进 Vivado 与 Verilator）+ Chisel 3.1 BlackBox 包装，或全 Chisel 3.1（受 2018 工具链约束）。

## 8. 未知与最小补证
- mtime 实际频率（40 MHz 下 400 kHz 推算 vs 注释 250 kHz）：`start.c` 用 `interval = 25000`（注释 "~10 Hz at 250 kHz"），若实为 400 kHz 则 tick 为 16 Hz，功能不受影响但说明该常量未随 40 MHz 更新；上板用 mtime 对墙钟计时即可定。
- sstatus SUM/MXR 是否被设置：细查 start.c/trap.c 写 sstatus 的常量（本轮只统计了 12 处引用）。
- `fpga-zynq/simulation/` 能否对本配置做 Verilator 仿真（fesvr + blkdev 模型）：M1 第一步验证。
- 热复位（运行中再次 `sys_reset`）：现有软件不使用；PS DDR 保留旧内容、AXI 在途事务无保护——列为不支持，不称已安全。

## 9. 本地 TileLink API 对照（本 checkout rocket-chip `7cd3352c3`，`evidence/details-4-tl-mmu.txt`）

| 项 | 本 checkout | 新版（Chipyard 1.14 树，仅作对照） |
|---|---|---|
| D 通道字段 | `opcode, param, size, source, sink, data, error`（`tilelink/Bundles.scala:165-178`）——**只有 `error`，没有 `denied/corrupt`** | `denied` + `corrupt` |
| A 通道字段 | `opcode, param, size, source, address, mask, data`（`:120-133`） | 同 |
| `size` | log2(字节数)，`sizeBits` 由 TransferSizes 决定 | 同 |
| 客户端节点 | `TLHelper.makeClientNode(name, sourceId)`（testchipip `Util.scala:125`）→ `TLClientNode(Seq(TLClientPortParameters(Seq(TLClientParameters(name, sourceId, supports*)))))` | `TLClientNode(Seq(TLMasterPortParameters.v1(...)))` |
| 边助手 | `edge.Get(fromSource, toAddress, lgSize)`、`edge.Put(fromSource, toAddress, lgSize, data)`、`edge.Put(..., data, mask)`（PutPartial）、`edge.Arithmetic/Logical(..., atomic)`（`tilelink/Edges.scala:368-424`），返回 `(legal, bundle)` | 同名，参数相近 |
| 消息码 | `TLMessages`：Get=4、PutFull=0、PutPartial=1、AccessAck=0、AccessAckData=1 | 同 |
| 用法样本 | `SerialAdapter.scala:71-76`（Put 带 mask、Get 带 rsize）、`BlockDevice.scala:135-139` | — |

## 10. Rocket 在本 checkout 的 MMU 行为（新核规格的对照，`evidence/details-5.txt`、`details-4-tl-mmu.txt`）
- 非规范 VA（sv39 位 63:39 ≠ 位 38）：`TLB.scala:189` `bad_va` → page fault。
- 访存不对齐：`TLB.scala:188,202-203` → misaligned load/store 异常（causes 4/6）。
- 叶子 PTE：`PTW.scala:63` `leaf = v && (r || (x && !w)) && a`；写需 `d`（`:68`）——缺 A/D 不是叶子 → page fault；`w && !r` 保留编码 → 非叶子非表 → page fault。
- 超级页 PPN 低位非零：`PTW.scala:98-102` 置 `v := false` → page fault（与规范一致）。
- PPN 超出物理位宽：`:103` `invalid_paddr` → `resp_ae`（**访问故障**，`:262`）。
- PTE 取回本身的总线错误：`:268` `resp_ae := true` → 访问故障。
- Rocket 在本配置下 `misa` 是否可写、xv6 是否依赖（`misaWritable=true` 默认）：不依赖（内核无 misa 引用）。
