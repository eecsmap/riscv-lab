# CPU-A原子后端阶段收口 — 2026-09-19

裁决：请求语义绑定补修通过；结合前两轮证据，原子后端与V2桥的已测单元/事务驱动子系统仿真范围验收通过。不是CPU-A指令、R-BOOT新配置或xv6验收。

## 独立复核

- 1720/1720交付哈希通过，输出/tmp/codex-atomic-final-hashes.log。
- 审查score.py：CPU_REQ保存完整字段并独立推导TL opcode/param/size/address/data/mask，CPU AMO模型采用请求语义；CPU_RESP对相应D有完成时序检查。
- 复用run10交付二进制独立重跑27场景：19正向sim0/score0，8负向score1（wrong-source断言退出-6，其余sim0）。新增ADD错映SWAP、operand半字互换及真实子系统错映负例均被检查拒绝。
- 原两个独立反例重新生成：wrong-request-operands退出1（114项报告），wrong-request-amo退出1（54项报告），不再误通过。14项具名日志变异独立执行SCORE_SELFTEST_DONE mutations=14 fails=0。
- 脚本codex-review/review-fixed.py新增可选交付/输出目录参数，本轮调用run10 final；结果codex-review/final/，旧档保留。

本轮没有独立重新生成Scala/编译Verilator，没有重新运行旧V1/M3；不把有限复核写成全量形式验证。子系统未映射非原子地址的manager覆盖仍按报告声明边界处理，不影响本次已冻结DRAM原子范围。原子保证不覆盖PS侧直接DDR访问；实际板配置待上板前核验。

下一任务codex-cpu-a-integration：完整A指令与精确异常、V2活动核接入、隔离R-BOOT配置引入已验收后端、boot12及回归。misa.A仅在完整链路验证后置位；xv6启动与教学PMP补丁随后，不在本阶段宣称完成。
