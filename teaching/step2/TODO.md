# 第 2 步的 TODO：在你的 `work/cpu/tcpu_core.v` 里加这七块

没有新骨架，因为你的第 1 步代码已经是你自己的了。下面每一块说明放在哪、长什么样；把它们当作第 1 步
那种 `// TODO:` 注释，按顺序加。建议每加完一块就 `make step2`，看 `TOHOST code=N` 往后走。

## TODO 1：译码按 opcode 分组（放在第 1 步的 `is_*` wire 旁边）

```verilog
wire is_opimm   = (opcode == `OP_OPIMM);
wire is_op      = (opcode == `OP_OP);
wire is_opimm32 = (opcode == `OP_OPIMM32);
wire is_op32    = (opcode == `OP_OP32);
wire is_lui     = (opcode == `OP_LUI);
wire is_auipc   = (opcode == `OP_AUIPC);
wire is_jal     = (opcode == `OP_JAL);
wire is_jalr    = (opcode == `OP_JALR);
wire is_branch  = (opcode == `OP_BRANCH);
wire is_load    = (opcode == `OP_LOAD);
wire is_store   = (opcode == `OP_STORE);
wire is_fence   = (opcode == `OP_MISCMEM);         // fence 和 fence.i：合法空操作
wire is_alu     = is_opimm | is_op | is_opimm32 | is_op32;
wire [6:0] funct7 = insn[31:25];
wire alt = funct7[5];                                // sub / sra 的选择位
```

## TODO 2：ALU（组合块，放在译码之后）

操作数 B：`is_op | is_op32 ? rs2_val : imm_i`。移位量：64 位用 `is_op ? rs2_val[5:0] : insn[25:20]`，
W 用 `is_op32 ? rs2_val[4:0] : insn[24:20]`。

```verilog
reg [63:0] alu_out;
always @(*) begin
  alu_out = 64'd0;
  if (is_opimm || is_op) case (funct3)
    3'b000: alu_out = (is_op && alt) ? rs1_val - op_b : rs1_val + op_b;
    3'b001: alu_out = rs1_val << shamt6;
    3'b010: alu_out = {63'd0, $signed(rs1_val) < $signed(op_b)};
    3'b011: alu_out = {63'd0, rs1_val < op_b};
    3'b100: alu_out = rs1_val ^ op_b;
    3'b101: alu_out = alt ? ($signed(rs1_val) >>> shamt6) : (rs1_val >> shamt6);
    3'b110: alu_out = rs1_val | op_b;
    3'b111: alu_out = rs1_val & op_b;
  endcase
  else if (is_opimm32 || is_op32) begin
    // 对低 32 位算，结果符号扩展：先算出 32 位的 w，再 {{32{w[31]}}, w}
  end
end
```

## TODO 3：分支判定与目标（组合）

```verilog
reg branch_taken;
always @(*) case (funct3)
  3'b000: branch_taken = (rs1_val == rs2_val);
  3'b001: branch_taken = (rs1_val != rs2_val);
  3'b100: branch_taken = ($signed(rs1_val) <  $signed(rs2_val));
  3'b101: branch_taken = ($signed(rs1_val) >= $signed(rs2_val));
  3'b110: branch_taken = (rs1_val <  rs2_val);
  3'b111: branch_taken = (rs1_val >= rs2_val);
  default: branch_taken = 1'b0;
endcase
wire [63:0] imm_b = {{51{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
wire [63:0] br_target   = pc + imm_b;
wire [63:0] jalr_target = (rs1_val + imm_i) & ~64'd1;
```

## TODO 4：访存地址、通道移位、掩码（组合）

```verilog
wire [63:0] mem_addr   = rs1_val + (is_store ? imm_s : imm_i);
wire [5:0]  lshift     = {mem_addr[2:0], 3'b000};
wire [7:0]  mask_base  = (funct3[1:0] == 2'b00) ? 8'h01 : (funct3[1:0] == 2'b01) ? 8'h03 :
                         (funct3[1:0] == 2'b10) ? 8'h0f : 8'hff;
```

## TODO 5：S_EXEC 改成按组分发

- `is_alu`：`wb_we = 1; wb_value = alu_out; npc = pc + 4; -> S_WB`
- `is_lui / is_auipc / is_jal / is_jalr`：第 1 步的写法扩一下；jalr 的 `npc = jalr_target`
- `is_branch`：`wb_we = 0; npc = branch_taken ? br_target : pc + 4; -> S_WB`
- `is_fence`：`wb_we = 0; npc = pc + 4; -> S_WB`
- `is_load`：发读请求 `addr = mem_addr[31:0]`，`size = funct3[1:0]`，`write = 0`，`wdata = 0`，`wmask = 0`，`-> S_MEM_WAIT`
  - `LOAD_WDATA_LEAK != 0` 时 `wdata = rs2_val << lshift`（故障开关，d06 的变异体）
- `is_store`：`write = 1`，`wdata = rs2_val << lshift`，`wmask = mask_base << mem_addr[2:0]`，其余同上

## TODO 6：S_MEM_WAIT 里 load 的数据（响应那一拍）

```verilog
wire [63:0] ld_shift = resp_rdata >> lshift;
// funct3: 000 lb 001 lh 010 lw 011 ld 100 lbu 101 lhu 110 lwu
// 有符号三种按最高位扩展；NO_LOAD_SEXT != 0 时改为零扩展（故障开关，t03 的变异体）
```

响应到了：`wb_we <= is_load; wb_value <= load_data; npc <= pc + 4; state <= S_WB`。store 的 `wb_we` 是 0。

## TODO 7：故障开关的复位与默认值

两个开关都是参数，不需要新的 reg。但确认 `LOAD_WDATA_LEAK == 0` 时 load 的 `wdata` 和 `wmask` 真的是 0，
否则 d06 在**没开**变异体时也会被监视器抓。

## 顺序建议

| 加完 | 跑 | 应该看到 |
| --- | --- | --- |
| TODO 1、2、5 的 alu/lui/auipc/jal 部分 | `make step2` | t01 过，t02 在 code 1 停 |
| TODO 3 和 5 的分支、jalr | 同上 | t02 过，t03 在 code 1 停 |
| TODO 4、6 和 5 的 load/store | 同上 | 八个 ok |
| TODO 5、6 里的两个开关 | `make step2-mutants` | 三个 ok |
