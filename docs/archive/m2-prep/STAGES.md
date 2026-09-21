# 指令 / CSR 分阶段支持表（M2-a0，Claude 建议）

原则：**未实现的指令一律产生非法指令异常（mcause=2），不静默 NOP；`misa` 只报告真正实现的扩展**。每阶段列"真实支持"与"未支持时的行为"，验收测试见 `TEST_PLAN.md`。

## 阶段 S1：RV64I 裸机 bring-up（首个可执行核）

| 组 | 指令 | 备注 |
|---|---|---|
| 整数寄存器-立即数 | `addi slti sltiu andi ori xori slli srli srai` | `x0` 恒零、写入被丢弃 |
| 32 位形式 | `addiw slliw srliw sraiw` | 结果**符号扩展**到 64 位 |
| 寄存器-寄存器 | `add sub sll slt sltu xor srl sra or and` | |
| 32 位形式 | `addw subw sllw srlw sraw` | 同上符号扩展 |
| 上位立即数 | `lui auipc` | 均为符号扩展的 32 位上位立即数 |
| 跳转 | `jal jalr` | `jalr` 目标清最低位；链接值 = 本指令地址 + 指令长度 |
| 分支 | `beq bne blt bge bltu bgeu` | |
| 访存 | `lb lh lw ld lbu lhu lwu sb sh sw sd` | 未对齐 → mcause 4/6（**不拆分**）；移位/符号扩展在 CPU 侧 |
| 系统 | `ecall ebreak` | mcause 11 / 3 |
| 陷入返回 | **`mret`** | S1 就需要（`t04_trap` 实际使用）：恢复 `mstatus.MPIE→MIE`、特权级 ← `MPP`、`pc ← mepc` |
| 屏障 | `fence` | 单在途下为 NOP，但必须**合法译码** |
| CSR（Zicsr） | `csrrw csrrs csrrc csrrwi csrrsi csrrci` | 见下表 |

**未实现编码的行为（统一规定）**：任何 M/A/F/D/C 编码、任何未列出的 funct3/funct7、任何未实现的 CSR 地址 → **非法指令异常（mcause=2）**，`mtval` = 指令编码，不改任何架构状态、不发总线请求。**不得**静默 NOP，**不得**在 `misa` 里报告未实现的扩展。

**任务切分与本表的对应**（Codex 复核要求写明）：**M2-1 只覆盖 `t01`–`t03`**（整数运算、跳转、访存），异常、CSR 与 `mret` 属 **M2-2**（`t04`），`t05_roi` 的退休基准在 M2-1 末即可用（只需 `minstret` 可读）。

**S1 的 M-mode CSR 最小集**（其余地址读写 → 非法指令）：

| CSR | 实现程度 | 依据 |
|---|---|---|
| `mhartid` | 只读 0 | bootrom `csrr a0, mhartid` |
| `mstatus` | MIE/MPIE/MPP 可读写，其余 WARL 读回 0 | bootrom `csrs mstatus, 8`；trap 压栈 |
| `mtvec` | 可读写（**[决策 D4]** 只支持 direct 模式，vectored 的低 2 位是否 WARL 回 0） | bootrom `csrw mtvec` |
| `mepc` | 可读写，低位按是否支持 C 对齐（见 D4） | bootrom `csrw mepc` |
| `mcause` / `mtval` | 陷入时写，可读 | 测试比对 |
| `mscratch` | 可读写 | xv6 timervec 用 |
| `mie` / `mip` | MSIE/MTIE/MEIE 位可读写；`mip` 只读（由中断线驱动） | bootrom `csrw mie, 8` |
| `mideleg` / `medeleg` | S2 起需要；S1 可读写但无效果 **[决策 D4]** | bootrom `csrw mideleg, zero` |
| `misa` | 只读，**如实**报告 I(+C/M/A 视阶段) | 禁止虚报 |
| `mcycle` / `minstret` | 可读**且可写**（M-mode 规范要求可写）；`minstret` 只在正常退休那拍 +1，陷入不加 | 计数口径、`t05_roi` |

**CSR 访问规则（S1 就必须正确，避免“可读”被误解成“只读”）**：
- `csrrw rd, csr, rs1`：总是写；`rd = x0` 时仍然写，只是不读。
- `csrrs/csrrc rd, csr, rs1`：**`rs1 = x0` 时不得写**（连读改写都不做），只读；`rs1 ≠ x0` 时按位置位/清除。
- `csrrwi/csrrsi/csrrci`：立即数版同理，**`uimm = 0` 的 `csrrsi/csrrci` 不写**。
- 对**只读 CSR**（地址位 [11:10] = 11，如 `mhartid`、`misa`）执行任何**会写**的形式 → 非法指令异常。
- **未实现地址** → 非法指令异常（不返回 0）。
- WARL 字段：写入非法值时保留原值或规范允许的合法值，读回必须是实际生效值——不得“吞掉写、读回 0”而对外称已实现。

## 阶段 S2：M 扩展、C 扩展与真实启动

| 项 | 内容 | 关键设计 |
|---|---|---|
| M | `mul mulh mulhsu mulhu div divu rem remu` + `mulw divw divuw remw remuw` | **[决策 D2]** 多周期移位-加/恢复余数（约 64 拍）vs 单周期 `*`（让综合器推 DSP）。除零/溢出按规范返回定值，不产生异常 |
| C | 全部 RV64C 编码 → 在 DECODE 前展开为 32 位 | 取指按半字推进；32 位指令跨 8 字节 beat 时发第二次取指（SPEC §3）；`mepc`/链接值必须用**真实指令长度**（2 或 4） |
| 启动 | 复位 0x10040 → ROM 里 `wfi` 等 MSIP → M 软件中断 → 0x10000 → `mret` 到 0x80000000 | 需要 `wfi` 与中断接受（SPEC §3、§5） |
| 中断 | MSIP/MTIP/MEIP 输入，`mip` 反映，指令边界接受 | CLINT 的 `lw/sw` 走普通访存 |

## 阶段 S3：S/U 特权与 Sv39（xv6 的门槛）

| 项 | 内容 | 备注 |
|---|---|---|
| 特权级 | M/S/U，`sret`、`mstatus.SPP/SPIE/SUM/MXR`、委派 `medeleg/mideleg` | **[决策 D4]** `medeleg` 的**可写位掩码**在 Rocket 上实测为 0xB109（M0 §2；这是 **medeleg 的支持掩码**，不是 `mideleg`，也不是恒定读回值）；**M-only 阶段 `medeleg`/`mideleg` 一律不可写**，不得提供“可写但无效果”的假委派 |
| S 级 CSR | `sstatus sie sip stvec sepc scause stval sscratch satp scounteren` | xv6 全部用到（M0 §2 的 CSR 清单） |
| Sv39 | 3 级页表、4 KB 页、A/D **软件置位**（缺 A/写缺 D → page fault，与 Rocket 一致）、SUM/MXR、`sfence.vma` | 规格细节见 M0 CONTRACT §A；**[决策 D6]** 无 TLB 起步还是小 TLB |
| 访问故障归类 | PTE 取回总线错误 / PPN 超物理位宽 → 访问故障；非规范 VA、保留编码、超级页不对齐 → page fault | M0 §10 有 Rocket 的逐条行为 |
| 原子 | xv6 只用 `amoswap.w(.aq)`（内核 4 条，用户 0 条） | **[决策 D5]** |
