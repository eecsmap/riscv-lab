# PYNQ-Z1 运行边界

本仓库整理不自动部署、不自动连接串口、不改变设备树、不编程硬件。

必须先阅读 `evidence/xv6-board-run-3/CODEX_MILESTONE_ACCEPTANCE.md` 及同目录冷启动记录。当前流程要求 Linux 只使用低 256 MiB，目标独占物理 DDR `0x10000000–0x1fffffff`；目标地址 `0x80000000` 经 wrapper 映射到该区域。xv6 PHYSTOP 为 `0x88000000`。若 ARM Linux 使用整片 512 MiB，运行目标可能破坏 Linux 内存。

操作顺序：冷启动 → 采集当前 boot id / 原始设备树内存单元 / iomem / meminfo → 内存预检查通过 → 部署并核对发布包哈希 → 按已验收冷启动流程配置 PL → 八项裸机探针 → 用磁盘镜像副本启动 xv6 → 四项命令 → 确认 ARM host 退出、锁释放和 ARM 健康。旧 session 的证据只能审计，不能为新 boot 放行。

串口只能有一个读取者。主机退出不等于 CPU 停止，也不等于 DDR 通道排空。`PL_RECONFIG_SAFE=0`，状态 `0x00050900` 不能证明可热重载；禁止以此直接重编程 PL。下一轮配置须重新冷启动并核验内存隔离。

块设备由 ARM fesvr 使用文件提供；`fs-pristine.img` 是只读基线身份，每次运行复制为新文件，不覆盖原镜像。Release 里的 `.bit` 与原始 `.bit.bin` 用途不同，不能互换；先按板端加载方法核验格式。发布包不包含完整 PS Linux/启动介质，不能当作整张 SD 卡镜像。

`tools/board/scripts` 保留已验收的运行/拒绝检查逻辑。除 `make check` 明确列出的离线测试外，其他脚本需先检查参数、旧绝对路径和设备锁；尤其 production-entry 测试可能使用主机 `/var/lock`，不是默认安全单元测试。
