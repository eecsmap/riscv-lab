# R-BOOT 超时终态补修：有限验收通过

Codex，2026-09-17。范围为受控启动流程的块设备排空/清理与超时后禁止继续启动；不代表任意 PL 热重配置安全或新板测通过。

## 独立执行

- 注册作业 codex-rboot-review2：499/499 交付哈希通过；使用交付 build3/sim/obj_dir/sim，**本轮未重编译**。
- `MAXCYC=300000 rboot-run.sh <build3 simulator> <codex-review-2/gates>`：原故障、读/写 DMA 在途、排队完成未消费、三轮重启、永久卡死、晚恢复、删除 READY/释放证据负例全部通过，`RBOOT_DONE fails=0 infra=0`。
- 晚恢复原始日志：205973 TIMEOUT，261610 LATE_DRAIN，ready=0、queued=1、discarded=0；host assert/release/reload=1/0/0，未提前冲刷旧完成。永久卡死和晚恢复均按约定以周期保护退出2，不当作程序正常退出。
- 同一 build3 模拟器跑原4项 M3 ELF，各自 exit0，check-m3/check-axi 均通过：`RD2_BOOT_GATE_DONE programs=4 fails=0 infra=0`。
- 默认板级归档 RTL 实算 SHA256：28ec3c910ac388e589dd40e9fdfbe63b75da912b09efbca6c526aa2f72443c68。本轮未重新生成该 RTL，未综合、未触板。

## 源码复核与边界

RD2Soc 的 rbFailed 无普通退出分支，仅冷复位离开；失败状态 hold 持续，flush 只在 rbFlush，READY 只在 rbReady。截止拍完成优先的规则有明确注释。host 超时进入 R_FAILED，其分支优先于正常 READY 释放路径，故后续 READY 不会触发重载。对 host 的伪 READY 行为本轮为源码复核，未另做运行时信号强制注入。

结合上一轮正常路径验收，R-BOOT 在上述限定仿真范围收口。PL_RECONFIG_SAFE 仍为0，不授权带活 PS 事务重载 PL；真实恢复按冷平台复位流程。fix13 的独立有限复核及其他已延期 RD2 项不因此自动通过，不阻塞独立整数 M 功能实现。

证据：`codex-review-2/gates/`、`codex-review-2/boot-gate/`；作业日志见 `.coord/jobs/logs/codex-rboot-review2-20260917-193621.log`。下一任务 `.coord/proposals/codex-cpu-m-extension.md`，完整 RV64 整数 M，C 下一阶段单独分派。
