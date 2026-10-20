// MCU-0: core + router + RAM + CLINT + GPIO. Four LEDs are GPIO OUT[3:0]; the buttons and switches are IN.
// No host, no bridge: the program is the RAM's initial contents.
`timescale 1ns/1ps
module mcu_top #(
  parameter        MEM_BYTES = 65536,
  parameter        INIT_HEX  = "",
  parameter        TICK_DIV  = 1
) (
  input             clk,
  input             rst,
  output     [3:0]  led,
  input      [3:0]  btn,
  input      [1:0]  sw,
  output            commit_valid,   // activity, for an LED or an ILA trigger
  output            bus_error       // a response with error set: the program touched a bad address
);
  localparam [63:0] RESET_PC = 64'h0000_0000_8000_0000;
  wire        req_valid, req_ready, req_write, resp_valid, resp_ready, resp_error, resp_scfail;
  wire [31:0] req_addr;
  wire [1:0]  req_size, req_lrsc;
  wire [63:0] req_wdata, resp_rdata;
  wire [7:0]  req_wmask;
  wire [3:0]  req_amo;
  wire        sel_ram, sel_clint, sel_gpio, slv_we, mtip, msip;
  wire [31:0] slv_addr;
  wire [63:0] slv_wdata, ram_rdata, clint_rdata, gpio_rdata;
  wire [7:0]  slv_wmask, gpio_out;

  tcpu_core #(.RESET_PC(RESET_PC)) cpu (
    .clk(clk), .rst(rst),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr), .req_write(req_write),
    .req_size(req_size), .req_wdata(req_wdata), .req_wmask(req_wmask), .req_amo(req_amo), .req_lrsc(req_lrsc),
    .resp_valid(resp_valid), .resp_ready(resp_ready), .resp_rdata(resp_rdata), .resp_error(resp_error),
    .resp_scfail(resp_scfail), .resv_clear(),
    .commit_valid(commit_valid), .commit_pc(), .commit_insn(), .commit_len(), .commit_rd_valid(), .commit_rd(),
    .commit_rd_data(), .trap_valid(), .trap_interrupt(), .trap_cause(), .trap_epc(), .trap_tval(), .halted(),
    .dbg_req_is_fetch(), .dbg_ra(5'd0), .dbg_rd(), .dbg_ra2(5'd0), .dbg_rd2(), .dbg_csr_sel(5'd0), .dbg_csr_val(),
    .dbg_priv(), .irq_msip(msip), .irq_mtip(mtip), .irq_meip(1'b0), .dbg_state(), .dbg_redirect(), .dbg_pc(),
    .dbg_irq_enabled());

  mcu_router #(.RAM_BYTES(MEM_BYTES)) bus (
    .clk(clk), .rst(rst),
    .req_valid(req_valid), .req_ready(req_ready), .req_addr(req_addr), .req_write(req_write), .req_size(req_size),
    .req_wdata(req_wdata), .req_wmask(req_wmask), .req_amo(req_amo), .req_lrsc(req_lrsc),
    .resp_valid(resp_valid), .resp_ready(resp_ready), .resp_rdata(resp_rdata), .resp_error(resp_error), .resp_scfail(resp_scfail),
    .sel_ram(sel_ram), .sel_clint(sel_clint), .sel_gpio(sel_gpio), .slv_we(slv_we), .slv_addr(slv_addr),
    .slv_wdata(slv_wdata), .slv_wmask(slv_wmask), .ram_rdata(ram_rdata), .clint_rdata(clint_rdata), .gpio_rdata(gpio_rdata));

  mcu_ram #(.MEM_BYTES(MEM_BYTES), .INIT_HEX(INIT_HEX)) ram (
    .clk(clk), .sel(sel_ram), .we(slv_we), .addr(slv_addr), .wdata(slv_wdata), .wmask(slv_wmask), .rdata(ram_rdata));
  mcu_clint #(.TICK_DIV(TICK_DIV)) clint (
    .clk(clk), .rst(rst), .sel(sel_clint), .we(slv_we), .addr(slv_addr), .wdata(slv_wdata), .wmask(slv_wmask),
    .rdata(clint_rdata), .mtip(mtip), .msip(msip));
  mcu_gpio gpio (
    .clk(clk), .rst(rst), .sel(sel_gpio), .we(slv_we), .addr(slv_addr), .wdata(slv_wdata), .wmask(slv_wmask),
    .rdata(gpio_rdata), .gpio_out(gpio_out), .gpio_in({2'b00, sw, btn}));

  assign led = gpio_out[3:0];
  assign bus_error = resp_valid & resp_error;
endmodule
