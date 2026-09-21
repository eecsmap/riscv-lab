# 复现范围

这是成功基线的源码与证据归档，不是“在任意新机器一键重建全部”的承诺。

| 路径 | 首版范围 |
| --- | --- |
| `make check` | 源码导入哈希、已保存 xv6 控制台与内存地图、传输/framing/内存检查器离线测试 |
| `make board-project` | 校验 15 项冻结输入并生成独立 Tcl，无需旧 Scala 工具链 |
| `make xv6 TOOLPREFIX=...` | 调用原 Makefile，显式指定 128 MiB 并强制重建，防止误用默认的 16 MiB 仿真参数；需 RISC-V GCC/binutils、主机 GCC、make、Perl |
| Vivado | 已保存原构建报告与 bitstream；本次仓库整理不重跑综合/实现 |
| Scala → RTL | 保留本地修改后的 Scala 源码与依赖基线，尚未提供独立环境一键重建 |
| ARM host | 保留源文件及已上板静态可执行文件，交叉编译环境尚待便携化 |
| 实板 | 原始冷启动 session 的证据，不是本次新上板测试 |

当前板级路线不是 Chipyard 1.14 的新 Sodor 实验路线。它继承旧 Rocket/PYNQ 集成；不要混用依赖版本。

原 FPGA 构建工具为 Vivado 2025.2.1，具体版本和约束检查见 `evidence/vivado`。

依赖基线（不是“工作树完全干净”的声明）：

| 依赖 | revision |
| --- | --- |
| ucb-bar/fpga-zynq | `726eb97185a74014ef3af059458db56d9ca25755` |
| ucb-bar/rocket-chip | `7cd3352c3b802c3c50cb864aee828c6106414bb3` |
| ucb-bar/testchipip | `8bf7e85ceb8a33ecca4234ab8edfca4206bc665b` |
| eecsmap/xv6-on-rocket-pynq-z1 (板级移植来源) | `1b5c9711a8221c1c2d5762761b228e4f0b5f5097` |
| chisel3 | `a86e38889302662db14b932e4e0d862290c01308` |
| firrtl | `1d4914c396881c66aceb47d5cdd8740ad9a5be26` |
| hardfloat | `45f5ae171a1950389f1b239b46a9e0d16ae0a6f4` |
| riscv-tools | `8ad8d4839acf2cdac0129b8fed8fe12136e77307` |

原工作树包含本地修改及预构建 firrtl.jar，详见 `archive/MANIFEST.md`。这些 pin 本身不足以证明 Scala 路径可重建，因此本版另存经哈希验证的生成 RTL 作为 FPGA 输入。`software/xv6` 是本地移植源码快照，不为它虚构单独上游提交号。每个导入文件的精确身份见根目录 `provenance.json`。

历史文档和导入脚本中的 `/home/engineer/fpga` 路径描述原机器；不要直接运行带该路径的历史构建脚本。受支持的便携入口是根 Makefile。xv6 的旧 `qemu` 目标不能当作该 HTIF/块设备移植版的验证入口。

冻结输入哈希会在有意修改源码时失败：未来实验应明确建立新配置与新输入清单，而不是重写原始验收的身份。探针 ELF 原构建包含随机临时对象名；发布包保留真正上板的旧 ELF，新命名对象的确定性构建不能假称与它们逐字节相同。
