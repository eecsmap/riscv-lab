# M4-a 最终验收 — 2026-09-16

结论：M4-a 上板准备阶段验收通过。不是综合/布局布线通过，更不是板上启动或xv6验收。

## 本轮独立运行

- 从workspace根运行 `sha256sum -c experiments/teaching-cpu/m4-prep/HASHES.txt`：153项全部OK，exit0；没有重生成预期哈希。
- 运行 `bash experiments/teaching-cpu/m4-prep/scripts/selftest.sh experiments/teaching-cpu/m4-prep/codex-review-3-tests`：SELFTEST_DONE cases=68 passed=68 wrong=0，exit0。新生成35个fixture，逐项日志保存在上述独立目录。
- 检查本轮selftest、fixture生成与preflight源码：正式baseline-identity不再被负例覆盖；退出状态和诊断双重断言；源清单/工程Tcl作为构建产物清单必需项，预检验证封存源哈希。

## 通过范围

板级接口/ROM静态审计、Top shim及离线层次、独立工程Tcl静态检查、构建入口失败传播、真实Vivado报告解析及缺字段/跨时钟证据/负裕量/超限/矛盾记录反例、当前预检拦截、构建身份缺失/漂移/跨目录反例，均在本轮自测中复现。测试用人工声明只验证checker分支，不构成实际实现或硬件批准。

前轮已指出的报告缺证据误PASS、自测fixture未生成而冒充覆盖、HASHES混用根、缺构建源清单绑定，按本阶段范围完成补修。保留此前不通过报告及证据；不把它们改成历史通过。

## 下一阶段边界

M4-b需用户另行授权Vivado构建，仍不碰硬件。构建开始前封存实际使用的源/工程清单，结束后将真实报告/位流/工具版本/约束身份纳入同次清单；人工检查实际工程源集合、时钟/CDC/DRC、器件资源、40MHz时序、dbg裁剪和无故障注入。清单哈希证明登记文件一致，不独自证明位流由该源码构建；需真实构建日志与过程对应。生成脚本执行及Vivado elaboration尚未验证。

M4-c另行授权板测；实际bit到bin转换、回退镜像关系、PS加载与裸机启动尚未验证。自测bit/bin是占位文本，不是可烧写产物。mtime实际400kHz与DTB声明1MHz差异继续保留为已知限制。

本轮无CPU/RTL修改，未重生成设计或重跑CPU仿真；未启动Vivado/hw_server/JTAG/串口，没有板卡操作。
