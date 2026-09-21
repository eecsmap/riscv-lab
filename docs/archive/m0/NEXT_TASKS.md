# M0 → M1/M2/M3 任务草案

## M1 总线通路（可与 M2 并行；先仿真后板上）
1. **M1-a 仿真环境判定**：在 `fpga-zynq` 树（JDK 8/sbt 2018，`build-rtl.sh` 已验证可用）验证 `simulation/` + `TestHarness.scala` 能否对 `ZynqFPGAConfig` 生成 Verilator 模型并用 fesvr 跑 `hello.riscv`（阻碍则记录，退而用 rocket-chip 自带 `TLRAM`/`TLFuzzer` 单元级测试）。验收：一次仿真运行日志 + tohost 退出码。
2. **M1-b 适配器 + 事务测试器**：新 Chisel 3.1 模块 `ReqRespToTL`（CONTRACT §B/§C；用本 checkout 的 `TLHelper.makeClientNode`、`edge.Get/Put(…, mask)`、`TLBundleD.error`，REPORT §9）+ 独立事务测试器主设备（不依赖 CPU）：读/写/窄写（wmask 全组合）/顺序/错误（访问 0x3000 error slave → denied）/响应背压/单在途保持；协议监视器沿用 RW 系列（rule1/2/3/4/5/7）。新配置 `TeachingBusTestZynqFPGAConfig`：BaseSubsystem + CLINT/PLIC + BootROM + Serial + BlockDevice + AXI mem + 测试器 tile。验收：仿真全部用例通过、零协议违约、错误路径按契约报错。
3. **M1-c 板上**：用 M1-b 配置出比特流（40 MHz，`run_impl_2025.tcl`），PS 侧用 `pl-probe`/fesvr 经 TSI 触发测试器跑 DDR 读写/窄写/HTIF 控制台回显（本 SoC 无 UART，"UART 测试"= HTIF tohost 路径）；中断：测试器写 CLINT msip/mtimecmp 观察 mtip/msip 到达。验收：板上日志 + 与仿真一致的结果向量。
依赖：M0 冻结 CONTRACT §B；复位前提按 CONTRACT §B（只在启动前、总线空闲时复位；热复位不测不承诺）；租约 `sodor-build-sbt` 不适用，需新租约（fpga-zynq sbt、vivado、board）。

## M2 最小执行核（M-mode 裸机）
1. **M2-a ISA 核**：按 CONTRACT §A 实现 RV64IMAC_Zicsr_Zifencei 多周期核（单口、单在途、C 展开、乘除、AMO RMW、精确同步异常、CSR M 级）。验收：riscv-tests `rv64ui/rv64um/rv64ua/rv64uc`（p 环境）在独立 Verilator 裸机 harness（简单存储 + tohost）全过；自写异常用例（非法/ecall/misaligned/断点/访问故障）。
2. **M2-b 接入 SoC 仿真**：把核放进 M1-b 的 tile 替换测试器，跑 `hello.riscv`（HTIF putchar/exit）；CLINT 定时中断与 msip 测试；**真实 bootrom 启动路径**（复位 0x10040 `_hang` wfi → TSI 加载 → MSIP → 0x10000 → mret → 0x80000000，REPORT §4）。
3. **M2-c 板上**：比特流 + fesvr 加载 hello.riscv → PASS；定时器程序；结果/提交轨迹与仿真比对。
依赖：CONTRACT §A/§B 冻结；M1-b 适配器。

## M3 xv6 兼容与启动
所需功能（缺一不可）：S/U 特权与委派（A2）、sv39 遍历 + 权限/SUM/MXR + A/D 语义（A4）+ sfence.vma、PMP CSR 处理（A3）、AMO（amoswap 至少）、CLINT 定时 → timervec → SSIP 反射、HTIF 控制台（普通访存）、blkdev MMIO + DMA 可见性（无 cache 天然）、fs.img 经 fesvr `+blkdev`、内核 `KERNBASE/PHYSTOP` 与 256 MB DRAM、bootrom 交接为 M-mode。
顺序：仿真（若 M1-a 成功则用 fesvr 仿真 + blkdev 模型）逐层：内核启动打印 → 首个用户进程 `init` → `sh` → 选定测试（`ls`、`echo`、`cat README`）→ `usertests`（分状态记录：快测/慢测）；然后板上同序列。软件适配候选（只在证据要求时用）：`-march` 去 C（A1）、start.c 的 pmp 写（A3）、timervec 委派差异（A2）。
