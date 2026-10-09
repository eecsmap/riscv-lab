# 教学路线：从第一条指令到跑通 xv6 的多周期 RV64 核

状态更新于 2026-10-09。分支 `teach-rv64ia`。这份文件是路线的唯一权威版本，每一步完成后在"状态"列更新，
并链接证据目录。历史讨论里的旧版本（M、C 在 xv6 之前）作废。

## 总体原则

1. **先给合同，再给自由。** 第一天交给学生三样固定接口，整门课不改：PHYSICAL_PORT 契约（单发、请求保持到握手、
   响应不早于握手后一拍、`resp_ready` 恒 1）、tohost 退出协议、commit/trap 观测端口。harness、监视器、SoC 桥
   全部预先给定，学生只写核心。
2. **每一步两种验收。** 定向测试通过，**并且**指定的故障注入参数必须让测试失败。一个不会失败的测试什么都没证明。
   harness 里现成的 `X0_WRITABLE`、`TRAP_BAD_MEPC`、`EARLY_IRQ` 等参数就是变异体。
3. **一步只引入一个新机制。** 新指令不算新机制；新的状态、新的子模块握手、新的端口字段才算。
4. **xv6 之前不需要 M 和 C。** 内核与用户程序用 RV64IA + Zicsr + Zifencei 构建（见 §4）。M 和 C 放在 xv6 之后，
   作为可以在同一负载上 A/B 测量的扩展。
5. **取指从 4 字节对齐开始。** 第 1 到第 11 步的取指路径不变：`req_size = 2`，没有 `insn_len`、`pc2` 和
   第二个 parcel。第 12 步加 C 时才改成 parcel 取指，学生会亲手量到两种取指差一倍的 CPI。

文件切分即写作顺序：`tcpu_core.v` 与 `tcpu_regfile.v` 先写，`tcpu_csr.v`、`tcpu_ptw.v`、`tcpu_muldiv.v`、
`tcpu_cdecode.v` 依次加入。

## 十二步

| 步 | 内容 | 唯一的新机制 | 验收 | 必须失败的变异体 | 状态 |
| --- | --- | --- | --- | --- | --- |
| 1 | 4 字节取指；addi / lui / sd / jal；S_IF_REQ、S_IF_WAIT、S_EXEC、S_WB 四态 | ready/valid 握手，请求保持到握手 | 程序把常数写进 tohost，harness 报 PASS | `REQ_WITHDRAW` 触发端口监视器 | 待做 |
| 2 | 完整 RV64I：W 后缀、六种分支、jalr、全宽度 load/store、fence、fence.i | S_MEM_WAIT 与字节通道移位 | t01 算术、t02 分支、t03 访存（学生写）；d03、d06 | `X0_WRITABLE`、`NO_LOAD_SEXT` | 待做 |
| 3 | 同步异常；M 级 CSR 最小集；六种 Zicsr；ecall / ebreak / mret；S_TRAP、S_ARCH | S_ARCH 空拍；先判合法再产生副作用 | d01、d02、d04、d05、d07、d08；c01 到 c10 | `TRAP_BAD_MEPC`、`TRAP_COUNTS_RET`、`ALLOW_RO_WRITE` | 待做 |
| 4 | mie / mip、三根中断线、wfi | 中断只在 S_IF_REQ 采样 | i01 到 i09、j01、j02；`IRQ_POINT` 十二个注入点 | `EARLY_IRQ`、`STALE_MIE`、`IRQ_BAD_MEPC` | 待做 |
| 5 | 进入 RD2 SoC 仿真：桥、TileLink、CLINT、HTIF 控制台（Scala 产物给定） | 地址映射与复位向量 0x10040 | boot01 到 boot04 | 无，这步是集成 | 待做 |
| 6 | S/U 特权、medeleg / mideleg、sret、sfence.vma 空操作、计数器门控 | 同一组触发器的两个视图 | M→S→U→ecall→sret 往返程序（需补写） | `FAULT_NO_DELEG`、`FAULT_S_IRQ_IN_M`、`FAULT_SRET_SPP` | 待做 |
| 7 | Sv39 walker、S_XLATE、端口 mux、satp / SUM / MXR / MPRV | 端口在两个主人之间切换 | ext04_sv39 | `FAULT_PTW_NO_PERM`、`FAULT_PPN_TRUNC` | 待做 |
| 8 | A 扩展，端口升级 V2（amo / lrsc / scfail / resv_clear），AtomicBackend 给定 | SC 成败由存储器侧决定 | ext03_a | 五个 `FAULT_A_*` | 待做 |
| 9 | 启动 xv6，RV64IA 镜像 | 无 | `check-xv6.py`：banner、提示符、echo / ls / cat / 管道 | 无 | **软件侧完成**（§4），基准核仿真通过 |
| 10 | 上板 PYNQ-Z1：Vivado 构建、冷启动、8 个启动门、perf 探针 | 板级安全规程（`docs/BOARD.md`） | xv6 到提示符；perf01 到 perf06 对上基线表 | 无 | 待做 |
| 11 | M 扩展：`tcpu_muldiv.v`、S_MUL | start / busy / done 子模块握手 | ext01_m；同一 xv6 负载软除法 vs 硬件除法的 mtime 对比 | `FAULT_W_SEXT`、`FAULT_MULH_SIGN` | 待做 |
| 12 | C 扩展：`tcpu_cdecode.v`，parcel 取指，S_IF2_REQ / S_IF2_WAIT，`insn_len`、`pc2` | 一条指令跨两次请求时的故障归属 | ext02_c；perf03 量 16 位 vs 32 位 CPI | `FAULT_C_IMM`、`FAULT_C_REG`、`FAULT_IF2_NO_XLATE`、`FETCH_ERR_ADDR` 对准第二个 parcel | 待做 |

第 12 步之后，IPS 实验的 fetch32、TLB、I-cache 三个阶段（`experiments/IPS-campaign/`）可以直接作为下一门课或
大作业，每一阶段都有已验收的参考数字。

### 每一步学生看到的成就

| 步 | 成就 |
| --- | --- |
| 1 | 波形里自己的核发出第一个请求、收到第一个响应、写进第一个字 |
| 3 | trap 处理程序第一次接管控制流再返回 |
| 4 | 打开 `STALE_MIE` 亲眼看到同一个中断被取两次，关掉后消失 |
| 5 | 第一次在"系统"里打印出一行字 |
| 7 | perf02 量到 4 KiB 页的 CPI 是裸机的四倍，TLB 的全部动机 |
| 9 | `$` 提示符 |
| 11 | 同一条 `ls`，加 M 前后的 mtime 差 |
| 12 | C 在这个核上既省指令又多一次往返，引出 fetch32 |

## 发给学生的东西 vs 学生自己写的东西

| 给定 | 学生写 |
| --- | --- |
| `tests/cpu/tb/tcpu_harness.v`（内存模型、故障注入、中断注入、端口监视器） | `rtl/cpu/tcpu_core.v` |
| `tests/cpu/tests`、`tests2`、`m3tests` 的测试程序与宏 | `rtl/cpu/tcpu_regfile.v` |
| `software/probes/ext0x_*.S`、`perf0x_*.S` | `rtl/cpu/tcpu_csr.v`（第 3 步起） |
| RD2 SoC 生成好的 Verilog 与 Verilator 仿真器（第 5 步起） | `rtl/cpu/tcpu_ptw.v`（第 7 步） |
| `software/xv6` 的 RV64IA 构建（§4） | `rtl/cpu/tcpu_muldiv.v`（第 11 步） |
| 基准核本身，仅教师持有，用作差分 oracle | `rtl/cpu/tcpu_cdecode.v`（第 12 步） |

## §4 第 9 步的软件侧：RV64IA 的 xv6（已完成，提交 cb1ec42）

与 xv6-sim 基线的源码偏差一共四处，`software/xv6/Makefile` 的注释块逐条列出，不允许有第五处：

| 偏差 | 原因 |
| --- | --- |
| `TEACHING_NO_PMP`（原有） | 教学核没有 PMP |
| `kernel/entry.S`：`mul a0,a0,a1` → `slli a0,a1,12` | 内核里唯一一条真正的乘法指令，hartid 乘 4096 |
| `kernel/printk.c`：printint 用移位减法除法 | `x / base`、`x % base` 是内核里仅有的变量操作数除法；其余乘除模都是常量操作数，编译器自己变成移位加法 |
| `user/softmath.c`：`__muldi3 __divdi3 __moddi3 __udivdi3 __umoddi3` 及 32 位变体，进 ULIB | 用户程序的乘除在 xv6 框架内实现，不链 libgcc；除零与 MIN/-1 按 M 扩展语义，软硬件行为一致 |

构建：`make xv6`（根 Makefile）或 `make -C software/xv6 kernel/kernel fs.img CPPFLAGS=-DTEACHING_SIM_MEM_MIB=128`。
`-march=rv64ia_zicsr_zifencei -mabi=lp64`，ABI 必须显式，`riscv64-linux-gnu-gcc` 默认 lp64d。

验收身份（gcc 15.2，两台机器逐字节一致）：

| 项 | 值 |
| --- | --- |
| `kernel/kernel` sha256 | `7073e286de6f8cc5c4bc2d13cf0905cdca94ecc454cb2755acba768d8c29f2bd` |
| `fs.img` sha256 | `848bcf991329c8af4188ddf94e3b2c0653b5f9566c2956a962cc8d2065338210` |
| 内核 mul/div/rem、压缩指令、未定义符号 | 0 / 0 / 0 |
| 21 个用户程序 mul/div/rem、未定义符号 | 0 / 0 |
| arch 标签 | `rv64i2p1_a2p1_zicsr2p0_zifencei2p0` |

检查命令：

```sh
PAT='^\s+[0-9a-f]+:\s+[0-9a-f]+\s+(mul|mulw|mulh|mulhu|mulhsu|div|divu|rem|remu|divw|divuw|remw|remuw)\s'
riscv64-linux-gnu-objdump -d software/xv6/kernel/kernel | grep -cE "$PAT"      # 0
riscv64-linux-gnu-nm software/xv6/kernel/kernel | grep -c ' U '                 # 0
riscv64-linux-gnu-readelf -A software/xv6/kernel/kernel | grep Tag_RISCV_arch
```

**基准核仿真结果，2026-10-08**，多周期单核 RD2 仿真器（`experiments/multicore/m3/runs/sim-single`），
`xv6-drive.py --max-cycles 2000000000`，默认 `--stage-timeout 900`：

| 阶段 | 墙钟 |
| --- | --- |
| banner | 4.2 s |
| 第一个提示符 | 1074.5 s（超过 900 s 的阶段超时，被驱动记为 1 个 failed，功能上通过） |
| echo | 63 s |
| ls | 781 s |
| cat README | 79 s |
| echo abc 加 wc | 119 s |
| 结束 | `XV6_DRIVE stages=7 failed=1 sim_exit=0 (deliberate-stop-after-all-commands)` |

ls 慢一个数量级，推测是每个数字的每一位都走一次 softmath 的 64 步除法；这是第 11 步最直观的对照。重跑时加
`--stage-timeout 1800` 可得干净的 7/7。原始日志目录待归档到 `experiments/teaching/xv6-rv64ia/`。

## 缺口

| 需要 | 现状 |
| --- | --- |
| 第 2 步的 t01 到 t03 与 `testmac.h` | 未提交，d 系列测试引用了它 |
| 第 6 步的 S/U 往返测试程序 | 只有 `docs/archive/cpu-su-prep/TEST_PLAN.md` |
| 按步运行的脚本 `make test-step N` | 没有；harness 的编译命令也没留下 |
| 预编译的 RD2 仿真器分发 | 需要旧版 rocket-chip 工具链生成一次 |
| 第 9 步证据归档与 `check-xv6.py` 的期望值 | 期望值仍指向被验收的 `6ad5c233…` 镜像，需为教学基线另开一份 |

## 测量数据的来源

路线里引用的数字都来自实板或仿真记录：B0 基线表（`benchmarks/baselines/B0/REPORT.md`）、IPS 四阶段对比
（tag `ips-v1-icache` 的 `experiments/IPS-campaign/FINAL-COMPARISON.md`）、流水线板上报告
（tag `pipe-v1-dual` 的 `experiments/pipeline/p3/board/REPORT.md`）。板上一次 DRAM 往返约 18 拍，
核心固定开销约 4 拍，32 位指令两次取指往返是 CPI 40 的来源。
