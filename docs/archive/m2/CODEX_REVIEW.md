# M2-1首次验收（2026-09-15）

## 补修验收：M2-1通过（独立执行核子集）

Codex独立复跑run-f二进制，未重新编译CPU。新证据 `codex-fix-review-8Euvjx/`。

- 4程序×3延迟全部退出0；另重跑生成完整commit轨迹，逐文件比较min/fixed/random的PC/insn/rd/value一致。首次使用的+commit-out参数被忽略，随后改为实际支持的+commit-trace重新运行，轨迹结论只来自第二轮文件。
- 3个ROI专项均退出0、49条静态PC期望通过，程序计数回读49。
- 原Codex非法JALR ELF及funct3=1..7全部按cause2陷入；后7项检查链接寄存器哨兵通过，故障指令不退休。
- load载荷正常用例退出0；泄漏注入明确打印wdata=0xdeadbeef并退出5。源码正常路径只在store设置wdata。
- tail-error退出4、cause7；tail-drop退出10、TAIL INCOMPLETE，未误报成功。min-t03实际req=resp=115，退休94（含最终store）。
- cycle非法用例按cause2通过，真实minstret用例退出0；源码已去掉cycle/mcycle假返回。
- run-f归档checker退出0；交付SRC.sha256及全部模拟器/生成C++哈希核对通过。旧x0/符号扩展等故障本轮仅核查归档checker，未逐项独立重跑。

RF写回仍为顺序控制信号后一边沿落地，harness在该边沿后读回检查；当前串行执行留有间隔，本轮未发现功能冲突。后续接精确异常/中断时须保持架构更新与观测时序明确，不能直接沿用流水核的commit假设。

四个退回项已收口。支持范围仍是RV64I执行子集及有限计数器读取，trap后停机；不代表完整Zicsr/M-mode、M/C/A、BootROM启动、SoC接入或上板。下一步M2-2应明确M-mode CSR/同步异常返回规则后实施，不重开本轮已完成项。

以下为首次退回记录。

结论：12个正向独立复现通过，但发现真实译码缺陷与接口/验证缺口，暂不最终验收。

实际执行：直接运行run-e的min/fixed/random四程序矩阵12次，全部退出0；交付check-m2-1.py检查run-e退出0。本轮未重编译CPU。新证据 `codex-review-zEH7QY/`。

## 阻断项

1. **非法JALR译码被接受，已RTL仿真复现。** is_jalr只检查opcode，illegal未验证funct3=000。独立 `codex-jalr-illegal.S` 使用funct3=001，应cause2；实际执行跳转并写TOHOST code=0，harness在expect-trap=2下退出7。修全部非法JALR funct3并给定向回归（epc/tval正确、该指令不退休、不写链接寄存器）。
2. **load请求wdata未清零。** S_EXEC对load/store统一赋req_wdata=rs2_val<<lshift；load的rs2位其实是立即数的一部分，可能读到非零寄存器。冻结PHYSICAL_PORT_V1明确读wdata/wmask固定0。修为仅store使用数据并加读载荷合法性monitor及非零寄存器命中测试。这是源码确定的违规路径，本轮未单独仿真抓拍。
3. **过早结束掩盖最终store完成。** C++看到后门tohost内存写入即break，不等对应响应和store退休。run-e的min-t03为req115/resp114；本轮独立JALR样例也req14/resp13。不能将未完成尾部计作完整事务验证。锁存退出请求，等待对应tohost store响应及退休后再判定；停止点避免把后续取指算成遗留事务。增加尾部响应error/丢失的对照，不能仍PASS。t01–03跨延迟完整PC/insn/rd/value轨迹比较原任务要求仍未实现（当前只比较总退休数），请补齐。
4. **额外CSR虚假实现。** 核接受cycle/mcycle读但统一返回0；既然宣称支持不能伪造。首项只需minstret，删去未实现cycle编码使其非法，或实现真实周期计数及测试。不要扩大到完整CSR阶段。

其它边界：寄存器堆写在WB设置rf_we后的下一边沿发生，而commit在WB已举起。当前串行取指留有间隔，未证明存在执行错误，但观测口不是同拍真实RF更新，后续须明确/对齐，不用观测自证正确性。

本轮未独立重跑全部故障/ROI；已有正向与归档checker通过不抵消上述新反例。修完回归原门禁，保留旧run-e。
