# CPU-A首次验收 — 2026-09-19

裁决：A功能主体独立复核认可，阶段尚未完整收口。只补下列回归与入口问题，不重做原子架构。

## 独立证据

- 1611/1611交付哈希通过（/tmp/codex-cpua-hashes.log）。审核心A解码/执行/异常分类、请求字段及报告/runner。
- 注册codex-cpua-review，从当前源码重新编译ELF及十模拟器，codex-review/core得到CPU_A_DONE scenarios=15 infra=0 fails=0。138例/72种AMO组合三时序通过，LR/SC三时序及外部竞争通过，21异常测试两时序通过，定向IRQ完成/退休次序通过，五具名缺陷被拒绝。正向实际sim退出均0（不只相信总入口）。
- 复用交付SoC模拟器，独立重跑atomic boot12_amo、atomic/default a05_misa_probe，实际进程退出0且check-m3通过；boot12独立事件checker通过。证明已测配置的完整A路径与misa双向边界。脚本codex-review/replay.py及.log/.exit/.check/.events。
- 本轮未重新生成SoC、未独立重跑全部旧回归及R-BOOT八项；Claude对g2的历史定位与失败日志已审，但根因尚未证明。

## 收口项

1. **R-BOOT g2-write-inflight未恢复。** 这是冻结门禁失败，不因旧SU也失败就自动豁免。现有证据把出现时间范围缩到较早版本，并没有证明根因在块设备而非CPU/软件/握手。需针对同一ELF/磁盘/触发比较首次请求、DMA、完成队列、重启及重发因果，最小修复；不删除该项、不单纯增加超时。run-soc-a.sh目前把此项INFRA排除并输出fails=0，不能当全量通过，修后恢复严格总入口。
2. **正向退出码未强制。** run-cpu-a.sh的score函数接收rc却只检查checker状态；a01/a02 checker不接收实际rc，非0退出可能被遗漏。所有正向都须退出0、有效完成签名及无协议/基础设施错误。负例只能由指定语义检查通过，不以无完成/异常退出单独计成功。保留本轮实际退出0证据，不追溯改档。
3. **补齐启用A配置下的冻结回归。** 已有SU/Sv39/M2-3回归运行MISA_A=0，证明旧配置兼容而非全部新配置回归。保留两侧边界探针，同时对新配置跑IMC/SU/Sv39，必要misa期望用副本diff。SoC补boot09/boot10 misa副本、原始hello、su01/05/06真实CLINT；当前runner只有4M3/boot11/12及探针，不是原任务全部清单。

未综合上板、未改xv6。下一任务codex-cpu-a-closeout完成这三项后，转教学xv6启动，不扩展微架构或一般复位矩阵。
