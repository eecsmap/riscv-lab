// MCU-0 address router: the PHYSICAL_PORT slave the core talks to, and three simple slaves behind it.
//
// Slave interface (fixed one-cycle latency, always ready): the router pulses `sel_<slave>` for one cycle
// together with slv_we / slv_addr / slv_wdata / slv_wmask; the slave performs the write, or registers its read
// data, at the end of that cycle, and holds <slave>_rdata until its next select. The router answers the core
// the cycle after that. Accept -> response is therefore two cycles, which the port contract allows.
//
// Addresses nobody claims, and atomic requests, answer resp_error = 1 and touch no slave.
`timescale 1ns/1ps
module mcu_router #(
  parameter [31:0] RAM_BASE   = 32'h8000_0000,
  parameter        RAM_BYTES  = 65536,
  parameter [31:0] CLINT_BASE = 32'h0200_0000,   // 64 KiB window
  parameter [31:0] GPIO_BASE  = 32'h1001_0000    // 4 KiB window
) (
  input             clk,
  input             rst,
  // ---- PHYSICAL_PORT, the core is the master
  input             req_valid,
  output reg        req_ready,
  input      [31:0] req_addr,
  input             req_write,
  input      [1:0]  req_size,
  input      [63:0] req_wdata,
  input      [7:0]  req_wmask,
  input      [3:0]  req_amo,
  input      [1:0]  req_lrsc,
  output reg        resp_valid,
  input             resp_ready,
  output     [63:0] resp_rdata,
  output reg        resp_error,
  output            resp_scfail,
  // ---- the slaves
  output reg        sel_ram,
  output reg        sel_clint,
  output reg        sel_gpio,
  output reg        slv_we,
  output reg [31:0] slv_addr,
  output reg [63:0] slv_wdata,
  output reg [7:0]  slv_wmask,
  input      [63:0] ram_rdata,
  input      [63:0] clint_rdata,
  input      [63:0] gpio_rdata
);
  wire [31:0] ram_off   = req_addr - RAM_BASE;
  wire        hit_ram   = (req_addr >= RAM_BASE) && (ram_off < RAM_BYTES);
  wire        hit_clint = ((req_addr & 32'hFFFF_0000) == CLINT_BASE);
  wire        hit_gpio  = ((req_addr & 32'hFFFF_F000) == GPIO_BASE);
  wire        atomic    = (req_amo != 4'd0) || (req_lrsc != 2'd0);
  wire        legal     = (hit_ram | hit_clint | hit_gpio) & !atomic;

  reg        busy;            // accepted, slave cycle in progress
  reg        answer;          // slave cycle done, respond now
  reg [2:0]  which;           // {gpio, clint, ram} of the accepted request
  assign resp_scfail = 1'b0;
  assign resp_rdata  = resp_error ? 64'd0 :
                       which[0] ? ram_rdata : which[1] ? clint_rdata : which[2] ? gpio_rdata : 64'd0;

  always @(posedge clk) begin
    if (rst) begin
      req_ready <= 1'b0; busy <= 1'b0; answer <= 1'b0; resp_valid <= 1'b0; resp_error <= 1'b0; which <= 3'd0;
      sel_ram <= 1'b0; sel_clint <= 1'b0; sel_gpio <= 1'b0; slv_we <= 1'b0; slv_addr <= 32'd0; slv_wdata <= 64'd0; slv_wmask <= 8'd0;
    end else begin
      resp_valid <= 1'b0; sel_ram <= 1'b0; sel_clint <= 1'b0; sel_gpio <= 1'b0;
      req_ready  <= req_valid && !busy && !answer && !req_ready;
      if (req_valid && req_ready) begin                      // accept: select the slave for the next cycle
        busy <= 1'b1; resp_error <= !legal; which <= {hit_gpio, hit_clint, hit_ram} & {3{!atomic}};
        sel_ram <= hit_ram & !atomic; sel_clint <= hit_clint & !atomic; sel_gpio <= hit_gpio & !atomic;
        slv_we <= req_write; slv_addr <= req_addr; slv_wdata <= req_wdata; slv_wmask <= req_wmask;
      end
      if (busy)   begin busy <= 1'b0; answer <= 1'b1; end      // the slave is doing its cycle
      if (answer) begin answer <= 1'b0; resp_valid <= 1'b1; end // its rdata is now held: respond
    end
  end
endmodule
