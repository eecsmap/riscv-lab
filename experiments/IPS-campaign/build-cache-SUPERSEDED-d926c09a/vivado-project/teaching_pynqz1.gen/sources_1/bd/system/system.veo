// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------
// This file contains confidential and proprietary information
// of AMD and is protected under U.S. and international copyright
// and other intellectual property laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// AMD, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) AMD shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or AMD had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// AMD products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of AMD products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.
//
// DO NOT MODIFY THIS FILE.

// MODULE VLNV: amd.com:blockdesign:system:1.0

// The following must be inserted into your Verilog file for this
// module to be instantiated. Change the instance name and port connections
// (in parentheses) to your own signal names.

// INST_TAG     ------ Begin cut for INSTANTIATION Template ------
system your_instance_name (
  .M_AXI_awaddr(M_AXI_awaddr), // output wire [31:0] M_AXI_awaddr
  .M_AXI_awlen(M_AXI_awlen), // output wire [7:0] M_AXI_awlen
  .M_AXI_awsize(M_AXI_awsize), // output wire [2:0] M_AXI_awsize
  .M_AXI_awburst(M_AXI_awburst), // output wire [1:0] M_AXI_awburst
  .M_AXI_awlock(M_AXI_awlock), // output wire [0:0] M_AXI_awlock
  .M_AXI_awcache(M_AXI_awcache), // output wire [3:0] M_AXI_awcache
  .M_AXI_awprot(M_AXI_awprot), // output wire [2:0] M_AXI_awprot
  .M_AXI_awregion(M_AXI_awregion), // output wire [3:0] M_AXI_awregion
  .M_AXI_awqos(M_AXI_awqos), // output wire [3:0] M_AXI_awqos
  .M_AXI_awvalid(M_AXI_awvalid), // output wire M_AXI_awvalid
  .M_AXI_awready(M_AXI_awready), // input wire M_AXI_awready
  .M_AXI_wdata(M_AXI_wdata), // output wire [31:0] M_AXI_wdata
  .M_AXI_wstrb(M_AXI_wstrb), // output wire [3:0] M_AXI_wstrb
  .M_AXI_wlast(M_AXI_wlast), // output wire M_AXI_wlast
  .M_AXI_wvalid(M_AXI_wvalid), // output wire M_AXI_wvalid
  .M_AXI_wready(M_AXI_wready), // input wire M_AXI_wready
  .M_AXI_bresp(M_AXI_bresp), // input wire [1:0] M_AXI_bresp
  .M_AXI_bvalid(M_AXI_bvalid), // input wire M_AXI_bvalid
  .M_AXI_bready(M_AXI_bready), // output wire M_AXI_bready
  .M_AXI_araddr(M_AXI_araddr), // output wire [31:0] M_AXI_araddr
  .M_AXI_arlen(M_AXI_arlen), // output wire [7:0] M_AXI_arlen
  .M_AXI_arsize(M_AXI_arsize), // output wire [2:0] M_AXI_arsize
  .M_AXI_arburst(M_AXI_arburst), // output wire [1:0] M_AXI_arburst
  .M_AXI_arlock(M_AXI_arlock), // output wire [0:0] M_AXI_arlock
  .M_AXI_arcache(M_AXI_arcache), // output wire [3:0] M_AXI_arcache
  .M_AXI_arprot(M_AXI_arprot), // output wire [2:0] M_AXI_arprot
  .M_AXI_arregion(M_AXI_arregion), // output wire [3:0] M_AXI_arregion
  .M_AXI_arqos(M_AXI_arqos), // output wire [3:0] M_AXI_arqos
  .M_AXI_arvalid(M_AXI_arvalid), // output wire M_AXI_arvalid
  .M_AXI_arready(M_AXI_arready), // input wire M_AXI_arready
  .M_AXI_rdata(M_AXI_rdata), // input wire [31:0] M_AXI_rdata
  .M_AXI_rresp(M_AXI_rresp), // input wire [1:0] M_AXI_rresp
  .M_AXI_rlast(M_AXI_rlast), // input wire M_AXI_rlast
  .M_AXI_rvalid(M_AXI_rvalid), // input wire M_AXI_rvalid
  .M_AXI_rready(M_AXI_rready), // output wire M_AXI_rready
  .S_AXI_awaddr(S_AXI_awaddr), // input wire [31:0] S_AXI_awaddr
  .S_AXI_awlen(S_AXI_awlen), // input wire [7:0] S_AXI_awlen
  .S_AXI_awsize(S_AXI_awsize), // input wire [2:0] S_AXI_awsize
  .S_AXI_awburst(S_AXI_awburst), // input wire [1:0] S_AXI_awburst
  .S_AXI_awlock(S_AXI_awlock), // input wire [0:0] S_AXI_awlock
  .S_AXI_awcache(S_AXI_awcache), // input wire [3:0] S_AXI_awcache
  .S_AXI_awprot(S_AXI_awprot), // input wire [2:0] S_AXI_awprot
  .S_AXI_awqos(S_AXI_awqos), // input wire [3:0] S_AXI_awqos
  .S_AXI_awvalid(S_AXI_awvalid), // input wire S_AXI_awvalid
  .S_AXI_awready(S_AXI_awready), // output wire S_AXI_awready
  .S_AXI_wdata(S_AXI_wdata), // input wire [63:0] S_AXI_wdata
  .S_AXI_wstrb(S_AXI_wstrb), // input wire [7:0] S_AXI_wstrb
  .S_AXI_wlast(S_AXI_wlast), // input wire S_AXI_wlast
  .S_AXI_wvalid(S_AXI_wvalid), // input wire S_AXI_wvalid
  .S_AXI_wready(S_AXI_wready), // output wire S_AXI_wready
  .S_AXI_bresp(S_AXI_bresp), // output wire [1:0] S_AXI_bresp
  .S_AXI_bvalid(S_AXI_bvalid), // output wire S_AXI_bvalid
  .S_AXI_bready(S_AXI_bready), // input wire S_AXI_bready
  .S_AXI_araddr(S_AXI_araddr), // input wire [31:0] S_AXI_araddr
  .S_AXI_arlen(S_AXI_arlen), // input wire [7:0] S_AXI_arlen
  .S_AXI_arsize(S_AXI_arsize), // input wire [2:0] S_AXI_arsize
  .S_AXI_arburst(S_AXI_arburst), // input wire [1:0] S_AXI_arburst
  .S_AXI_arlock(S_AXI_arlock), // input wire [0:0] S_AXI_arlock
  .S_AXI_arcache(S_AXI_arcache), // input wire [3:0] S_AXI_arcache
  .S_AXI_arprot(S_AXI_arprot), // input wire [2:0] S_AXI_arprot
  .S_AXI_arqos(S_AXI_arqos), // input wire [3:0] S_AXI_arqos
  .S_AXI_arvalid(S_AXI_arvalid), // input wire S_AXI_arvalid
  .S_AXI_arready(S_AXI_arready), // output wire S_AXI_arready
  .S_AXI_rdata(S_AXI_rdata), // output wire [63:0] S_AXI_rdata
  .S_AXI_rresp(S_AXI_rresp), // output wire [1:0] S_AXI_rresp
  .S_AXI_rlast(S_AXI_rlast), // output wire S_AXI_rlast
  .S_AXI_rvalid(S_AXI_rvalid), // output wire S_AXI_rvalid
  .S_AXI_rready(S_AXI_rready), // input wire S_AXI_rready
  .DDR_0_cas_n(DDR_0_cas_n), // inout wire DDR_0_cas_n
  .DDR_0_cke(DDR_0_cke), // inout wire DDR_0_cke
  .DDR_0_ck_n(DDR_0_ck_n), // inout wire DDR_0_ck_n
  .DDR_0_ck_p(DDR_0_ck_p), // inout wire DDR_0_ck_p
  .DDR_0_cs_n(DDR_0_cs_n), // inout wire DDR_0_cs_n
  .DDR_0_reset_n(DDR_0_reset_n), // inout wire DDR_0_reset_n
  .DDR_0_odt(DDR_0_odt), // inout wire DDR_0_odt
  .DDR_0_ras_n(DDR_0_ras_n), // inout wire DDR_0_ras_n
  .DDR_0_we_n(DDR_0_we_n), // inout wire DDR_0_we_n
  .DDR_0_ba(DDR_0_ba), // inout wire [2:0] DDR_0_ba
  .DDR_0_addr(DDR_0_addr), // inout wire [14:0] DDR_0_addr
  .DDR_0_dm(DDR_0_dm), // inout wire [3:0] DDR_0_dm
  .DDR_0_dq(DDR_0_dq), // inout wire [31:0] DDR_0_dq
  .DDR_0_dqs_n(DDR_0_dqs_n), // inout wire [3:0] DDR_0_dqs_n
  .DDR_0_dqs_p(DDR_0_dqs_p), // inout wire [3:0] DDR_0_dqs_p
  .FIXED_IO_0_mio(FIXED_IO_0_mio), // inout wire [53:0] FIXED_IO_0_mio
  .FIXED_IO_0_ddr_vrn(FIXED_IO_0_ddr_vrn), // inout wire FIXED_IO_0_ddr_vrn
  .FIXED_IO_0_ddr_vrp(FIXED_IO_0_ddr_vrp), // inout wire FIXED_IO_0_ddr_vrp
  .FIXED_IO_0_ps_srstb(FIXED_IO_0_ps_srstb), // inout wire FIXED_IO_0_ps_srstb
  .FIXED_IO_0_ps_clk(FIXED_IO_0_ps_clk), // inout wire FIXED_IO_0_ps_clk
  .FIXED_IO_0_ps_porb(FIXED_IO_0_ps_porb), // inout wire FIXED_IO_0_ps_porb
  .FCLK_RESET0_N(FCLK_RESET0_N), // output wire FCLK_RESET0_N
  .ext_clk_in(ext_clk_in), // input wire ext_clk_in
  .M_AXI_arid(M_AXI_arid), // output wire [11:0] M_AXI_arid
  .M_AXI_awid(M_AXI_awid), // output wire [11:0] M_AXI_awid
  .M_AXI_bid(M_AXI_bid), // input wire [11:0] M_AXI_bid
  .M_AXI_rid(M_AXI_rid), // input wire [11:0] M_AXI_rid
  .S_AXI_arid(S_AXI_arid), // input wire [5:0] S_AXI_arid
  .S_AXI_arregion(S_AXI_arregion), // input wire [3:0] S_AXI_arregion
  .S_AXI_awid(S_AXI_awid), // input wire [5:0] S_AXI_awid
  .S_AXI_awregion(S_AXI_awregion), // input wire [3:0] S_AXI_awregion
  .S_AXI_bid(S_AXI_bid), // output wire [5:0] S_AXI_bid
  .S_AXI_rid(S_AXI_rid) // output wire [5:0] S_AXI_rid
);
// INST_TAG_END ------  End cut for INSTANTIATION Template  ------

// You must compile the wrapper file system.v when simulating
// the module, system. When compiling the wrapper file, be sure to
// reference the Verilog simulation library.
