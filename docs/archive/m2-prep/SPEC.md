# M2 教学 CPU 首版规格（Claude，2026-09-15，待 Codex 裁定后冻结）

任务书 `.coord/proposals/codex-m2-spec-and-test-prep.md`。约束沿用已冻结的 `PHYSICAL_PORT_V1` 与已验收的 `ReqRespToTL`（M1-b/M1-soc）。**本文是建议 + 依据，不是已批准架构**；M0/NEXT_TASKS 里的候选说法（如 AMO 本地 RMW）在此重新提出并标为待裁定。

## 1. 推荐：直接写 Verilog-2001/SystemVerilog 子集，经薄 BlackBox 封装接入

| | 方案 A：旧 Chisel 3.1 直接实现 | **方案 B（推荐）：独立 Verilog + Chisel BlackBox 封装** |
|---|---|---|
| 工具依赖 | 必须在 JDK 8 容器里跑 sbt 0.13/1.1，改一行等一轮 elaboration（实测生成一个配置约 1.5–3 分钟） | 改 CPU 只需 Verilator（主机本地，秒级）；只有封装/配置变动才碰 sbt |
| 与已有资产的接口 | 直接 `Module`，最自然 | `BlackBox` + `addResource`/`-I` 均可；testchipip 与 rocket-chip 里已有多处 BlackBox 先例（`SimSerial.v`、`AsyncResetReg.v`、`plusarg_reader.v`），**本地已验证可用**（M1-a 的模型就链接了这三个） |
| 语言能力 | Chisel 3.1 较老（无 `Definition`/`Instance`，`Chisel._` 与 `chisel3._` 混用有坑，本轮已踩过 `dut.io.start` 不自动失效化） | Verilog 子集稳定，教学可读性好；Verilator 5 与 Vivado 都直接吃 |
| 测试 | 必须走 sbt→firrtl→verilator 全链 | CPU 单元测试可以只用 Verilator，**不占 `fpga-zynq-build-sbt` 租约**，与 SoC 集成解耦 |
| 上板（M3+） | 经 firrtl 产出 Verilog | 直接给 Vivado，少一层 |
| 风险 | 旧 Chisel 的坑会持续消耗 | 需要手写位宽/复位纪律；BlackBox 端口名必须与封装一致（用一个生成脚本或注释锁定） |

**推荐 B**，理由是迭代成本：CPU 会改几十轮，A 每轮都要付 sbt 代价并抢租约。工具兼容性证据在本地：M1-a 的模型已经把 Verilog 源文件与 Chisel 生成的 RTL 一起交给 Verilator 并跑通 hello.riscv（`experiments/teaching-cpu/m1/evidence/hello-run.log`）。**[决策 D1]**

## 2. 顶层与接口

```
            ┌──────────────── TeachingCpu (Verilog) ────────────────┐
 clk/rst ──►│  PC / regfile[31] / CSR file / 多周期 FSM             │
            │                                                       │
            │  req.valid/ready, addr[31:0], write, size[1:0],       │──► PHYSICAL_PORT_V1 ──► ReqRespToTL ──► SoC
            │  wdata[63:0], wmask[7:0]                              │
            │  resp.valid/ready, rdata[63:0], error                 │◄──
            │  irq_msip, irq_mtip, irq_meip (输入，M2-b 起用)        │
            │  commit_valid, commit_pc[63:0], commit_insn[31:0] (观测) │
            └───────────────────────────────────────────────────────┘
```
- CPU 不实现 TileLink/AXI，一切访存走物理口；取指、数据、将来的页表遍历**串行复用**同一口，任何时刻至多一笔在途。
- `resp.ready` 恒 1（单在途下消费者总能收），但**桥必须按握手保持**——这条在 M1-b 已有断言与故障对照守着。

## 3. 多周期状态机（首版，M-mode 裸机）

```
RESET ──► IF_REQ ──► IF_WAIT ──► (IF2_REQ ──► IF2_WAIT)? ──► DECODE ──► EX
                                                                        │
             ┌──────────────────────────────────────────────┬───────────┤
             ▼                                              ▼           ▼
          MEM_REQ ──► MEM_WAIT ──► WB                      WB         TRAP ──► IF_REQ
```
- **IF**：按 `pc[2:0]` 对齐到 8 字节发一次 `size=3` 读，取回的 beat 里按半字选指令。若 32 位指令跨 8 字节边界（`pc[2:1]==3` 且低半字的低 2 位为 `11`），再发一次 IF2 取下一个 beat 拼接。**C 扩展的半字对齐、跨 beat、跨页三种情况在此集中处理**（跨页故障的 PC 归属见 §6）。
- **请求快照**：进入 `*_REQ` 时把 `{addr, write, size, wdata, wmask}` 锁存进请求寄存器，`valid` 由状态驱动，握手前不变、不撤回（契约要求，M1-b 的 fault1 就是这条的反例）。
- **物理地址范围检查（不得截断）**：有效地址与 PC 在内部是 64 位，物理口只有 `addr[31:0]`。**进入物理口之前必须检查 `addr[63:32]`**：非零即产生访问故障（取指 1 / load 5 / store 7），`mtval` = 完整 64 位地址，**且不发出任何总线请求**。直接截断会造成地址别名（`0x1_8000_0000` 被当成 `0x8000_0000`），这是安全与调试上的静默错误。当前 SoC 的物理空间上界见 M1-soc 的地址图。
- **跳转目标对齐**：无 C 时，`jal`/`jalr`/分支的目标若 `target[1] != 0` → 指令地址未对齐异常（cause 0），`mepc` = **跳转指令自身**的地址、`mtval` = 目标地址（规范要求在跳转处报告，而不是在目标处取指时报告）。有 C 后只检查 `target[0]`，而 `jalr` 本就清除最低位，故实际只剩分支/`jal` 的立即数编码保证对齐。
- **整 beat 取指的越界风险**：IF 一次读 8 字节，PC 位于 beat 末尾时会带回 PC 之后的字节。在无 MMU 的 M-mode 裸机下无害，但 (a) 该 beat 可能落在 MMIO 上（读副作用！），(b) 有 MMU 后可能跨页触发本不该发生的故障。**约束**：IF 的 beat 不得跨越 4 KB 边界（跨界时退化为按半字/字取），且不得对已知 MMIO 区域做整 beat 过取——这两条在首版就按"PC 与 beat 同页"实现，避免 S3 再重构。
- **load 扩展 / store 通道**：桥只按字节通道搬运，**移位与符号扩展由 CPU 做**。load：`rdata >> (8*addr[2:0])` 后按 `funct3` 截断/符号扩展；store：`wdata << (8*addr[2:0])`，`wmask = ((1<<(1<<size))-1) << addr[2:0]`。
- **架构更新的两条互斥路径**：`WB`（正常退休）与 `TRAP`（陷入）**都**会改 PC/CSR，二者互斥、每条指令至多走其一。`WB` 写寄存器堆、按指令语义写 CSR、`pc ← pc + len`（或跳转目标）、`minstret++`；`TRAP` 不写寄存器堆、不增 `minstret`，只写 `mepc/mcause/mtval/mstatus` 并 `pc ← mtvec`。原先"WB 是唯一改 PC/CSR 的状态"的说法与 TRAP 冲突，已按此更正。`commit_valid` 只在 WB 那一拍为 1，`minstret` 也只在这里加；陷入走 `trap_valid`，两者**不会同拍为 1**——这是 RW1–R1 那批实验里踩过的坑（WB 停顿期间重复计数），提交记录字段就是为了让测试能逐条比对而不是靠计数器自证。
- **异常**：所有同步异常在 `TRAP` 状态统一处理：写 `mepc`（**出错指令自身的地址**）、`mcause`、`mtval`，`mstatus.MPP/MPIE` 压栈，PC ← `mtvec`。访存异常必须在**发出总线请求之前**判定（未对齐、将来的权限/翻译），总线返回的 `error` 则映射为访问故障（取指 1 / load 5 / store 7）——后者发生时写副作用可能已经发生，与 Rocket 行为一致（M0 §10）。
- **中断接受时机**：只在**指令边界**（WB 完成后、下一条 IF 之前）且**没有在途访存**时接受。这条不是新发明：RW9 在 Sodor 上实测过，中断在保持型请求的承诺期内被接受会导致"访存已发出、指令被杀"（`HoldD: request accepted without a free, non-killed WB slot`，`experiments/counter-baseline/CLAUDE_RW10.md`）。

## 4. 提交记录（观测口，非架构状态）

| 字段 | 宽度 | 含义 |
|---|---|---|
| `commit_valid` | 1 | 该拍提交了一条指令（WB 唯一一拍） |
| `commit_pc` | 64 | 提交指令的 PC |
| `commit_insn` | 32 | 指令编码（压缩指令为展开前的 16 位零扩展，另给 `commit_compressed`） |
| `commit_rd` / `commit_rd_valid` / `commit_rd_data` | 5/1/64 | 写回的寄存器与值（`rd=x0` 时 `rd_valid=0`） |
| `trap_valid` | 1 | 该拍进入陷入（与 `commit_valid` 互斥，**不增 `minstret`**） |
| `trap_interrupt` | 1 | 该次陷入是中断而非异常（独立位，不塞进 cause 的最高位） |
| `trap_cause` | 64 | 完整 `mcause` 宽度的原因码（5 位放不下中断标识，也放不下将来的自定义 cause） |
| `trap_epc` / `trap_tval` | 64/64 | 写入 `mepc` / `mtval` 的值 |

用途：单元测试逐条比对、与参考路径对齐、以及"一条指令只提交一次"的自动门禁。**不得**用它替代架构状态检查。

## 5. 复位与启动

复位后 `pc = 0x10040`（BootROM 的 `_hang`，M0 已用 `BootROM.scala` + 生成 RTL `s2_pc <= 40'h10040` 双重证据确认），`mhartid = 0`，特权 M，`mstatus.MIE = 0`。启动链要求 CPU 支持：`csrw mtvec/mie/mideleg/mstatus/mepc`、`csrr mhartid`、`wfi`（可实现为 NOP，但**之后必须仍能接受 MSIP**）、`mret`、以及对 CLINT 的 `lw/sw`。这些在 `bootrom.rv64.img` 的反汇编里逐条可见（M0 §4）。

## 6. 明确留到后续阶段的设计点（不在首版实现，但接口要留好）
- **跨页取指**：首版无 MMU，不会发生；实现 Sv39 时，IF2 的第二个 beat 可能落在另一页，故障的 `mepc` 必须是**指令起始地址**而非第二个 beat 的地址，`mtval` 为触发故障的地址。IF 状态机现在就把"两个 beat 各自的地址"分开保存，避免届时重构。
- **页表遍历**：复用同一物理口，插在 IF/MEM 之前的 `PTW` 子状态机；首版不实现，但状态机的请求快照/仲裁已经是串行的，加进去不改变接口。
- **原子**：见待裁定清单 D5。
