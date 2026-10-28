# 第 4 步的 TODO：七块

## TODO 1：CSR 模块加 mie、mip 和中断判定

端口加上（和基线核同名）：

```verilog
input  irq_msip, irq_mtip, irq_meip,      // 三根电平，来自核的同名输入
output irq_pending,                       // 有一个可接受的中断
output [63:0] irq_cause,                  // {1'b1, 57'd0, 6'd11/3/7}
output irq_enabled,                       // 给 dbg_irq_enabled：MIE 打开且至少一根线的使能打开
```

- `mie`：三个触发器 `mie_msie`、`mie_mtie`、`mie_meie`，读出 `{52'd0, meie, 3'd0, mtie, 3'd0, msie, 3'd0}`。
- `mip`：**不是寄存器**，读出就是 `{52'd0, irq_meip, 3'd0, irq_mtip, 3'd0, irq_msip, 3'd0}`。地址 0x344 的 [11:10] 不是 11，
  所以写它是合法指令，但模块里不存任何东西。
- 两个地址加进"已知"列表。

## TODO 2：优先级

```verilog
wire [11:0] pend = mip_value[11:0] & mie_value[11:0];
assign irq_pending = st_mie && (pend != 0);
wire [5:0] n = pend[11] ? 6'd11 : pend[3] ? 6'd3 : 6'd7;   // MEI > MSI > MTI
assign irq_cause = {1'b1, 57'd0, n};
```

只有 M 模式时就这么简单；第 6 步加 S 模式后，"在比 M 低的特权级上 MIE 不起作用"会让条件多一项。

## TODO 3：trap 时记录中断的 cause

你在第 3 步写的 trap 分支已经把 `trap_cause`、`trap_epc`、`trap_tval` 存进 mcause、mepc、mtval，并做了 MIE→MPIE。
中断走同一条路：只要 `trap_cause` 带着 bit 63、`trap_tval` 是 0，这里不用改。

## TODO 4：在 S_IF_REQ 接受中断

放在 S_IF_REQ 的**最后**（你的写法里后写的优先），比取指地址检查优先：

```verilog
if (irq_pending) begin
  trap_cause     <= irq_cause;
  trap_tval      <= 64'd0;
  trap_epc       <= (IRQ_BAD_MEPC != 0) ? pc - 64'd4 : pc;   // mepc 就是这条还没执行的指令
  trap_interrupt <= 1'b1;
  state          <= S_TRAP;                                   // 不发这次取指：core_req_valid 保持 0
end
```

`trap_interrupt` 是输出寄存器，同步异常时它必须是 0。基线核的做法：always 块开头
`if (state != S_TRAP) trap_interrupt <= 1'b0;`，只有中断路径把它置 1。

## TODO 5：wfi

`wire is_wfi = (insn == 32'h10500073);` 加进 `known_op`，走"不写寄存器、`npc = pc + 4`"那条路，和 fence 一样。

## TODO 6：两根观测线

```verilog
assign dbg_irq_enabled = csr_irq_enabled;                         // 注入器只在使能真的生效时触发（j01）
assign dbg_redirect    = (state == S_WB) && (npc != pc + 64'd4);  // 正在写回一条改变了控制流的指令（i07）
```

它们不是给软件用的，是给 harness 定位注入时刻用的。基线核里它们一直存在，骨架里接成了 0。

## TODO 7：三个变异开关

```verilog
// STALE_MIE：在 S_ARCH 也采样（用的是还没落地的 MIE）
S_ARCH: if (STALE_MIE != 0 && irq_pending) begin ...同 TODO 4... end else state <= S_IF_REQ;

// EARLY_IRQ：在 S_MEM_WAIT 也接受，放弃已经发出的访存
S_MEM_WAIT: if (EARLY_IRQ != 0 && irq_pending) begin core_req_valid <= 1'b0; ...同 TODO 4，epc = pc... end
```

`IRQ_BAD_MEPC` 已经在 TODO 4 里。注意 `EARLY_IRQ` 那一段要写在 S_MEM_WAIT 里**收到响应那一段之前**，
这样同一拍响应到达时，后面的 `state <= S_WB` 会覆盖它，这和基线核的行为一致。

## 顺序建议

| 加完 | 跑 | 预期 |
| --- | --- | --- |
| TODO 1 | `make step3` | 第 3 步仍然全过：mie、mip 只是多了两个地址 |
| TODO 1 到 4 | `make step4` | i01、i02、i03、i04、i06、i08、i09 过 |
| TODO 5 | 同上 | i05 过 |
| TODO 6 | 同上 | i07、j01 过，最后 20 个全 ok |
| TODO 7 | `make step4-mutants` | 5 个 ok |
