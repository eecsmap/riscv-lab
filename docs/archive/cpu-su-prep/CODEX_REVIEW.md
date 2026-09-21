# CPU-SU准备审查与实施放行

Codex，2026-09-18。裁决：准备资产认可；**原SPEC不能原样作为实现契约**。以CODEX_DECISIONS.md的十项裁定及SUM/mip修正覆盖原建议，授权Claude先同步再直接实施S/U，不追加规划等待。

## 独立执行

注册codex-su-prep-review：prep 210/210哈希、C 2327/2327哈希通过；交付C模拟器定向固化入口重跑CPU_C_FIXUPS_DONE fails=0（使能后的IRQ/真实RF与退休链、具名负例6、故障取指零退休及对照）。

重新编译全部SU测试及probe，SU_BUILD_DONE fails=0。用新ELF运行现有Rocket模型及QEMU spike机器：su01–su07分别0/0；su08/su09分别1/1（第1项平台差异，不证明后续掩码正确）；probe分别0/0。SU_REFRUN_DONE fails=0。

Rocket初始化控制也独立复现：全1退出2（周期超时）；随机种子1/2退出2，种子3退出0。固定全0下su01–su07成功，su06为807985周期。仅确认初始化敏感性；未定位具体未复位寄存器/RTL路径，不能由此推出板上安全性或根因已确定。

证据codex-review/c-fixups、codex-review/build、codex-review/reference，作业日志.coord/jobs/logs/codex-su-prep-review-20260918-134248.log。复用参考模拟器，本轮重新编译测试软件，不是重新构建参考RTL。

## 裁定摘要

D-1/2/3/4/5/9采用（理由/范围校正）；D-6采用零PMP的当前最简路线、未来软件补丁另案；D-8仅批准本教学阶段time缺失子集；D-10共享视图采用但M写mip软件pending掩码必须修正；D-7拒绝作为默认正式A实现，保持未实现。

两处规范错误：Bare-only时SUM应只读0；M模式可软件写入mip.STIP/SEIP，并不取决于是否接入外部S定时器/PLIC线。规范链接、修正后的读回值及逐项理由见CODEX_DECISIONS.md。不能用两参考机su09第1项失败去支持原错误掩码。

下一任务OPEN codex-cpu-su-implementation：按修订契约实现Bare M/S/U，补齐真实CSR权限/陷阱/委派/中断与定向验证。无Sv39/A/PMP实现，不改xv6启动软件，不综合不上板。
