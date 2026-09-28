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

`timescale 1ps / 1ps

`include "vivado_interfaces.svh"

module system_sv (
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M_AXI" *)
  (* X_INTERFACE_MODE = "master M_AXI" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXI, DATA_WIDTH 32, PROTOCOL AXI4, FREQ_HZ 25000000, ID_WIDTH 12, ADDR_WIDTH 32, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, HAS_LOCK 1, HAS_PROT 1, HAS_CACHE 1, HAS_QOS 1, HAS_REGION 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 8, NUM_WRITE_OUTSTANDING 8, MAX_BURST_LENGTH 16, PHASE 0.0, CLK_DOMAIN system_ext_clk_in, NUM_READ_THREADS 4, NUM_WRITE_THREADS 4, RUSER_BITS_PER_BYTE 0, WUSER_BITS_PER_BYTE 0, INSERT_VIP 0" *)
  vivado_aximm_v1_0.master M_AXI,
  (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI" *)
  (* X_INTERFACE_MODE = "slave S_AXI" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXI, DATA_WIDTH 64, PROTOCOL AXI4, FREQ_HZ 25000000, ID_WIDTH 6, ADDR_WIDTH 32, AWUSER_WIDTH 0, ARUSER_WIDTH 0, WUSER_WIDTH 0, RUSER_WIDTH 0, BUSER_WIDTH 0, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, HAS_LOCK 1, HAS_PROT 1, HAS_CACHE 1, HAS_QOS 1, HAS_REGION 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 16, PHASE 0.0, CLK_DOMAIN system_ext_clk_in, NUM_READ_THREADS 1, NUM_WRITE_THREADS 1, RUSER_BITS_PER_BYTE 0, WUSER_BITS_PER_BYTE 0, INSERT_VIP 0" *)
  vivado_aximm_v1_0.slave S_AXI,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_0_cas_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_0_cke,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_0_ck_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_0_ck_p,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_0_cs_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_0_reset_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_0_odt,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_0_ras_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire DDR_0_we_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [2:0] DDR_0_ba,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [14:0] DDR_0_addr,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [3:0] DDR_0_dm,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [31:0] DDR_0_dq,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [3:0] DDR_0_dqs_n,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [3:0] DDR_0_dqs_p,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire [53:0] FIXED_IO_0_mio,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire FIXED_IO_0_ddr_vrn,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire FIXED_IO_0_ddr_vrp,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire FIXED_IO_0_ps_srstb,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire FIXED_IO_0_ps_clk,
  (* X_INTERFACE_IGNORE = "true" *)
  inout wire FIXED_IO_0_ps_porb,
  (* X_INTERFACE_IGNORE = "true" *)
  output wire FCLK_RESET0_N,
  (* X_INTERFACE_IGNORE = "true" *)
  input wire ext_clk_in
);

  // interface wire assignments
  assign M_AXI.ARUSER = 0;
  assign M_AXI.AWUSER = 0;
  assign M_AXI.WID = 0;
  assign M_AXI.WUSER = 0;
  assign S_AXI.BUSER = 0;
  assign S_AXI.RUSER = 0;

  system inst (
    .M_AXI_awaddr(M_AXI.AWADDR),
    .M_AXI_awlen(M_AXI.AWLEN),
    .M_AXI_awsize(M_AXI.AWSIZE),
    .M_AXI_awburst(M_AXI.AWBURST),
    .M_AXI_awlock(M_AXI.AWLOCK),
    .M_AXI_awcache(M_AXI.AWCACHE),
    .M_AXI_awprot(M_AXI.AWPROT),
    .M_AXI_awregion(M_AXI.AWREGION),
    .M_AXI_awqos(M_AXI.AWQOS),
    .M_AXI_awvalid(M_AXI.AWVALID),
    .M_AXI_awready(M_AXI.AWREADY),
    .M_AXI_wdata(M_AXI.WDATA),
    .M_AXI_wstrb(M_AXI.WSTRB),
    .M_AXI_wlast(M_AXI.WLAST),
    .M_AXI_wvalid(M_AXI.WVALID),
    .M_AXI_wready(M_AXI.WREADY),
    .M_AXI_bresp(M_AXI.BRESP),
    .M_AXI_bvalid(M_AXI.BVALID),
    .M_AXI_bready(M_AXI.BREADY),
    .M_AXI_araddr(M_AXI.ARADDR),
    .M_AXI_arlen(M_AXI.ARLEN),
    .M_AXI_arsize(M_AXI.ARSIZE),
    .M_AXI_arburst(M_AXI.ARBURST),
    .M_AXI_arlock(M_AXI.ARLOCK),
    .M_AXI_arcache(M_AXI.ARCACHE),
    .M_AXI_arprot(M_AXI.ARPROT),
    .M_AXI_arregion(M_AXI.ARREGION),
    .M_AXI_arqos(M_AXI.ARQOS),
    .M_AXI_arvalid(M_AXI.ARVALID),
    .M_AXI_arready(M_AXI.ARREADY),
    .M_AXI_rdata(M_AXI.RDATA),
    .M_AXI_rresp(M_AXI.RRESP),
    .M_AXI_rlast(M_AXI.RLAST),
    .M_AXI_rvalid(M_AXI.RVALID),
    .M_AXI_rready(M_AXI.RREADY),
    .S_AXI_awaddr(S_AXI.AWADDR),
    .S_AXI_awlen(S_AXI.AWLEN),
    .S_AXI_awsize(S_AXI.AWSIZE),
    .S_AXI_awburst(S_AXI.AWBURST),
    .S_AXI_awlock(S_AXI.AWLOCK),
    .S_AXI_awcache(S_AXI.AWCACHE),
    .S_AXI_awprot(S_AXI.AWPROT),
    .S_AXI_awqos(S_AXI.AWQOS),
    .S_AXI_awvalid(S_AXI.AWVALID),
    .S_AXI_awready(S_AXI.AWREADY),
    .S_AXI_wdata(S_AXI.WDATA),
    .S_AXI_wstrb(S_AXI.WSTRB),
    .S_AXI_wlast(S_AXI.WLAST),
    .S_AXI_wvalid(S_AXI.WVALID),
    .S_AXI_wready(S_AXI.WREADY),
    .S_AXI_bresp(S_AXI.BRESP),
    .S_AXI_bvalid(S_AXI.BVALID),
    .S_AXI_bready(S_AXI.BREADY),
    .S_AXI_araddr(S_AXI.ARADDR),
    .S_AXI_arlen(S_AXI.ARLEN),
    .S_AXI_arsize(S_AXI.ARSIZE),
    .S_AXI_arburst(S_AXI.ARBURST),
    .S_AXI_arlock(S_AXI.ARLOCK),
    .S_AXI_arcache(S_AXI.ARCACHE),
    .S_AXI_arprot(S_AXI.ARPROT),
    .S_AXI_arqos(S_AXI.ARQOS),
    .S_AXI_arvalid(S_AXI.ARVALID),
    .S_AXI_arready(S_AXI.ARREADY),
    .S_AXI_rdata(S_AXI.RDATA),
    .S_AXI_rresp(S_AXI.RRESP),
    .S_AXI_rlast(S_AXI.RLAST),
    .S_AXI_rvalid(S_AXI.RVALID),
    .S_AXI_rready(S_AXI.RREADY),
    .DDR_0_cas_n(DDR_0_cas_n),
    .DDR_0_cke(DDR_0_cke),
    .DDR_0_ck_n(DDR_0_ck_n),
    .DDR_0_ck_p(DDR_0_ck_p),
    .DDR_0_cs_n(DDR_0_cs_n),
    .DDR_0_reset_n(DDR_0_reset_n),
    .DDR_0_odt(DDR_0_odt),
    .DDR_0_ras_n(DDR_0_ras_n),
    .DDR_0_we_n(DDR_0_we_n),
    .DDR_0_ba(DDR_0_ba),
    .DDR_0_addr(DDR_0_addr),
    .DDR_0_dm(DDR_0_dm),
    .DDR_0_dq(DDR_0_dq),
    .DDR_0_dqs_n(DDR_0_dqs_n),
    .DDR_0_dqs_p(DDR_0_dqs_p),
    .FIXED_IO_0_mio(FIXED_IO_0_mio),
    .FIXED_IO_0_ddr_vrn(FIXED_IO_0_ddr_vrn),
    .FIXED_IO_0_ddr_vrp(FIXED_IO_0_ddr_vrp),
    .FIXED_IO_0_ps_srstb(FIXED_IO_0_ps_srstb),
    .FIXED_IO_0_ps_clk(FIXED_IO_0_ps_clk),
    .FIXED_IO_0_ps_porb(FIXED_IO_0_ps_porb),
    .FCLK_RESET0_N(FCLK_RESET0_N),
    .ext_clk_in(ext_clk_in),
    .M_AXI_arid(M_AXI.ARID),
    .M_AXI_awid(M_AXI.AWID),
    .M_AXI_bid(M_AXI.BID),
    .M_AXI_rid(M_AXI.RID),
    .S_AXI_arid(S_AXI.ARID),
    .S_AXI_arregion(S_AXI.ARREGION),
    .S_AXI_awid(S_AXI.AWID),
    .S_AXI_awregion(S_AXI.AWREGION),
    .S_AXI_bid(S_AXI.BID),
    .S_AXI_rid(S_AXI.RID)
  );

endmodule
