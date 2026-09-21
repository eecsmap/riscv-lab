# M1-a/b 独立复核（2026-09-14）

## 2026-09-15 补修最终验收：通过（桥单元范围）

Codex独立重跑 `bridge-fix-20260914T224216Z` 全13个二进制，5正向退出0、8负向退出134且逐一命中目标错误。新证据 `codex-fix-review-zbEfhK/`。本轮未重新编译。

- zerolat/zerolat-bp各704笔、错误0、694笔同拍A/D；后者响应背压1084拍。旧桥对照A等待4004拍、A/D均0，按预期超时。源码确认D.ready仅依赖状态，并处理sA同拍A/D。
- valid临时撤销、等待期间载荷改变分别在cycle10命中专属保持错误；checker以前拍pending为条件，覆盖最终握手拍。
- 正向每例8笔本地拒绝，包括映射但不支持操作/尺寸，零TL事务检查通过。
- `MAXCYC=200`受控运行run-sim.sh独立返回2，错误码传播通过。
- 13例RTL/二进制哈希均通过；13例六个源码哈希在实际源码目录核验均通过。首次在workspace根执行相对路径sources.sha256失败仅因工作目录错误（原日志保留），改在隔离树common/src/main/scala/teaching核验通过；非源码漂移。四份Scala交付快照与构建源码一致。

M1-a前轮已通过，本轮收口M1-b。不代表桥SoC集成、DDR或教学CPU启动通过；下一步为旧SoC内无CPU事务发生器接桥的集成验证。BusTest.scala中两处“at most 4 bytes”注释已过时，实际TeachingWideOnlyRAM只支持8字节读，以代码为准；非功能阻碍。

以下保留初次退回记录。

结论：M1-a 环境验收通过；M1-b 现有用例限定通过，整体退回窄修。

## 实际运行

独立运行已交付二进制（未重新生成/编译），证据目录 `codex-m1-review-jsbj89a1/`，含逐例原始日志、退出码、桥二进制哈希。

- hello：输入ELF与模拟器均通过交付SHA256核对，三项自检通过，退出0，6861周期。
- clean/delay/backpressure：退出0，分别966/1366/1366笔，错误0；A/D计数960/1360/1360闭合。
- 五个故障：均SIGABRT（Python返回-6，对应shell134），日志分别命中数据错误、响应超时、重复响应、写提前完成、错误位丢失。不是仅凭非零退出判定。
- 当前ReqRespToTL源码快照与隔离树文件一致。未重新跑xv6，未做桥SoC集成、Vivado或上板；Rocket hello不等于教学CPU已运行。

## 必须补修

1. **零延迟manager互等（源码推导，尚未RTL复现）。** ReqRespToTL仅在sD/sDiscard拉高D.ready，sA必须先A.fire才能进入sD。旧TLRegisterNode的RegisterRouter.scala将A.ready连接RegMapper输入ready、D.ready连接输出ready；RegMapper.scala在concurrency=0时back=front，input.ready依赖output.ready。因此直接接这种合法组合manager时，sA的D.ready=0阻止A.fire，无法进入sD。现有TLRAM与TLError均声明minLatency=1，没有测试同拍响应。须增加真实零延迟manager并复现旧桥失败，再修复（正确处理同拍A/D，或显式桥内缓冲），CPU侧仍保持至少下一拍响应。
2. **背压保持checker漏检valid撤销。** BusTester仅在当前resp.valid仍为1时比较payload；上一拍valid&&!ready、当前valid=0不会报错，隔拍重发甚至改payload也可能漏过。应从上一拍待握手条件出发检查当前valid及payload，包括最终握手拍；新增临时撤销后重发、等待时改payload反例，必须按协议原因失败。现有fault2是永久丢响应，不能替代此覆盖。
3. **覆盖/入口收尾。** 增加已映射但不支持该size的manager定向测试，证明本地拒绝且零TL事务；当前只有unmapped。run-sim.sh最后echo导致子进程失败仍可能脚本返回0，须传回ec，并验证失败入口。补修构建必须重新生成对应RTL，不用“文件存在”复用旧生成物，记录源码→RTL→二进制哈希对应。

上述只收口原M1任务，不扩大到CPU实现或上板。委托见 `.coord/proposals/codex-m1-bridge-corrections.md`。
