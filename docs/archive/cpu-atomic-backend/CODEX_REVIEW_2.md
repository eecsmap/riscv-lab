# CPU-A 后端补修复核 — 2026-09-19

裁决：R2真实插点/声明DRAM域、R3新增场景及R1原九项反例局部认可；阶段尚不最终验收，只余R1请求语义绑定窄修。

## 独立证据

1216/1216哈希通过；复用run8二进制独立重跑全部24场景，19正向sim0/score0、五负向score1（wrong-source断言退出-6，其余sim0）。包含四真实子系统拓扑正向及一负向。原九个日志变异独立执行SCORE_SELFTEST_DONE mutations=9 fails=0。

本轮未重建Scala/Verilator，未再次跑旧V1/M3回归；审阅实际WithAtomicHub插点及评分器实现，活动CPU与R-BOOT新配置仍属下阶段。脚本codex-review/review-fixed.py，结果codex-review/fixed/。

## 唯一退回项：CPU_REQ → TL A只绑定地址和粗分类

score.py在CPU_REQ处没有保存amo编码、wdata、wmask、write完整语义；A_ACC处只比较addr和kind，未严格比较size/opcode/param/data/mask。因此AMO算术模型的操作与操作数来自待验证桥产生的A_ACC，而非CPU请求。

独立两反例（保持TL、存储和响应日志不变）：

- wrong-request-operands：将所有非零amo的CPU_REQ data改为0x123456789abcdef0；score=0、fails=0。
- wrong-request-amo：将CPU_REQ的所有AMO改为SWAP(1)；score=0、fails=0。

变异及score见codex-review/fixed/。这意味着桥把ADD映射为SWAP或串错operand，模型可能跟着错误TL计算并接受；前次要求的端到端请求绑定仍未完整实现，不是新增功能要求。

## 要求

冻结CPU物理请求完整字段，以独立映射校验TL opcode/param/size/address/data/mask与LR/SC标记；再使用同一请求语义计算预期返回和写结果。非法组合及字节通道清零按V2契约验证，不能只信legal打印值。每条CPU响应必须在对应D完成之后（合法DRAM请求），明确drain例外，避免仅到运行末尾才检查闭合。

补本两反例及size/mask变异、至少一个真实桥映射或operand单缺陷注入，正确控制通过而错误由指定检查拒绝。其余已认可场景保持回归，不重新扩大架构/复位研究范围。
