# CPU-C：整数 C 仿真阶段验收通过

Codex，2026-09-18。裁决对象claude-cpu-c-acceptance。基于以下独立执行与源码核对通过，不表示xv6已启动、完整特权兼容或FPGA时序通过。

## 独立证据

- 1775/1775交付哈希通过。注册codex-cpuc-review，重新构建解压单元与CPU门禁，输出codex-review/。
- 解压枚举49152个压缩parcel：38157合法、394 HINT、10601非法，零不一致。两个新构建故障版本分别1024/16232不一致，均exit1。
- 新构建CPU：31/31整数C助记符执行，三种内存配置216条提交一致，135条压缩退休；32位指令起点覆盖pc%8=0/2/4/6。M程序三配置通过。
- 跨4KiB边界、两段各自访问错误、非法编码、c.ebreak、半字地址mret通过；两种IF2注入、六项取指中途核复位、两具名故障（实际tohost6）与I对照通过。
- 本轮从源码完整回归M2-3通过：M2_3_DONE fails=0、M23_WITH_C_DONE attempt=1 exit=0；最后M长运算IRQ也通过，CPU_C_DONE fails=0。与上一轮M审查不同，本轮不再只是审阅归档全量回归。
- 注册codex-cpuc-soc-review，使用交付soc-run2模拟器独立重跑原4M3、boot09、boot10和hello，所有实际exit0，check-m3/check-axi通过。hello与原始riscv-test/hello.riscv逐字节一致，控制台重建确认sum(1..100)=5050。**SoC本轮复用二进制，未独立重编SoC**。可复跑入口codex-review/replay-soc.py。

## 发现并独立补足的IRQ证据

原两例在pc=0x80000000、enabled=0时即FIRE，随后开中断才进入handler；因此原报告“第二半取指期间推迟已使能中断”的证据不足，不能仅靠命中状态和中断次数证明。

Codex对本轮新构建obj_irq-if2req/obj_irq-if2resp，使用同一i01.elf，追加：

```
+inject-pc=800001d0 +target-pc=800001d0 +target-reg=7:31000
+expect-fire-state=IF2_REQ   # resp版本为IF2_WAIT
+expect-interrupts=1 +expect-cause=7 +min-irq-hits=1
```

二者exit0、enabled=1，目标为该ELF中开MIE后的lui t2,0x31；mepc均为0x800001d4。请求阶段commit633→IRQ636；响应阶段commit582→IRQ585；真实RF x7=0x31000已生效、目标恰退休一次。日志aimed-req.log/aimed-resp.log。因此补足此次功能裁决；要求下一任务把这个检查固化到入口，用符号/反汇编推导地址而非永久硬编码。

## 限定与后续

- 核级复位例使用测试台丢弃陈旧应答模型；不是带新C核重新证明真实RD2所有复位窗口。原真实桥仍有自身排空状态与复位协议；普通运行时valid不可撤销没有被放宽，不能把复位边界下的核端取消推广到TL上已经承诺的事务。
- 故障取指“不退休”源码路径合理，但当前runner在未输出提交轨迹的stdout搜索PC，不是独立退休证据。后续维护时改为真实提交计数/轨迹；本轮不据此宣称已测试具名“故障仍退休”变异。
- 负例入口仍接受任意非零；本轮独立确认实际为具名结果检查6，后续固化为精确退出与原因，防止基础设施错误冒充拒绝。
- 以上验证入口固化作为下一任务前置小修，不重开解压/复位通用矩阵，不否定已经实跑的功能结果。
- 无综合/上板，不报告资源时序，默认板级产物未替换。下一步CPU-SU规格与测试准备，随后S/U实现、Sv39及原子/PMP真实契约、xv6。
