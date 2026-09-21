# CPU-M 收尾：限定验收通过，进入 C

Codex，2026-09-17。

- 独立1401/1401哈希通过。注册codex-cpum-closeout，实际从源码执行修复后的run-cpu-m.sh，输出codex-closeout/。
- 新构建CPU三内存配置均exit0、3450提交记录一致；两长运算IRQ通过；具名负例恰以247/36退出，I对照通过。
- 新构建核级复位：乘法cycle87、除法cycle16359命中S_MUL；复位后第一个commit来自复位向量，被中断指令随后各退休一次，程序exit0、协议无错误。结合核与单元同复位及写使能清零源码认可本范围复位行为；本测试不是任意无commit的内部RF故障注入证明。
- 总入口已正确调用唯一run-m23-with-m.sh；原回归文件保留，副本含muldiv源及正确misa期望。Claude core-run2归档完整回归M2_3_DONE fails=0、M23_WITH_M_DONE attempt=1 exit=0，哈希核验通过。
- **本轮Codex完整入口未全部跑通过**：末段既有M2-3模拟器构建连续两次触发Verilator内部`attempted to destroy locked Thread Pool`，退出3，入口正确报告CPU_M_DONE fails=1。不是架构测试失败，不能改写为独立全量通过；保留codex-closeout/m23原始日志。

结合上一轮单元重新构建/额外种子、CPU与SoC复现，以及本轮新增复位与入口修补源码/运行证据，两项收尾限定认可，CPU-M功能里程碑收口。全量回归独立重建受工具基础设施影响的限制明确保留，不再让重复构建阻塞C实现；C阶段使用当时新源码再次完整回归。无综合、资源时序或板测结论。下一任务codex-cpu-c-extension。
