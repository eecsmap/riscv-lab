# teaching/ — 按步骤实现教学核的作业包

路线见 [`docs/TEACHING-PLAN.md`](../docs/TEACHING-PLAN.md)。这里是每一步的测试程序、运行脚本和学生起点文件。

## 运行

```sh
cd teaching
make step1                         # 跑你的核：teaching/work/cpu/*.v
make step1-mutants                 # 跑这一步必须抓住的故障注入
make step1-all CORE=../rtl/cpu     # 用参考核跑同样的东西（每一步参考核都必须通过）
```

依赖：`iverilog`、`python3`、任一 riscv64 GCC（自动识别 `riscv64-unknown-elf-`、`riscv64-elf-`、
`riscv64-linux-gnu-`，或 `TOOLPREFIX=/path/to/riscv64-unknown-elf-`）。

## 固定接口

三样东西整门课不变，harness 会强制检查：

| 接口 | 规则 |
| --- | --- |
| PHYSICAL_PORT | 单发；请求挂上后 valid 和 payload 保持到握手；读请求 wdata = 0、wmask = 0；响应不早于握手后一拍；`resp_ready` 恒 1 |
| tohost | 程序结束时向 `tohost` 写 `(code << 1) \| 1`，code 0 为 PASS |
| 观测端口 | 每拍至多一次 commit 或一次 trap，不能同时；`commit_rd_data` 必须等于下一拍寄存器堆里真实的值 |

harness 在 `tests/cpu/tb/tcpu_harness.v`：内存模型、时序配置（`READY_DELAY`、`RESP_DELAY`、`RANDOM`）、
协议监视器、故障与中断注入都在里面，学生不改它。

## 一次运行产生什么

`teaching/out/<step>/<test>.<tag>.log`，内容是：`PARAMS` 一行记录本次的参数；每条退休一行 `COMMIT`，每次 trap 一行
`TRAP`；`PROTO ERROR` / `OBS ERROR` 是监视器的报告；最后 `SUMMARY`、`TOHOST code=N`、`RESULT PASS|FAIL`。
判 PASS 需要同时满足：code 0、`proto_errors = 0`、`obs_errors = 0`、至少一次退休。超时也是 FAIL。
`VCD=1 make step1` 另存波形到同目录。

## 变异体

每一步的 `stepN-mutants` 用参数打开一个已知缺陷，要求运行**失败**，并且日志里出现指定的那条错误。缺陷没被抓到、
或者被别的原因抓到，都算这一步没过。一个不会失败的测试什么都没证明。
