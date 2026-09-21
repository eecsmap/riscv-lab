# 来源与许可证

本仓库没有为全部内容重新授予一种统一许可证。保留各文件原版权说明，第三方组件按各自许可使用：

- `software/xv6/LICENSE`：xv6 原许可证，覆盖其派生移植。
- `licenses/fpga-zynq-LICENSE`：旧平台集成来源。
- `licenses/rocket-chip-LICENSE.*`：Rocket Chip 相关生成逻辑与支持代码的原许可。
- `licenses/riscv-fesvr-LICENSE`：fesvr 来源；预编译主机程序包含相关链接代码。
- 板定义来源为原本地 `board_files/pynq-z1`；其文件声明保留。testchipip 本地快照未发现顶层 LICENSE，本版不据此假设它无版权约束。

自研新增部分尚未选择对外开源许可证。当前以私有仓库存档；若未来公开，先补齐第三方来源/分发许可审核和自研代码的许可证决定。`provenance.json` 将文件定位到本地来源，依赖基线见 `docs/REPRODUCING.md`。历史报告中的作者归属保留，归档不表示重新验收其中每项结论。
