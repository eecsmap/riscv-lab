# 第 3 步的 TODO：八块，按测试顺序加

## TODO 1：三个新状态和 halt

`S_TRAP = 4'd6`、`S_HALT = 4'd7`、`S_ARCH = 4'd8`（和基线、harness 一致）。S_WB 结尾改成 `state <= S_ARCH`；
S_ARCH 只做 `state <= S_IF_REQ`。S_TRAP：

```verilog
S_TRAP: begin
  trap_valid <= 1'b1;           // 观测口：在这里赋值，下一拍（S_ARCH）为 1
  trap_enter <= 1'b1;           // 给 CSR 模块：写 mepc / mcause / mtval / mstatus
  pc <= csr_mtvec;              // 直接模式，向量就是 mtvec
  if (STOP_ON_TRAP != 0) begin halted <= 1'b1; state <= S_HALT; end
  else state <= S_ARCH;
end
S_HALT: begin halted <= 1'b1; core_req_valid <= 1'b0; end
```

进入 S_TRAP 之前由出错的那个状态填好 `trap_cause`、`trap_epc`、`trap_tval` 三个寄存器。

## TODO 2：非法指令判定（组合）

```verilog
wire known_op = is_alu | is_lui | is_auipc | is_jal | is_jalr | is_branch | is_load | is_store |
                is_fence | is_fencei | (is_csr && csr_form_ok) | is_ecall | is_ebreak | is_mret;
wire illegal  = !known_op || !shift_imm_ok || !op_funct7_ok || !op32_ok || !load_f3_ok || !store_f3_ok ||
                !branch_f3_ok || !opimm32_ok || csr_addr_illegal;
```

每个 `*_ok` 是对保留编码的检查，基线核 `tcpu_core.v` 的 "legality" 一段逐条列了，可以对照着写。`jalr` 只有
funct3 = 000（d05）；`fence` 只有 funct3 = 000 和 001；SYSTEM 里 funct3 = 000 时只认 ecall、ebreak、mret 三条
完整编码。在 S_EXEC 的最前面：`if (illegal) → cause 2，tval = 指令编码，epc = pc → S_TRAP`。

## TODO 3：地址检查，在发请求之前

```verilog
wire mem_misaligned = (funct3[1:0] == 2'b01) ? mem_addr[0] :
                      (funct3[1:0] == 2'b10) ? |mem_addr[1:0] :
                      (funct3[1:0] == 2'b11) ? |mem_addr[2:0] : 1'b0;
wire mem_pa_bad = (mem_addr[63:32] != 32'd0);
wire pc_pa_bad  = (pc[63:32] != 32'd0);
wire target_misaligned = (is_jal | is_jalr) ? jump_target[1] :        // 无 C：IALIGN = 32，看 bit 1
                         (is_branch && branch_taken) ? br_target[1] : 1'b0;
```

S_EXEC 顺序：illegal → 未对齐（cause 4/6，tval 地址）→ PA 越界（cause 5/7）→ 目标未对齐（cause 0，tval 目标）→
ecall/ebreak → 发请求或写回。S_IF_REQ 里 `pc_pa_bad` → cause 1。注意 jalr 的目标已清 bit 0，所以只看 bit 1。

## TODO 4：总线错误变成访问错误

S_IF_WAIT 收到 `resp_error`：cause 1，tval = pc。S_MEM_WAIT 收到 `resp_error`：load cause 5、store cause 7，
tval = 地址。c08 的三个地址都在 32 位空间内但没有设备，错误来自总线不是核。

## TODO 5：ecall、ebreak、mret

- ecall：cause 11，tval 0，epc = pc，不退休。
- ebreak：cause 3，tval = pc。
- mret：正常退休（走 S_WB，计入 minstret），`npc = mepc`，`mret_go` 给 CSR 模块恢复 MIE。

## TODO 6：CSR 模块（新文件 `tcpu_csr.v`）

建议照基线的接口写，第 4、6 步在它上面加东西：

```verilog
module tcpu_csr #(parameter TRAP_BAD_MEPC = 0, TRAP_COUNTS_RET = 0, ALLOW_RO_WRITE = 0) (
  input clk, rst,
  input [11:0] addr, input access, input write_intent, input read_intent,
  output addr_illegal, output reg [63:0] rdata,
  input we, input [63:0] wdata,            // 在 S_WB 由核给出，和寄存器写同一拍
  input retire,                            // S_WB 的那一拍：minstret + 1
  input trap, input [63:0] trap_cause, trap_epc, trap_tval,
  input mret,
  output [63:0] mtvec_base, output [63:0] mepc_out,
  input [4:0] dbg_sel, output reg [63:0] dbg_val);
```

地址译码：已知集合以外 → `addr_illegal`；只读的（mhartid、cycle、instret）在 `write_intent` 时 → 非法，
除非 `ALLOW_RO_WRITE`。trap 时：`mepc <= TRAP_BAD_MEPC ? epc + 4 : epc`，mcause、mtval，MPIE ← MIE，MIE ← 0。
mret 时：MIE ← MPIE，MPIE ← 1。`minstret` 在 `retire || (TRAP_COUNTS_RET && trap)` 时加一，软件写优先。
`dbg_sel`：0 mstatus、1 mtvec、2 mepc、3 mcause、4 mtval、5 mscratch、6 mcycle、7 minstret，testbench 结束时打印。

## TODO 7：Zicsr 在核里的接法

```verilog
wire is_csr = is_system && (funct3 != 3'b000);
wire csr_form_ok = (funct3[1:0] != 2'b00);
wire csr_write_intent = is_csr && ((funct3[1:0] == 2'b01) || (rs1 != 5'd0));   // 看寄存器号，不看值
wire csr_read_intent  = is_csr && ((funct3[1:0] == 2'b01) ? (rd != 5'd0) : 1'b1);
wire [63:0] csr_src   = funct3[2] ? {59'd0, rs1} : rs1_val;
wire [63:0] csr_wdata = (funct3[1:0] == 2'b01) ? csr_src :
                        (funct3[1:0] == 2'b10) ? (csr_rdata | csr_src) : (csr_rdata & ~csr_src);
```

S_EXEC：`wb_we = csr_read_intent; wb_is_csr = 1`。S_WB：`rf_wd = csr_rdata`（组合读，本指令生效前的值），
`csr_we = wb_is_csr; csr_wdata_r = csr_wdata`，和寄存器写同一个沿落地，读改写因此原子。

## TODO 8：观测口和开关

`trap_valid` 由 S_TRAP 产生：在 S_TRAP 那一拍赋值，在其后一拍（state 已是 S_ARCH）为 1，宽度一拍；它和 `commit_valid` 永不同拍。所有 `output reg` 观测信号都是这个关系：在状态 X 里赋值，在 X 的下一拍可见。`trap_interrupt` 这一步恒 0。
`dbg_csr_sel` / `dbg_csr_val` 接到 CSR 模块。三个故障开关都在 CSR 模块里，核只负责透传参数。

## 顺序建议

| 加完 | 跑 | 应该看到 |
| --- | --- | --- |
| TODO 1、2 | `make step3` | d04、d05、d07 过（cause 2 停机） |
| TODO 3 | 同上 | d01、d02 过 |
| **练习**：自己写 `d09_pc_highpa.S` | 先故意把 S_IF_REQ 的 cause 写错，看它失败；再改对 | 第 3 步唯一一个检查取指地址越界（cause 1）的测试，由你来写 |
| TODO 6、7 | 同上 | d08、c01、c02、c04 过 |
| TODO 5 | 同上 | c05、c09、c10 过 |
| TODO 2 的 CSR 部分 | 同上 | c03 过 |
| TODO 3 的目标对齐 | 同上 | c06 过 |
| TODO 4 | 同上 | c08 过，c07 被正确拒绝 |
| TODO 8 的开关 | `make step3-mutants` | 三个 ok |
