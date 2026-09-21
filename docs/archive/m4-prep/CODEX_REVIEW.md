# M4-a 独立验收 — 2026-09-16

结论：部分认可，暂不收口；退回构建接入与门禁窄修，不授权 M4-b/Vivado/硬件。

本轮独立运行结果见 `codex-review/`：交付 RTL 审计 exit0，首次生成反例 exit1（2项）；正常 dry-run exit0；强制 python3 审计返回1后仍 DRY_RUN_OK/exit0；全部五类资源200%占用反例仍 IMPL_CHECK_DONE fails=0/exit0；当前 preflight exit1。本轮未重新生成 RTL、未重跑 CPU 仿真，不能把 Claude 的全回归报告记为本轮独立复现。

## 阻断项

1. 构建层次尚未闭合。原 wrapper 第264行实例化 `Top`；原工程 Tcl 第108行指定硬件顶层 `rocketchip_wrapper`。新文件只提供 `TeachingBoardTop`。构建入口建议将工程顶层设成 `TeachingBoardTop` 会绕开 PS/板级 wrapper，端口相同不能解决模块名绑定。需隔离适配层或独立 wrapper，并保留真正的板级顶层；显式加入 tcpu_core/csr/regfile/defs 等 BlackBox 依赖和 include 路径，输出独立工程，不改原始 wrapper/基线。
2. `m4-build-board.sh` 无 pipefail，审计通过管道尾部 tail 取返回值，掩盖失败。已受控复现；并需门禁验证 ROM 输入实际存在，不能缺文件跳过后仍通过。
3. `check-impl-reports.py` 只打印资源占用不判断超限；无设备、40MHz、时钟/CDC/DRC完整证据也可返回成功。已用全部资源200%的反例复现。实际基线 Vivado timing/util 报告也已调用检查：当前 WNS/TNS/WHS/THS 正则不能读取正常表格，且 unconstrained 关键字扫描误判零问题报告。需以真实报告格式作正例，缺失/损坏/超限/负裕量作反例；机器未覆盖的人工判据必须显式保持待审核，不得声称全关卡通过。
4. preflight 不能只取 glob 首个 bit/report、只看转换镜像存在。应绑定同一次构建的清单与完整哈希；基线清单为空/不完整应失败，缺测试 ELF 应失败，资源占用应阻止本次会话而非仅打印。保留独立人工授权关卡。

## 边界与补证

当前审计复现76端口相同、无 plusarg/TLMonitor/EV/TAILHIT、RESET_PC=0x10040、旁存ROM前156字节匹配；这不是整个 wrapper 的编译或独立从RTL重新抽取ROM证明。HASHES.txt 使用跨目录重复裸文件名，需补可直接核验的路径清单；本轮没有宣称整份哈希通过。

“项目未显式定义 SYNTHESIS”不能推出 Vivado 综合时未定义该宏，工具内建宏需另核实，当前文档应撤回其272站点必编译的确定说法。无需为此提前运行 Vivado。

未发现本轮证据证明正常 CPU RTL 功能错误；M3已验收结论不因这些准备工具缺陷自动作废。下一步仅修 M4-a。
