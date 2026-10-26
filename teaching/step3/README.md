# 第 3 步：同步异常、M 级 CSR、mret

目标：让核在出错时按架构规定的方式停下来、记录现场、跳到处理程序，并能回来。做完这一步，核第一次能运行一个
"程序 + 处理程序"的组合，这是操作系统内核态的最小形态。

这一步的唯一新机制是 **S_ARCH 空拍**，以及一条纪律：**先判合法，再产生副作用**。一条非法指令、一次未对齐访问、
一个越界地址，都要在发出任何总线请求、写任何寄存器之前被判定并转入 S_TRAP。

## 做什么

| 组 | 内容 |
| --- | --- |
| 状态 | 新增 S_TRAP、S_ARCH、S_HALT；S_WB 之后经 S_ARCH 回 S_IF_REQ；S_TRAP 也经 S_ARCH |
| 同步异常 | 非法指令 2、取指未对齐 0、取指访问错误 1、load 未对齐 4、load 访问错误 5、store 未对齐 6、store 访问错误 7、ecall 11、ebreak 3 |
| 现场 | mepc = 出错指令的 pc；mtval 按原因：非法指令是编码，未对齐和访问错误是地址，ebreak 是自己的 pc，ecall 是 0 |
| CSR | mstatus（MIE、MPIE、MPP 恒 3）、misa、mtvec、mepc、mcause、mtval、mscratch、mhartid、mcycle、minstret、cycle、instret |
| Zicsr | csrrw / csrrs / csrrc 及三个立即数形式；写意图由编码决定，读意图只对 csrrw 看 rd |
| 返回 | mret：pc ← mepc，MIE ← MPIE，MPIE ← 1 |
| 计数 | mcycle 每拍加一；minstret 只在 S_WB 退休时加一，trap 不算；软件写计数器时软件的值胜 |
| 观测 | trap_valid、trap_cause、trap_epc、trap_tval；dbg_csr_sel 的回读口；STOP_ON_TRAP 参数让第一次 trap 后进 S_HALT 并拉高 halted |

还有三个故障开关：`TRAP_BAD_MEPC`（mepc 记成下一条指令）、`TRAP_COUNTS_RET`（trap 也让 minstret 加一）、
`ALLOW_RO_WRITE`（对只读 CSR 的写不报非法）。

## 为什么是 S_ARCH

S_WB 把寄存器写、CSR 写、pc 更新**调度**出去，它们在 S_WB 之后那一拍的末尾才**落地**。第 1、2 步那一拍恰好是
S_IF_REQ，它只读 pc，所以没出事。从这一步起 S_IF_REQ 之后要读的东西多了：trap 要写 mepc、mcause、mstatus，
下一次取指用的 pc 来自 mtvec；mret 要读 mepc；第 4 步还要在 S_IF_REQ 采样 MIE。让它们在一个什么都不决定的
空拍里落地，之后的每个决定都建立在已经生效的状态上。`STALE_MIE` 变异体在第 4 步会演示少了这一拍的后果。

## 测试

```sh
make step3            # 24 次运行
make step3-mutants    # 3 个变异体
```

| 测试 | 查什么 | 结束方式 |
| --- | --- | --- |
| d01 | 高 32 位非零的地址不能被截断：cause 7，总线上零次数据请求 | trap 停机 |
| d02 | 未对齐 load 在发请求之前 trap：cause 4，零次数据请求 | trap 停机 |
| d04 | 未实现的编码 cause 2，并且不出现在 commit 流里 | trap 停机 |
| d05 ×7 | jalr 的 7 种非法 funct3：cause 2，链接寄存器 x9 原封不动 | trap 停机 |
| d07 | 读不存在的 CSR（`time`）是非法指令，不能编一个值 | trap 停机 |
| d09 | 跳到 32 位物理空间之外：jalr 正常退休，下一次取指报 cause 1，tval 是那个地址，零次数据请求（学生编写） | trap 停机 |
| d08 | 真实实现的 minstret 和 instret 能读、在走 | tohost |
| c01 | 六种 Zicsr 形式和写意图规则 | tohost |
| c02 | WARL：mtvec、mepc、mstatus、misa、mhartid 的读回值 | tohost |
| c03 | 必须报非法的 CSR 访问：写只读 CSR、`csrrs` 带非零寄存器号、不存在的地址 | tohost |
| c04 | mcycle 和 minstret 的计数与可写 | tohost |
| c05 | mret 计入退休，出错指令不计 | tohost |
| c06 | 跳转目标对齐：取到 2 字节对齐目标 cause 0，mtval 是目标；不取的分支不看目标 | tohost |
| c08 | 三种访问错误来自总线的 error 响应，不是核内的范围检查 | tohost |
| c09 | ecall、ebreak 是异常不是退休，mtval 各自的规则，commit 流里不出现 | tohost |
| c10 | trap 不是退休：minstret 的差恰好是 4；另跑一次随机时序 | tohost |
| c07 | **反向测试**：handler 每次进入都 fault，运行必须被 TRAP STORM 拒绝 | 期望 FAIL |

d 系列用 `STOP_ON_TRAP=1` 和 `+expect_trap=<cause>`：第一次 trap 后核停机，testbench 以 cause 判定，
再用 grep 查附加性质（`HALT ... data_requests=0`、`REG x9=...`、commit 流里没有某条编码）。
c 系列链接 `tests/cpu/tests2/thandler.S`：共享 handler 记录 mcause、mepc、mtval 和 trap 次数，从 mepc + 4 恢复。

### 期望随扩展变化的三个测试

c02、c03、c06 的期望取决于核有没有 C、S、M：没有 C 时 mepc 低两位清零、2 字节对齐的跳转目标要 trap；
有 S 时 mstatus 多出一组可写位、misa 多出 S 和 U。`teaching/step3/` 里的版本用 `-DHAS_C`、`-DHAS_S`、`-DHAS_M`
选择期望。学生的核默认一个都没有；参考核由 Makefile 自动加全部；到第 6 步你自己加 `ISA_FLAGS="-DHAS_S"`，
第 12 步再加 `-DHAS_C`。同一份测试跟着核一起演进，这比"换一套测试"更能说明到底改了什么。

## 杀死矩阵

三个变异体对全部 23 次运行的结果（参考核）：

| 变异体 | 被谁杀死 | 没被谁杀死 |
| --- | --- | --- |
| `TRAP_BAD_MEPC` | c03、c08、c09、c10：handler 从错误的 mepc 恢复，多跳过一条指令，trap 之后的第一个检查就失败 | d 系列（它们在第一次 trap 就停机，不看 mepc）、c01、c02、c04、c05、c06 |
| `TRAP_COUNTS_RET` | 只有 c10：minstret 的差从 4 变成 5 | 其他全部 |
| `ALLOW_RO_WRITE` | 只有 c03：`csrw cycle` 没有 trap | 其他全部 |

后两个变异体各只被一个测试杀死，意味着那个测试一旦坏掉，对应的缺陷就没人看守。这是测试轨道 V3 的材料。

## 常见的坑

- 判断顺序。S_EXEC 里的 if 链是优先级：非法指令 → 未对齐 → 地址越界 → 目标未对齐 → 发请求。顺序错了，
  d01、d02 的 `data_requests` 不为 0。
- 写了寄存器再 trap。出错指令不能有任何架构效果：`wb_we` 必须为 0，commit_valid 不能高。d05 查 x9。
- minstret 在 trap 时加了一：c10。
- CSR 读改写的原子性：`csrrs` 的读值和写值要在同一拍，否则 c04 里"软件写胜过自增"会失败。
- mret 之后直接回 S_IF_REQ 而不经 S_ARCH：第 3 步看不出来，第 4 步的中断测试会把它翻出来。
- `misa` 的值：这一步是 `0x8000000000000100`，MXL = 2 加 I。多报一个扩展就是 c02 code 5。
