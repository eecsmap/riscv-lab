# 第 2 步：完整 RV64I

目标：第 1 步的四态核扩成完整的 RV64I 整数核。指令集之外**不引入新状态**：load 走第 1 步 `sd` 已经用过的
S_MEM_WAIT，分支和跳转在 S_EXEC 里算目标。新机制只有一个：字节通道，也就是任意宽度的 load/store 在 8 字节字里
的位置、掩码和符号扩展。

## 做什么

在 `work/cpu/tcpu_core.v` 上继续，模块名、参数、端口不变。

| 组 | 指令 | 要点 |
| --- | --- | --- |
| 寄存器-立即数 | addi slti sltiu andi ori xori slli srli srai | 64 位移位量是 `insn[25:20]`，6 位 |
| W 立即数 | addiw slliw srliw sraiw | 对低 32 位运算，结果**符号扩展**到 64 位；W 移位量 5 位 |
| 寄存器-寄存器 | add sub sll slt sltu xor srl sra or and | 移位量取 `rs2[5:0]` |
| W 寄存器 | addw subw sllw srlw sraw | 同上，移位量取 `rs2[4:0]` |
| 上位立即数 | lui auipc | 立即数符号扩展到 64 位 |
| 跳转 | jal jalr | 链接值 `pc + 4`；jalr 目标 `(rs1 + imm) & ~1` |
| 分支 | beq bne blt bge bltu bgeu | 64 位比较；目标 `pc + imm_b` |
| 访存 | lb lh lw ld lbu lhu lwu sb sh sw sd | 见下节 |
| 屏障 | fence fence.i | 合法，退休一次，不做任何事 |

还要实现两个故障开关（`X0_WRITABLE` 在给定的寄存器堆里，不用管）：

- `NO_LOAD_SEXT != 0`：lb、lh、lw 的结果零扩展而不是符号扩展。
- `LOAD_WDATA_LEAK != 0`：load 发请求时把 `rs2_val` 当写数据放到 `req_wdata` 上。rs2 字段在 load 里是立即数的一部分，
  这个"缺陷"曾经是真实的（Codex 评审第 2 条），端口监视器就是为它加的那条规则。

## 字节通道

端口上的数据永远在**地址对应的字节通道**上，核不做搬运：

- load：响应是 pc 所在那个 8 字节字，`load_data = resp_rdata >> {addr[2:0], 3'b000}` 之后再按宽度截取、扩展。
- store：`req_wdata = rs2_val << {addr[2:0], 3'b000}`，`req_wmask = base_mask << addr[2:0]`，base_mask 按宽度是
  `0x01 / 0x03 / 0x0f / 0xff`。`req_size = funct3[1:0]`。
- 这一步只有对齐访问。未对齐是第 3 步的 trap。

## 测试

```sh
make step2            # t01 算术、t02 分支、t03 访存，各两种时序；加 d03、d06
make step2-mutants    # X0_WRITABLE 杀 t01 code 1；NO_LOAD_SEXT 杀 t03 code 2；LOAD_WDATA_LEAK 被监视器抓
```

测试用 `testmac.h` 的四个宏，每个检查一个唯一 code，失败时日志 `TOHOST code=N` 直接告诉你是哪个检查。
`main` 由 `tests/cpu/tests/dcrt.S` 的 `_start` 调用，`PASS` 跳到它的 `tt_exit`。

| 测试 | 查什么 | 退休数（参考核） |
| --- | --- | ---: |
| t01_alu | 43 个检查：x0、立即数、移位、W 形式、寄存器-寄存器、lui/auipc、fence | 187 |
| t02_branch | 六种分支的取与不取、64 位比较、回跳循环、jal/jalr 链接值、jalr 清 bit 0 | 89 |
| t03_ldst | 22 个检查：各宽度的符号/零扩展、负偏移、窄 store 只改自己的通道、相邻字不受影响 | 150 |
| d03_badbranch | 不取的分支不检查目标对齐 | 14 |
| d06_loadpayload | load 的 rs2 字段不能漏到总线上 | 26 |

参考核跑这些是上表的退休数；你的核应该一样，周期数大约是参考核的一半。

## 验收

- `make step2`：八个 ok。
- `make step2-mutants`：三个 ok，分别是 code 1、code 2 和那条 `read request carried a write payload`。

## 常见的坑

- W 指令的结果忘了符号扩展，或者用了 64 位的进位：t01 code 16、18、33、38。
- `sltu` 把 -1 当负数：code 26。
- 移位量用了 `imm[5:0]` 以外的位，或 W 移位用了 6 位：code 24、35。
- 符号扩展的 lw 和零扩展的 lwu 弄反：t03 code 8、9。
- store 数据没按地址移位，或掩码没移位：t03 code 13、14，而且会改坏相邻字节，code 21。
- jalr 的目标没清 bit 0：t02 code 16；链接值算成了目标：code 13、15。
- 第 1 步时序下过了、随机时序下不过：S_MEM_WAIT 里 `resp_valid` 的采样和第 1 步 IF_WAIT 一样，响应只有一拍。

## 关于 x0 测试的一个细节

`li gp, 0` 汇编成 `addi gp, x0, 0`。x0 一旦可写并且装进了脏值，之后所有常数都被污染，连失败 code 本身都会被加上
那个脏值。所以 t01 的 x0 检查先取期望、再写 x0、再用 `sub x0, x0, x0` 把它清零，然后才比较。
这是"测试自己也会被被测对象污染"的一个小例子，测试轨道 V0 会回到这里。
