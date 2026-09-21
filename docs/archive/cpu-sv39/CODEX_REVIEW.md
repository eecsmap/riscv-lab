# CPU-SV39 初次独立验收 — 2026-09-18

裁决：暂不通过，退回一个具体功能缺陷及相应测试，不重开架构设计。

已独立核验1929/1929交付哈希；复用 core-run2/obj_min/tcpu_tb 重跑 sv01–sv06，六程序实际退出0。审阅 DESIGN/REPORT、PTW全文、核心集成diff。尚未独立重建整核、重跑全部回归或SoC，本轮不声称全量通过。

## 阻断：非叶 PTE 的 D/A/U 保留位被忽略

`tcpu_ptw.v` 的 pte_reserved 只检查63:54，非叶分支只检查是否已经到level0。DESIGN §3第4项还明确把非叶 D/A/U 描述为忽略。

冻结规范 v20240411 supervisor §9.3.1 指定非叶 D/A/U 保留；§9.3.2 步骤3要求保留位/编码置位时产生原访问类别的 page fault；Sv39低10位沿用该规则。依据：https://docs.riscv.org/reference/isa/v20240411/priv/supervisor.html 。不能把“软件须清零”解释成“硬件可以忽略”。

独立从当前 PTW RTL 新构建的定向测试 `codex-review/nonleaf.cpp`，结果 `codex-review/nonleaf.log`：

- 合法非叶控制：2次PTE读，翻译成功，PASS。
- 分别仅置非叶 U(bit4)、A(bit6)、D(bit7)：三例均继续读取下一层并成功，fault=0；预期第一次PTE响应后 load page fault=13，不应继续读下一层。三例 FAIL，进程退出1。

因此原有六程序全通过不能覆盖该漏洞。没有修改交付功能RTL；补修任务 codex-cpu-sv39-nonleaf-fix。
