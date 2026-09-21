# M2 裸机验证计划（Claude，2026-09-15）

## 1. 已经实际跑通的部分（不是计划，是本轮结果）

`tests/` 下 6 个测试 × 2 种 ISA 变体 = **12 个 ELF**，全部在 **M1-a 已验收的 Rocket Verilator 模型**上按各自的期望退出码通过（同一 ELF、同一 tohost 约定）。

| 测试 | 覆盖 | 期望退出码 | rv64i / rv64ic 周期 | 结果 |
|---|---|---|---|---|
| `t01_alu` | **x0 不可写**（见下）、64 位环绕、`addw/sraw` 的 32 位语义与符号扩展、`srli` vs `srai`、`slt/sltu`、逻辑、`lui` 符号扩展 | 0 | 1927 / 1584 | OK |
| `t01n_x0check` | **对 x0 检查结构本身的受控反例** | **1** | — | OK（按预期失败） |
| `t02_branch` | 六种分支取/不取、有符号 vs 无符号、`jal`/`jalr` 链接值、`jalr` 清最低位、后向循环次数 | 0 | 1584 / 1383 | OK |
| `t03_ldst` | 各宽度 load 的符号/零扩展、store 的字节通道隔离、各自然偏移 | 0 | 2061 / 1927 | OK |
| `t04_trap` | 非法指令、未对齐 load/store、`ecall`、`mepc` 精确指向出错指令、`mcause`、`mret`、`mscratch` 往返 | 0 | 1927 / 1718 | OK |
| `t05_roi` | **程序内定义的 ROI + 退休基准**（见 §1.2） | 0 | 1249 / 1249 | OK |

证据：`evidence/reference-run/`（逐例 `.exit`、日志尾、`elf.sha256`、`inputs.sha256`、`tools.txt`、`summary.txt`，`REFRUN_DONE fails=0`）。

### 1.1 x0 检查：原写法抓不到，已重写并给了受控反例

Codex 复核指出：`CHECK_EQ(x0, 0, 1)` 展开出的 `li a1, 0` 其实是 `addi a1, x0, 0`。如果 x0 真的可写并存了 5，那么 `a1` 也会读成 5，**两边同错、检查通过**。现改为 `CHECK_X0_ZERO`：用 `auipc t0, 0` 取一个与 x0 无关的值，`sub t1, t0, t0` 造出**真正的 0**，再 `add t2, x0, t1` 读 x0 并与 t1 比较；失败码也用 `sub/addi` 生成，避免坏掉的 x0 改变报告出来的编号。

`t01n_x0check` 是对**这套比较结构**的受控反例：同样的序列，但把 x0 换成一个故意置 5 的寄存器，因此**必须**以退出码 1 失败——实测正是 1。这证明该结构能看见非零值；**但它不是"x0 坏掉的核"的反例**，那需要被改坏的 CPU，属 M2-1 的故障注入（`NEXT_TASKS.md` 已列）。原先"检查号 1 一定会失败"的承诺已撤回。

### 1.2 退休基准：程序内 ROI，期望来自反汇编

`t05_roi` 在程序里用两条 `csrr minstret` 划出 ROI，中间是 `.option norvc` 固定编码的 3 指令循环 × 16 次。**期望值 49 = 3×16 + 1（收尾的 csrr 计入）由反汇编静态推导**，不来自被测计数器：`tests/expected-trace.py` 从 `.dis` 里解析循环体起止与分支目标，输出 `expected_retired=49` 与完整的 49 条 PC 轨迹（`evidence/reference-run/t05-expected-trace.txt`）。测试在参考核上通过，说明实测 `minstret` 增量与静态推导一致。

这解决了"共同 ROI"的问题：ROI 的边界在**软件里**，与宿主如何进入无关——参考路径是真实 TSI 启动，未来 CPU harness 是预载内存直接起跑，两者的全程周期/指令数不可比，但**这段 ROI 的退休数必须一致**。全程周期（上表）**不作为**任何基准，只是运行时间的参考。

## 2. 编译与结束约定

- `-march=rv64i_zicsr`（S1）与 `-march=rv64ic_zicsr`（S2），`-mabi=lp64`、`-mcmodel=medany`、`-nostdlib -nostartfiles -ffreestanding -O0 -Wa,--fatal-warnings`。
- 链接到 `0x8000_0000`（`tests/link.ld`），`.htif` 段 64 字节对齐放 `tohost`/`fromhost`。
- 结束：`tohost = (code << 1) | 1`，code 0 = 通过，否则是失败的检查号。**同一个 ELF 在两种宿主下都能判定**：(a) 参考路径由 fesvr 解析 tohost 并作为进程退出码；(b) 将来的 CPU harness 直接监视内存里的 `tohost` 地址。
- **两种入口必须分清**（Codex 要求）：本轮的参考运行是**真实 TSI 启动**（fesvr 经 TSI 写 DRAM → 写 CLINT MSIP → bootrom `mret`）；未来 M2 的 CPU 单元 harness 计划是**直接把 ELF 段预载进内存模型、复位后从 0x8000_0000 起跑**，不经 bootrom/TSI。两者的覆盖不同，报告里不得混称——真实启动链的验证要等 S2 的 bootrom 测试。

## 3. 参考结果的来源

| 来源 | 可用性 | 用法 |
|---|---|---|
| **现有 Rocket 模型**（M1-a） | ✅ 本地已验证 | 首选。同 ELF 跑出 PASS/失败码，作为金标准 |
| `qemu-system-riscv64` | ✅ 主机有（`/usr/bin`） | 备选；需要另配 `-machine virt -bios none`，tohost 语义不同，作为交叉验证而非主判据 |
| Spike | ❌ 无二进制，源码在 `rocket-chip/riscv-tools/riscv-isa-sim` | 需要现场构建；本轮**未**构建，不作为依据 |
| riscv-tests 官方套件 | 源码在 `riscv-tools/riscv-tests`（xv6 构建链已用其 env/macros） | S1 末期引入 `rv64ui-p-*`，届时用同一参考模型产出金标准 |

## 4. 精确门禁（按阶段）

**S1（RV64I 裸机，CPU 单元 harness）**
1. `t01`–`t03` 全绿，且**逐条提交比对**：`commit_pc` 序列与参考一致，`commit_rd_valid=0` 当 `rd=x0`。
2. 符号扩展与 32 位运算：`t01` 的 4/5/12 项（`addw`/`sraw`/`lui`）。
3. 跳转与链接值：`t02` 的 8/9 项。
4. 访存字节通道与符号扩展：`t03` 全部 11 项。
5. **背压稳定**：在 harness 的物理口上注入随机 `req.ready` 延迟与 `resp` 延迟，结果必须逐位相同（复用 M1-b 的延迟器思路）。
6. **访问故障**：对未映射地址读写 → `error` → mcause 1/5/7；写副作用的可见性按 SPEC §3 说明。
7. **未对齐** → mcause 4/6，且**不发出总线请求**。
8. **精确异常**：`t04` 的 mepc/mcause/mret 全部项。
9. **一条指令只提交一次**：在 `t05_roi` 的 ROI 内，`commit_valid` 的计数 == **静态推导的 49** == 参考核实测的 `minstret` 增量；`trap_valid` 与 `commit_valid` 不得同拍为 1，且陷入不增 `minstret`。期望值来自反汇编而非被测计数器（R1 那批实验的教训）。
10. **PA 越界与跳转对齐**（SPEC §3 新增）：地址高位非零 → 访问故障且**零总线请求**；无 C 时跳转目标 bit1 非零 → cause 0 且 `mepc` 指向跳转指令本身。两者各需一个定向用例（M2-2 一并验收）。

**S2（M/C/CSR/中断/真实启动）**：`rv64ui-p-*` 与 `rv64um-p-*` 子集；压缩指令的半字对齐与跨 beat 取指定向用例；CLINT 定时中断（mtimecmp → mtip → 指令边界接受）；**从 0x10040 起的真实 bootrom 启动**（这一项才能声称"启动链走通"）。

**S3（S/U/Sv39）**：`rv64si-p-*`；页表遍历定向用例（各级、超级页不对齐、缺 A/D、非规范 VA）；最后才是 xv6 内核启动。

## 5. 复跑

```
bash experiments/teaching-cpu/m2-prep/tests/build.sh <outdir>                     # 编译 12 个 ELF + 哈希 + 工具版本（目录非空则拒绝，exit 2）
bash experiments/teaching-cpu/m2-prep/tests/reference-run.sh <sim> <elfdir> <out> # 在 Rocket 参考模型上跑（同样拒绝非空目录）
python3 experiments/teaching-cpu/m2-prep/tests/expected-trace.py <t05.dis> 16   # 静态推导 ROI 退休数与 PC 轨迹
```
`<sim>` = M1-a 的模型（`teaching-cpu-work/sim-20260914T213208Z/obj_dir/sim`，sha 记录在 `evidence/reference-run/inputs.sha256`）。
