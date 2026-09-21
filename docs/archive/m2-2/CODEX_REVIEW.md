# M2-2独立验收（2026-09-15）

结论：通过，限定为本任务的M-only CSR、同步异常与mret；尚未中断、C/M扩展、SoC或上板。

## 实际执行

直接重跑run-c二进制，未重新编译CPU。证据 `codex-retest-GMBmLR/`。

- t01/t02/t03/t04/t05 × min/fixed/random，共15次退出0；五程序完整PC/指令/rd/value轨迹跨三档逐字节一致。
- CSR形式/WARL/非法CSR、计数器、mret计数、跳转目标、真实访问故障、ecall/ebreak、trap计数共9项独立运行退出0。
- 三项新增故障：badmepc退出90、trap计入退休退出1、只读写放行退出1。对应软件检查拒绝，不是超时。复跑日志无协议或观测错误。
- run-c完整归档checker退出0。源快照SRC.sha256、全部模拟器/生成C++及ELF哈希独立核对通过。
- 未知+commit-out独立返回3；首次使用旧阶段的.i.elf后缀导致输入不可读，所有调用均在启动前返回3，随后更正为.elf重跑。首次日志保留在 `codex-review-88R7UO/`，不计为功能执行。

本轮未独立逐项重跑全部14类参数反例、旧故障及ROI专用检查；它们经过交付归档checker核验。未将全程周期当作退休数。

## 源码核对与边界

CSR地址及写意图先判非法；零源RS/RC不写，编号非零但值为0仍为写。固定misa保留WARL值，cycle/instret/mhartid写非法。真实mcycle与minstret软件写优先，陷阱不加退休，mret计退休。mstatus仅MIE/MPIE、MPP固定M，mtvec direct、mepc低2位归0，符合本任务明确范围。

trap与退休使用独立路径，真实CSR调试读口参与交叉检查；CSR/RF使能是寄存后在下一边沿生效，报告中“同拍”应结合这一边沿约定理解。此实现不等于通用流水提交接口，后续中断接入仍需按已承诺访存/架构状态更新边界验证。

未知参数问题已收口；新增可写CSR和mret使旧scope-t04/cycle非法读负例不再适用，替换理由合理。

下一步可分派M2-3分阶段实现：整数M/C及中断/BootROM启动，再接既有SoC。当前仅完成验收，尚未分派下一实现任务；不授权直接上板。
