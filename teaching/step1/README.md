# 第 1 步：第一条指令退休

目标：一个能取指、执行 `addi` / `auipc` / `sd` / `jal`、并通过 tohost 报告结果的四态核。做完这一步，
波形里能看到你的核发出第一个请求、收到第一个响应、把第一个字写进内存。

## 做什么

1. 把 `tcpu_core_skeleton.v` 复制为 `teaching/work/cpu/tcpu_core.v`，把 `rtl/cpu/tcpu_regfile.v` 复制到同一目录
   （寄存器堆给定：x0 读 0、写入丢弃，这是第 2 步的变异体要检查的性质）。
2. 填骨架里的 TODO。模块名、参数、端口一个都不能动，harness 按它们实例化。
3. `make step1` 直到 `RESULT PASS`，三种时序（立即应答、固定延迟、随机延迟）都要过。
4. 实现 `REQ_WITHDRAW` 这个故障开关（见下），`make step1-mutants` 要看到监视器抓住它。

## 状态

```
S_IF_REQ ──> S_IF_WAIT ──> S_EXEC ──> S_WB ──> S_IF_REQ
                                 └──> S_MEM_WAIT ──> S_WB      (只有 sd 走这条)
```

| 状态 | 这一拍做什么 |
| --- | --- |
| S_IF_REQ | 把 `pc` 挂上端口：`valid = 1`、`addr = pc[31:0]`、`write = 0`、`size = 2`、`wdata = 0`、`wmask = 0` |
| S_IF_WAIT | 看到 `req_ready` 才拉低 valid，早一拍都是违约；看到 `resp_valid` 用 `pc[2]` 从 64 位里挑出 32 位指令 |
| S_EXEC | 译码；算 `wb_value` 和 `npc`；`sd` 在这里发写请求，地址 `rs1 + imm_s`，`size = 3`，`wmask = 8'hff` |
| S_MEM_WAIT | 同 S_IF_WAIT 的握手规则；响应到了去 S_WB |
| S_WB | 调度寄存器写、更新 pc、在 commit 端口报告这条指令 |

端口上的每个信号都来自寄存器（骨架已经这样写了）。这是"请求保持到握手"最简单的实现方式：你只在两个地方改它，
挂上的那一拍和看到 ready 的那一拍。

## 测试程序

`s1_tohost.S` 只用这四条指令：算 2 + 3 − 5 + 1 = 1，用 `auipc + addi` 取 tohost 的地址，`sd` 写进去，`jal` 自旋。
值 1 就是 code 0。`addi` 错了，值就不是 1，日志会告诉你解码出的 code 是多少。

地址用 `auipc` 而不是 `lui`：镜像在 `0x8000_0000`，`lui` 会把它符号扩展成 `0xFFFF_FFFF_8000_0000`，
一个正确的核必须拒绝这种地址（第 3 步的 d01 测这个）。

## 变异体：REQ_WITHDRAW

参数 `REQ_WITHDRAW = 1` 时，核在 S_IF_WAIT 里第一次看到 `req_ready` 为 0 就把 valid 拉低一拍，然后再挂回去。
这是对契约的蓄意违反。`make step1-mutants` 用 `READY_DELAY = 2` 保证 ready 会晚到，监视器必须打出：

```
PROTO ERROR: request withdrawn before the handshake
```

并且运行结果是 FAIL。程序本身仍然会写 tohost，所以这个 FAIL 完全来自监视器。这一步要你明白：
**违约的核也能算出正确答案，所以答案对不等于核对。**

## 验收

- `make step1`：三个 `ok`。
- `make step1-mutants`：一个 `ok`（即运行按预期 FAIL 且日志含那条错误）。
- 日志里 6 行 `COMMIT`，顺序是四条 `addi`、`auipc`、`addi`，`x10` 最后是 1，`x5` 是 tohost 的地址。
- `proto_errors = 0`、`obs_errors = 0`。

## 常见的坑

- 读请求带了 `wdata` 或 `wmask`：监视器报 `read request carried a write payload`。
- 在看到 ready 之前就拉低 valid，或者等待时改了地址：`request withdrawn` / `payload changed`。
- `commit_rd_data` 和寄存器堆里下一拍的值不一致：`OBS ERROR`。最常见的原因是 commit 报了一个值，寄存器写的是另一个。
- `jal` 的链接值是 `pc + 4`，目标是 `pc + imm_j`；两者都在 S_EXEC 算好，S_WB 只负责落地。
- 64 位响应里取哪一半：`pc[2]` 为 1 取高 32 位。

参考核跑这个测试要 93 拍，你的 4 字节取指版本应该在 50 拍左右：参考核每条指令取两个 16 位 parcel，
那是第 12 步才会解释的事。
