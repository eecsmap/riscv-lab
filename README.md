# riscv-lab

用于自学 RISC-V 微架构、FPGA SoC 与操作系统的实验仓库。

当前里程碑：自研多周期 RV64 CPU 替换 Rocket，在 **PYNQ-Z1 / 40 MHz / PS DDR** 上启动 xv6，完成 `echo`、`ls`、`cat` 和管道命令。2026-09-21 的原始记录及独立复核见 [验收记录](evidence/xv6-board-run-3/CODEX_MILESTONE_ACCEPTANCE.md)。这不是教学产品，也不是完整 ISA 合规认证。

## 当前设计

CPU 使用单口指令/数据访问、独立的请求和响应 ready/valid 通道；写地址和写数据属于同一个请求。请求未握手时保持 valid 和负载，响应背压时保持响应。CPU 是顺序多周期实现，不依赖总线固定延迟。M/C、S/U、Sv39 和原子操作已加入；Sv39 使用串行页表遍历，无 TLB，无指令/数据缓存。原子操作由 CPU 与 SoC 后端共同实现。

路径：CPU → req/resp 桥 → TileLink → AXI4 → Zynq PS DDR。ARM 端 fesvr 提供控制、控制台和文件支持的块设备；不是自研 SD 控制器。内部 `teaching`、`tcpu` 等历史标识保留，以免整理仓库改变已验证硬件。

## 目录

| 路径 | 内容 |
| --- | --- |
| `rtl/cpu` | 当前 CPU Verilog |
| `soc/scala` | 桥、原子后端、复位域、SoC 集成源码快照 |
| `boards/pynq-z1` | 已验证构建的冻结 RTL、约束、PS 配置、输入哈希 |
| `host/csrc` | ARM 主机程序源码 |
| `software/xv6`、`software/probes` | xv6 移植与裸机探针源码 |
| `tests/cpu`、`tools` | 测试源码、离线检查及板端运行工具 |
| `evidence` | 实板验收、原始日志、Vivado 报告 |
| `docs/archive` | 历史设计权衡与阶段报告，不是当前操作指南 |
| `provenance.json` | 导入来源与文件 SHA-256 |

## 开始

```sh
make check                      # Python 3 + bash；离线，无硬件访问
make board-project              # 生成独立 Vivado 项目 Tcl，不运行 Vivado
make xv6 TOOLPREFIX=/path/to/riscv64-unknown-elf-
```

[复现范围与依赖](docs/REPRODUCING.md) · [安全运行边界](docs/BOARD.md) · [来源与许可证](LICENSES.md)。预编译成功基线单独放在私有 GitHub Release，不进入源码 Git 历史。

## 结果与边界

该次实板启动 shell 用时 86.2 秒，四项命令在 277.9 秒完成。布局布线结果为 LUT 13,777、FF 5,884、BRAM 0、DSP 0，WNS +0.779 ns、WHS +0.024 ns。

后续性能探针报告的 ALU 循环 CPI 为 bare 40.33、Sv39 大页 82.63、4 KiB 页 161.26。这是 **Claude 提交、尚未独立验收的微基准结果**，不是整个 xv6 的平均 CPI；没有同负载 Rocket 对照。原报告保留在历史资料中，不采纳其把循环结果外推成 xv6 平均性能的表述。

未宣称：完整 usertests、完整 ISA 合规、长期稳定性、全新环境端到端构建复现。**仅允许冷启动流程，不支持安全热重载 PL。** 下一步优先补齐便携构建与可重复性能对照，而不是改变这个冻结基线。
