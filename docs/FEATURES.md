# 特性演进与配置路线

## 查看特性如何加入

固定标签用于回看已验收实验；开发分支用于继续实现。保留原始提交、修正和合并，不 squash 成一个难以追踪的大提交，不移动历史标签。

| 标签/提交 | 累计状态 | 相邻阶段重点 |
|---|---|---|
| `v0.1.0-xv6-boot` | 自研多周期核上板启动 xv6 | 初始完整系统 |
| `ips-v1-baseline` | 冻结微基准基线 | 测量身份与规则 |
| `ips-v1-fetch32` | 对齐时32位取指快路径 | 减少parcel取指往返 |
| `ips-v1-tlb` | 加入TLB | 避免重复页表遍历 |
| `ips-v1-icache` | 加入指令缓存 | 减少外部取指访问 |
| `bcf403e` | TeachingHart封装 | 为可替换核与多核铺路 |
| `33c4864` | 多hart原子后端 | 预约归属、写失效、同时清除计数 |
| `b147091` | 真实双核 | 启动、中断、仲裁、全局排空复位 |
| `565d33f` | 双核板级配置 | 40MHz实现 |
| `mc-v1-dual` | 双核xv6与测评资产归档 | 软件适配、原始记录、可复现构建 |

IPS标签代表累计配置，不是每个特性的独立补丁；部分阶段曾在平行分支开发。
`git diff A B`比较两个已验收树，比假设所有标签构成直线历史更可靠。

```sh
git log --graph --decorate --oneline --all
git diff ips-v1-baseline ips-v1-fetch32 -- rtl soc
git diff ips-v1-fetch32 ips-v1-tlb -- rtl soc
git diff ips-v1-tlb ips-v1-icache -- rtl soc
git diff ips-v1-icache mc-v1-dual -- rtl soc software/xv6
git log --oneline ips-v1-icache..mc-v1-dual -- rtl soc
```

测量及重建入口见 [双核归档](../experiments/multicore/README.md)。早期B0/E1报告保留失败、勘误与恢复记录；它们不是推荐部署25MHz配置的声明。

## 当前配置能力：不要混同参数、接线与已验证组合

| 维度 | 代码现状 | 验证/限制 |
|---|---|---|
| 核实现 | `RD2Params.coreImpl` | 当前只接受`multicycle`；流水线尚未实现 |
| 核数 | 原子RD2路径`numCores`、`TeachingHart` | 1/2核；0/4被拒绝，非原子历史路径仍为单核 |
| TLB | `tcpu_core.TLB_ENTRIES`，0关闭 | 有RTL参数及历史测试；不等于任意SoC配置已接通或验收 |
| I-cache | `tcpu_core.ICACHE_BYTES`，0关闭 | 当前里程碑每核1KiB；同上 |
| fetch32 | 历史标签保留基线/优化对照 | 当前核内实现，不承诺统一开关 |
| 数据缓存 | 无 | 不列为本阶段可选项 |
| 软件 | 部署/测评/验证内核 | `TEACHING_VALIDATION`隔离pin/getcpu；mtime为只读测评调用 |

当前双核板上已验收组合：multicycle × 2、fetch32、每核8项TLB/1KiB I-cache、无D-cache、共享串行原子后端。保持每hart单物理请求在途、不可撤销ready/valid契约。

## 流水线完成后再完善的方向（不是本次实现承诺）

参考Chipyard的配置组合思路，而不要求照搬其实现：

- 核实现、核数、取指策略、TLB/I-cache容量、后端内存分别表达；核型不绑定核数。
- 由统一配置对象贯通RTL参数、SoC接线、仿真和板级生成；少用复制源码维护变体。
- 维护命名的已验收配置，例如multicycle-single、multicycle-dual、pipeline-single、pipeline-dual；非法或未实现组合显式拒绝。
- 构建产物记录完整有效配置、源码/软件hash、工具版本与验收级别；“能生成”“仿真通过”“上板通过”分别标注。
- 先做少量正交对照，不对全部笛卡尔积跑长测试；改变接口/缓存策略时把变量单独列出。
- 标签固定历史实验；未来在同一源码树切配置，二者互补，不能用新默认值重解释旧测量。

本次只整理历史与方向，不增加配置开关、迁移实现或宣称流水线支持。PIPE-P0继续先定义吞吐约束和精确异常，再分阶段实现。
