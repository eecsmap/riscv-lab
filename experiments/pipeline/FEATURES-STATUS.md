# 流水线特性演进（实现状态记录）

`docs/FEATURES.md`（特性演进与配置路线）在 main 上；本分支 `pipe-single` 从 `mc-v1-dual` 分出，按约束不改 main。
下表是流水线线路的状态行，合并时并入该文件的“标签/提交”表与“当前配置能力”表。只记录实现与仿真状态；
P3a 的离线面积/时序结果见 `experiments/pipeline/p3/REPORT.md`；没有任何上板结论。

状态级别：可表达 < 已实现 < 仿真通过 < 上板通过。

| 提交 | 累计状态 | 相邻阶段重点 | 级别 |
|---|---|---|---|
| `e327462` | PIPE-P0 契约、测试计划、可执行控制模型 | 精确异常、冲刷、单请求在途约束 | 文档 |
| `53b1aac`（P1 验收锚点） | 独立 RV64I 五级流水核 `tcpu_core_pipe` | ALU 命中 II=1；差分、中断对齐、故障旋钮 | 核级仿真通过 |
| `ed0d79d` | + M、+ C（Bare）；非缓存取指按 16 位 parcel | 共享 mul/div 与 C 译码器不改 | 核级仿真通过（P2a 验收） |
| `affc3a3` | + M/S/U 特权（共享 CSR 单元） | 委托、xRET、跨特权中断 | 核级仿真通过 |
| `f5c2add` | + Sv39：流水线自有双查找 8 项 TLB，共享页表遍历器经包装器 | 预取遍历可抢占、PTE 事务归属元数据 | 核级仿真通过 |
| `35c05eb` | + A：LR/SC/AMO 经现有原子后端 | 只由最老指令发出、响应后退休 | 核级仿真通过 |
| `79f21e4` 及其后 | SoC 显式选择：`RD2Params.coreImpl = "pipeline"`，BlackBox `desiredName = tcpu_core_pipe`，源清单 `rtl/cpu/pipeline/SOURCES.pipe` | 旧配置生成 RTL 归一化后逐字相同；pipeline × 2 拒绝 | 可生成 |
| `0b225e0`/`8e099a5`（P2b 验收） | 单核 xv6 在 RD2 仿真器上运行：`m4smoke`、`perf-short` 均通过 `m3_check.py --n1`；SoC 退休关联门禁 | 与多周期核同内核/磁盘镜像对照 | SoC 仿真通过；未上板 |
| P3a（`RD2PipeBoardConfig`） | 单流水核 PYNQ-Z1 板级形态离线综合/布局布线，40 MHz 时序收敛，生成 bitstream（未烧写） | 与单多周期 cache、双多周期构建对照资源与时序 | 离线布线通过；未上板 |

当前配置能力的变化（对应 `docs/FEATURES.md` “核实现”一行）：

| 维度 | 代码现状 | 验证/限制 |
|---|---|---|
| 核实现 | `RD2Params.coreImpl` 接受 `multicycle`、`pipeline` | `pipeline` 只在原子（V2）路径、`numCores = 1`；其它组合在生成时拒绝并给出取值 |
| 流水线扩展 | `PIPE_EXT_M/C/SU`、`MISA_A`，SoC 选择 pipeline 时全开 | TLB 固定 8 项（与参考核相同），I-cache 1 KiB；无 D-cache |

未实现：双流水线核（P4）、板级构建与测量（P3 之后另行授权）、统一配置框架。
