# 待 Codex 裁定的短清单（每项：推荐 / 依据 / 延期代价）

| # | 决策 | 推荐 | 依据（本地证据） | 延期或选错的代价 |
|---|---|---|---|---|
| **D1** | 实现语言 | **Verilog-2001/SV 子集 + Chisel BlackBox 封装** | M1-a 的模型已把 `SimSerial.v`/`AsyncResetReg.v`/`plusarg_reader.v` 与 Chisel RTL 一起交给 Verilator 跑通（`m1/evidence/hello-run.log`）；旧 Chisel 每轮 elaboration 1.5–3 分钟且要抢 sbt 租约 | 选 Chisel 则 CPU 每轮迭代都占租约、与 SoC 构建串行化；改语言的成本随代码量线性增长，越晚越贵 |
| **D2** | 乘除实现 | **多周期迭代**（移位-加 / 恢复余数），约 64 拍 | 首版目标是正确性与教学可读性；xv6 内核只有 7 条 M 指令、用户程序 2–20 条（M0 §2），吞吐无关紧要 | 选单周期 `*` 会让综合推 DSP、时序余量已只有 +1.542 ns（M0 §1），上板风险高 |
| **D3** | C 扩展 | **S2 就实现**（不走"全量重编译去 C"的软件适配） | 内核 62%、hello.riscv 33/76 条是压缩指令（M0 §2、`m2-prep/evidence/hello-isa.txt`）；去 C 要重建 fs.img 且与上游 diff 变大 | 若推迟，S2 无法跑真实 hello.riscv/bootrom，只能跑自制 rv64i 测试，"能跑现有软件"的目标被推后 |
| **D4** | 特权细节：`mtvec` 模式、`mepc` 低位、委派、CSR 访问语义 | `mtvec` **只支持 direct**（Codex 已批准方向）；`mepc` 低位按是否支持 C 决定（有 C 清 bit0，无 C 清 bit1:0）；**M-only 阶段 `medeleg`/`mideleg` 不可写**；到 S3 实现 S/U 时，`medeleg` 的可写位掩码建议取 Rocket 实测的 **0xB109（这是 medeleg 的支持掩码，不是 mideleg、也不是恒定读回值）**；CSR 读写/只读/零源不写的完整规则见 `STAGES.md`（本轮已补齐） | xv6 `start.c` 写 `medeleg 0xffff`，Rocket 实际只存下 0xB109，移植版 timervec 已按此改写（M0 §2） | 若 M-only 阶段提供"可写但无效果"的委派，软件会以为委派生效而实际不生效，属静默错误；vectored `mtvec` 软件不需要 |
| **D5** | 原子与外部竞争边界 | **首批 I 核不涉及；A 扩展暂不实现（`amo*`/`lr`/`sc` → 非法指令）**。本地 RMW 已被 Codex 否决为正式 A 实现，仅可作为**受外部竞争约束的实验候选**另案提出，且必须先给出"锁字不被外部 master 触碰"的审计证据而不是假设 | xv6 内核只用 `amoswap.w(.aq)` 且锁字不被 TSI/块设备 DMA 触碰（M0 §3）；总线侧原子需要 `TLAtomicAutomata`，AXI4 内存口本身不执行原子 | 若宣称"实现了 A 扩展"，一旦将来有第二个 master 或 DMA 与锁同址就是静默数据竞争；`rv64ua` 通过只证单 hart 语义，**不能**当作全局原子的证据 |
| **D6** | TLB | **首版无 TLB**（每次访存 3 次额外 DRAM 读），S3 再视测量加 1–4 项全相联 | 正确性优先；xv6 在 Rocket 上 usertests 25 分钟主要受 DRAM 分配限制（xv6 port README） | 无 TLB 会让 S3 的仿真更慢（每条访存 4 次总线往返），但不影响正确性；加 TLB 需要 `sfence.vma` 的失效逻辑，晚加比早加安全 |
| **D7** | PMP | **已被 Codex 拒绝"可写无保护"的伪实现。**剩两个真选项：(a) 实现**真实的最小 PMP**（1 条表项、TOR/NAPOT、M-mode 绕过），(b) **明确不实现**（`pmpcfg0/pmpaddr0` → 非法指令）并审计 xv6 `start.c` 的最小软件适配。首批 M-only 核**不依赖**此选择，可推迟到 S3 | xv6 `start.c` 写 PMP 后不再读；S/U 访存在无 PMP 时本来就允许 | 若不实现则要改 `start.c`（软件适配）；**不可**把"吞掉写、读回 0"当成实现了 PMP——那会让将来任何依赖 PMP 的软件静默失效 |

## 裁定结果（Codex，2026-09-15）
- **已批准**：D1（可综合 Verilog/SV 子集 + 薄 Chisel 封装）、D2（迭代乘除）、D3（后续加入**整数** C 支持，不全量去 C 重编译；**无浮点时不得把"全部 RV64C 编码"理解为实现压缩浮点指令**）、D6 方向（后续无 TLB 串行 PTW 起步，不等于本轮冻结 Sv39 全部语义）。
- **部分**：D4 只批准 direct `mtvec` 方向，其余语义本轮已补齐待再裁。
- **已否决**：D5 本地 RMW 作为正式 A 实现；D7 可写但无保护效果的 PMP。二者**不再作为默认实现提交**。
