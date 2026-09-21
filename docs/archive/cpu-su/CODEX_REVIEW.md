# CPU-SU 独立验收 — 2026-09-18

裁决：通过，范围为 Bare M/S/U 仿真，不代表 Sv39、xv6 或新版位流完成。

## 独立证据

- 交付 HASHES.txt 2878/2878 通过（本轮输出 /tmp/codex-su-hashes.log）。审阅 CSR 全文、核心相关改动、DESIGN 与测试入口，符合 CODEX_DECISIONS 的裁定。
- 从源码重新构建 cpu-su/codex-review/core：CPU_SU_DONE fails=0。su01–su11 在 min/fixed/random 三种时序通过；确定性程序提交记录一致，定时器程序检查合法顺序和结果。su12 定向 U 模式中断 enabled=1、fire_priv=0、x7=0x31000，目标指令先退休且 epc=target+4。
- 三具名故障 nodeleg/sirqm/sretspp 分别退出11/14/1，相应 I 对照为0；不是把超时算作拒绝。
- 从源码重新构建 cpu-su/codex-review/c-regression：CPU_C_DONE fails=0，包含 M2_3_DONE fails=0（本轮 attempt=1），M/C 正向、具名负向、IF2 enabled 中断、跨边界取指错误及复位回归均通过。
- 使用交付 soc-run2 模拟器（本轮未重建 SoC），独立重跑原4M3、boot09/boot10 的记录过 misa 修改副本、原始 hello、su01/su05/su06。进程退出码及 HTIF/AXI/程序检查通过，CODEX_SU_SOC_PASS。su05/06 使用真实 SoC CLINT。
- 可复跑 SoC 入口：codex-review/replay-soc.py；结果 codex-review/soc。完整作业日志位于 .coord/jobs/logs/codex-su-{review,regression,soc-review}-20260918-*.log。

## 边界与后续

没有发现本轮需要退回的功能阻断。参考核的初始化差异没有据此宣布已查明；S/U CSR 是已裁定的精简实现，不宣称完整扩展合规。satp 仍 Bare、PMP/time 非法、A 未实现；未综合/上板，教学核 xv6 未启动。

下一任务为单口、无 TLB 的串行 Sv39 PTW；保持当前接口与多周期结构。原子/外部竞争、PMP 启动适配及 xv6 集成另行收口，不扩大本次 S/U 验收范围。
