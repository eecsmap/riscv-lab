# M0 契约草案：教学 CPU 架构与总线接口（待 Codex 裁定处标 **[决策]**，其余为证据确定）

Codex验收注（2026-09-14）：M0按平台审计交付验收，不等于本文全部候选架构已冻结。权限规则中的“S访问U页需SUM”仅适用于数据读写；S模式取指不得执行U页，不受SUM放宽，本地 `rocket-chip/src/main/scala/rocket/TLB.scala:174` 的 priv_rw_ok 与 priv_x_ok 分开实现。首版热复位不支持；主机在启动时切换sys_reset并不能自行证明上次运行的AXI事务已排空，冷启动/确认总线空闲是额外使用前提。完整A扩展、PMP和计数器权限不能由当前xv6样本测试推定。

## A. CPU 架构（由现有内核/用户程序/启动链证据确定）
- ISA：RV64IMAC + Zicsr + Zifencei。无 F/D（misa F/D=0；FP 指令→非法指令）。C 必需（除非 **[决策 A1]** 采用软件适配全量重编译 rv64ima）。
- 特权：M/S/U；medeleg/mideleg 可写；**[决策 A2]** 可委派异常集：最小 = Rocket 的 0xB109（misaligned fetch、breakpoint、ecall-U、三种 page fault）；建议额外允许 bit 2（非法指令）、4/6（misaligned ld/st）以简化 M-mode 处理——但 xv6 port 的 timervec 已按 Rocket 行为改写，两者都能跑，需选一个并固定。
- CSR 最小集：mstatus mie mip mtvec mepc mcause mtval mscratch medeleg mideleg mhartid misa(只读)；**[决策 A3]** pmpcfg0/pmpaddr0 与 mcounteren 的处理是设计取舍不是架构事实：候选 (i) 实现为可读写、无强制效果的寄存器（xv6 `start.c` 写 pmp 后不再读；S/U 访存不受限）；(ii) 不实现并陷入 → 必须改 `start.c`（软件适配）；(iii) 实现最小 PMP（1 项、TOR/NAPOT）。支持边界写明后再冻结；menvcfg 不实现；sstatus sie sip stvec sepc scause stval sscratch satp scounteren；time/cycle/instret 只读计数（xv6 用 `r_time`? 未见，列可选）。
- 中断：mtip/msip（CLINT）、ssip/stip（软件置位）、meip/seip 接 PLIC（无源）。取中断只在指令边界，且不在有未完成访存时（RW9 安全窗口经验）。
- 异常精确：所有同步异常在该指令提交前生效，无副作用（访存异常在总线请求发出前判定：misaligned、权限、翻译故障；总线错误响应→访问故障，此时写副作用可能已发生——与 Rocket 一致）。
- MMU 最小规格（sv39）：satp.MODE=8（MODE=0 裸模式必需；其他值 **[决策]** 忽略写或非法）；3 级、4 KB 页；串行遍历共用物理口。规则（规范要求，Rocket 行为见 REPORT §10）：非规范 VA（位 63:39 ≠ 位 38）→ 该访问类型的 page fault；PTE.V=0 或 (W=1,R=0) 保留编码 → page fault；非叶子到第 0 级仍是表 → page fault；叶子在第 1/2 级且 PPN 低位非零（超级页不对齐）→ page fault（xv6 不用超级页，但规范要求，需规格验证）；缺 A 或写时缺 D → **[决策 A4]** page fault（不写 PTE，与 Rocket 一致，xv6 已软件置位）；权限：U 页仅 U（S 访问需 SUM）、非 U 页仅 S、R/W/X 检查、MXR 允许读 X 页；PTE 取回遇总线 error → 访问故障（按原访问类型 1/5/7）；PPN 超出实现物理位宽（32 位）→ 访问故障（Rocket 同）。sfence.vma 使遍历缓存/TLB 失效。TLB **[决策 A5]**：首版无 TLB（每次访存 3 次额外 DRAM 读）或 1–4 项全相联；正确性优先。

> **2026-09-18 注（cpu-atomic-prep）**：本节“原子由 CPU 内部读→改→写两笔总线事务实现”的建议已被 Codex 否决（m2-prep D5、cpu-su-prep/CODEX_DECISIONS.md D-7），不再作为默认实现；现行契约见 `experiments/teaching-cpu/cpu-atomic-prep/CONTRACT.md`。以下文字为历史记录。
- 原子（**受限单核 xv6 使用边界，不是完整 A 扩展实现**）：AMO 由 CPU 内部 读→改→写 两笔总线事务实现，期间：不发其他请求、不取中断（中断在指令边界）、不可被外部主设备察觉为原子——TSI/BlockDevice DMA 若写同一字，结果未定义；xv6 满足前提（锁字只被 CPU 触碰，证据 §3）。LR/SC：CPU 内保留位（地址匹配）；SC 在 LR 后有异常/中断/其他访存或地址不符时失败；**不检测外部写入**。`rv64ua` 测试通过只证明单 hart 语义，不证明全局原子；本轮软件审计“无 LR/SC 使用”与未来测试是两回事。**[决策 A6]** 是否在适配器用 `edge.Arithmetic/Logical` 发 TL 原子（本 checkout 的 AXI4 内存口不执行原子，需 `TLAtomicAutomata`）——建议否。
- misaligned 访存：陷入（causes 4/6），不做硬件拆分。
- fence/fence.i：等待无未完成事务（单在途即天然）后 NOP；sfence.vma 见 MMU。
- 复位：**PC=0x10040**（BootROM `hang`，证据 REPORT §4），mhartid=0，特权 M，mstatus.MIE=0，mip.MSIP 由 CLINT 驱动；启动依赖 M-mode 软件中断被取（REPORT §4 顺序）。
- wfi：可实现为 NOP 或等待中断——但 **bootrom 的复位路径就是 `_hang` 的 wfi 循环**，因此 wfi 之后必须仍能取 MSIP。
- 计数器：mcycle/minstret 可选；xv6 不依赖。

## B. 物理内存口（CPU ↔ 适配器）契约（单套 ready/valid，由证据与 RW 系列经验确定；宽度为 **[决策 B1]** 的候选冻结值）
- 请求（Decoupled）：`valid/ready`；字段在 valid 期间保持、握手前不得撤回、不得改变；`addr[31:0]`（本 SoC 物理地址 32 位足够；PTE PPN 超范围由 CPU 判访问故障）；`op`：0 read / 1 write（AMO 由 CPU 拆成 read+write）；`size`：**log2(字节数)**，取值 0..3（1/2/4/8 字节），直接用作 TL `lgSize`（不再二次编码）；自然对齐（不对齐由 CPU 先陷入，不上口）；`wdata[63:0]`（按地址低 3 位放置，或固定低位放置由适配器移位——**[决策 B2]** 建议数据按字节通道对齐放置 + `wmask[7:0]`）；`wmask[7:0]`；可选 `kind`（fetch/load/store/ptw）只作观测，不影响事务（**[决策 B3]** 是否保留）。
- 响应（Decoupled）：`valid/ready`（CPU 可保证 ready 恒 1，但适配器须按握手保持，不得靠"消费者总 ready"）；`rdata[63:0]`（读；按字节通道对齐）；`error`（本 checkout 的 `TLBundleD.error` → CPU 访问故障：fetch 1 / load 5 / store 7）；响应不早于请求握手后的下一拍；每请求恰一次响应；单在途（CPU 在收到响应前不发下一请求）。
- 写完成定义：响应 = TL AccessAck 已收到（目标已接受写）。MMIO 顺序：单在途 + 按序 → 程序序即总线序。
- 复位（**受限前提**）：`sys_reset` 只复位 target 子系统（CPU、TL 总线、CLINT/PLIC/ROM、Serial/BlockDevice、AXI4 桥），**不清空 PS DDR，也不撤销已进入 AXI 互连/PS 的事务**。首版契约只承诺：复位发生在 fesvr 启动时、总线空闲、任何 TSI/DMA/CPU 流量之前（现有 `zynq_driver.cc` 流程即如此，是主机操作前提）；运行中的热复位**不支持**，不声称安全；若将来只复位 CPU 而不复位适配器，适配器须等在途 TL 响应返回后才接受新请求——不在本轮实现。
- 时序：全部寄存边界（响应至少 k+1）；无组合环（valid 不依赖 ready）。

## C. 适配器（req/resp → TileLink-UL）
- `TLHelper.makeClientNode(name, sourceId = IdRange(0,1))`（testchipip `Util.scala:125`，产生 `TLClientNode`），挂 sbus；请求映射：读 → `edge.Get(0.U, addr, size)`、写 → `edge.Put(0.U, addr, size, wdata, wmask)`（PutPartial；`lgSize` 即契约 `size`）；响应：`d.opcode` AccessAck/AccessAckData，`d.error` → `error`；不使用 Arithmetic/Logical/Hint/Acquire。API 对照见 REPORT §9。
- 中断：`IntSinkNode` 接 CLINT（msip、mtip）与 PLIC（meip、seip）。
- 取指同口：CPU 每次取 8 字节对齐 dword（size 3）并在内部按 2 字节粒度取指令，32 位指令跨 8 字节边界时再取一次。

## D. 明确未冻结（需 M1/M2 实测或 Codex 裁定）
- 数据放置约定（B2）、kind 字段（B3）、TLB 有无（A5）、委派集（A2）、PMP 处理（A3）、实现语言、C 是否软件去除（A1）、TL 原子（A6）、mtime 实际频率。
