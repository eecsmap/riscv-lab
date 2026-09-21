# M4-a 补修独立验收 — 2026-09-16

结论：主要补修认可，仍有验证完整性缺口，暂不最终收口。无 Vivado/硬件授权。

独立证据在 `codex-review-2/`，可运行 review.py 重放。未运行整套 selftest：其最后一项会暂时覆盖交付 baseline-identity.txt，而且已发现 fixture 生成错误。未重生成 RTL、未重跑 CPU 仿真。

## 已认可

- build dry-run exit0，含12文件哈希、shim对照、ROM抽取审计、Tcl静态检查、126模块离线层次检查；工程顶层保留 rocketchip_wrapper，Top shim 接 TeachingBoardTop。
- --execute exit3；注入 python3 失败后入口 exit1，不再掩盖。
- 真实基线报告无人工声明 exit2/PENDING，带测试用声明 exit0；这些声明只用于 checker 测试，不是硬件放行。
- 独立构造健康资源行遮蔽超限行的有效 fixture，exit1，明确报矛盾及超限。
- 当前无构建，preflight exit1。
- HASHES.txt 135项在m4-prep目录通过，最后4项却相对于workspace根；单命令核验 exit1。另从workspace根核验最后4项均通过，未发现这些文件内容变更。

## 尚需修复

1. 缺报告结构被视为成功。由真实通过报告仅删除 Device/Design State 字段，带同样测试声明仍exit0；将 Inter Clock Table 标题改为未知标题仍exit0。源码对 dev/st 缺失跳过检查，inter regex不匹配直接当空表。必需身份/状态/跨时钟证据缺失或不可解析必须FAIL/PENDING，不得PASS。补正例、逐字段缺失与缺表定向反例，并确认失败原因。该原则也适用于DRC归属/状态和其他必需报告字段。
2. 自测虚报覆盖。selftest.log 有 SyntaxError；quoted heredoc 内 `open("'"$W"'/shadowed-util.rpt",...)` 不是有效Python，文件根本没生成，impl-shadowed-resource.log失败原因是文件不存在。58退出码符合预期不等于58项预期场景被验证。fixture生成失败应立即停止；断言变换次数、文件存在及预期诊断，不仅断言任意非零。thin-baseline负例应使用输入覆盖/隔离副本，不能临时覆盖正式证据再恢复。
3. HASHES.txt仍混用两个工作目录；补统一相对根或绝对路径，并在提交前从指定目录真实运行 sha256sum -c，不要以重新生成清单替代核验。
4. 构建身份仍未绑定：preflight读取当前全局源MANIFEST，而BUILD-MANIFEST没有记录本次构建所用源MANIFEST/Tcl的哈希。更新源清单后，旧产物仍可能用新源身份接受审核。需每次构建封存源/工程清单并由产物清单引用哈希，预检用这一份验证；跨构建报告/位流替换的负例应拒绝。测试fixture可用假bit文件，但不能因此宣称已验证真实位流内容或转换关系。

这些是准备与验证链缺口，未发现新CPU功能错误；保留M3已有验收结论。后续只补上述项目，不扩大CPU范围，不提前执行综合或上板。
