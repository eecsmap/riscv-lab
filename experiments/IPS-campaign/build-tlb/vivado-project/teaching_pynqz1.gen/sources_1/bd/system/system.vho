-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2026 Advanced Micro Devices, Inc. All Rights Reserved.
-- -------------------------------------------------------------------------------
-- This file contains confidential and proprietary information
-- of AMD and is protected under U.S. and international copyright
-- and other intellectual property laws.
--
-- DISCLAIMER
-- This disclaimer is not a license and does not grant any
-- rights to the materials distributed herewith. Except as
-- otherwise provided in a valid license issued to you by
-- AMD, and to the maximum extent permitted by applicable
-- law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
-- WITH ALL FAULTS, AND AMD HEREBY DISCLAIMS ALL WARRANTIES
-- AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
-- BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
-- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
-- (2) AMD shall not be liable (whether in contract or tort,
-- including negligence, or under any other theory of
-- liability) for any loss or damage of any kind or nature
-- related to, arising under or in connection with these
-- materials, including for any direct, or any indirect,
-- special, incidental, or consequential loss or damage
-- (including loss of data, profits, goodwill, or any type of
-- loss or damage suffered as a result of any action brought
-- by a third party) even if such damage or loss was
-- reasonably foreseeable or AMD had been advised of the
-- possibility of the same.
--
-- CRITICAL APPLICATIONS
-- AMD products are not designed or intended to be fail-
-- safe, or for use in any application requiring fail-safe
-- performance, such as life-support or safety devices or
-- systems, Class III medical devices, nuclear facilities,
-- applications related to the deployment of airbags, or any
-- other applications that could lead to death, personal
-- injury, or severe property or environmental damage
-- (individually and collectively, "Critical
-- Applications"). Customer assumes the sole risk and
-- liability of any use of AMD products in Critical
-- Applications, subject only to applicable laws and
-- regulations governing limitations on product liability.
--
-- THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
-- PART OF THIS FILE AT ALL TIMES.
--
-- DO NOT MODIFY THIS FILE.

-- MODULE VLNV: amd.com:blockdesign:system:1.0

-- The following code must appear in the VHDL architecture header.

-- COMP_TAG     ------ Begin cut for COMPONENT Declaration ------
COMPONENT system
  PORT (
    M_AXI_awaddr : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    M_AXI_awlen : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    M_AXI_awsize : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    M_AXI_awburst : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    M_AXI_awlock : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    M_AXI_awcache : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M_AXI_awprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    M_AXI_awregion : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M_AXI_awqos : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M_AXI_awvalid : OUT STD_LOGIC;
    M_AXI_awready : IN STD_LOGIC;
    M_AXI_wdata : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    M_AXI_wstrb : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M_AXI_wlast : OUT STD_LOGIC;
    M_AXI_wvalid : OUT STD_LOGIC;
    M_AXI_wready : IN STD_LOGIC;
    M_AXI_bresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    M_AXI_bvalid : IN STD_LOGIC;
    M_AXI_bready : OUT STD_LOGIC;
    M_AXI_araddr : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    M_AXI_arlen : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    M_AXI_arsize : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    M_AXI_arburst : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    M_AXI_arlock : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
    M_AXI_arcache : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M_AXI_arprot : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    M_AXI_arregion : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M_AXI_arqos : OUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    M_AXI_arvalid : OUT STD_LOGIC;
    M_AXI_arready : IN STD_LOGIC;
    M_AXI_rdata : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    M_AXI_rresp : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    M_AXI_rlast : IN STD_LOGIC;
    M_AXI_rvalid : IN STD_LOGIC;
    M_AXI_rready : OUT STD_LOGIC;
    S_AXI_awaddr : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    S_AXI_awlen : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    S_AXI_awsize : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    S_AXI_awburst : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    S_AXI_awlock : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    S_AXI_awcache : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    S_AXI_awprot : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    S_AXI_awqos : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    S_AXI_awvalid : IN STD_LOGIC;
    S_AXI_awready : OUT STD_LOGIC;
    S_AXI_wdata : IN STD_LOGIC_VECTOR(63 DOWNTO 0);
    S_AXI_wstrb : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    S_AXI_wlast : IN STD_LOGIC;
    S_AXI_wvalid : IN STD_LOGIC;
    S_AXI_wready : OUT STD_LOGIC;
    S_AXI_bresp : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    S_AXI_bvalid : OUT STD_LOGIC;
    S_AXI_bready : IN STD_LOGIC;
    S_AXI_araddr : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
    S_AXI_arlen : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    S_AXI_arsize : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    S_AXI_arburst : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
    S_AXI_arlock : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
    S_AXI_arcache : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    S_AXI_arprot : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
    S_AXI_arqos : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    S_AXI_arvalid : IN STD_LOGIC;
    S_AXI_arready : OUT STD_LOGIC;
    S_AXI_rdata : OUT STD_LOGIC_VECTOR(63 DOWNTO 0);
    S_AXI_rresp : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
    S_AXI_rlast : OUT STD_LOGIC;
    S_AXI_rvalid : OUT STD_LOGIC;
    S_AXI_rready : IN STD_LOGIC;
    DDR_0_cas_n : INOUT STD_LOGIC;
    DDR_0_cke : INOUT STD_LOGIC;
    DDR_0_ck_n : INOUT STD_LOGIC;
    DDR_0_ck_p : INOUT STD_LOGIC;
    DDR_0_cs_n : INOUT STD_LOGIC;
    DDR_0_reset_n : INOUT STD_LOGIC;
    DDR_0_odt : INOUT STD_LOGIC;
    DDR_0_ras_n : INOUT STD_LOGIC;
    DDR_0_we_n : INOUT STD_LOGIC;
    DDR_0_ba : INOUT STD_LOGIC_VECTOR(2 DOWNTO 0);
    DDR_0_addr : INOUT STD_LOGIC_VECTOR(14 DOWNTO 0);
    DDR_0_dm : INOUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    DDR_0_dq : INOUT STD_LOGIC_VECTOR(31 DOWNTO 0);
    DDR_0_dqs_n : INOUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    DDR_0_dqs_p : INOUT STD_LOGIC_VECTOR(3 DOWNTO 0);
    FIXED_IO_0_mio : INOUT STD_LOGIC_VECTOR(53 DOWNTO 0);
    FIXED_IO_0_ddr_vrn : INOUT STD_LOGIC;
    FIXED_IO_0_ddr_vrp : INOUT STD_LOGIC;
    FIXED_IO_0_ps_srstb : INOUT STD_LOGIC;
    FIXED_IO_0_ps_clk : INOUT STD_LOGIC;
    FIXED_IO_0_ps_porb : INOUT STD_LOGIC;
    FCLK_RESET0_N : OUT STD_LOGIC;
    ext_clk_in : IN STD_LOGIC;
    M_AXI_arid : OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
    M_AXI_awid : OUT STD_LOGIC_VECTOR(11 DOWNTO 0);
    M_AXI_bid : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
    M_AXI_rid : IN STD_LOGIC_VECTOR(11 DOWNTO 0);
    S_AXI_arid : IN STD_LOGIC_VECTOR(5 DOWNTO 0);
    S_AXI_arregion : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    S_AXI_awid : IN STD_LOGIC_VECTOR(5 DOWNTO 0);
    S_AXI_awregion : IN STD_LOGIC_VECTOR(3 DOWNTO 0);
    S_AXI_bid : OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
    S_AXI_rid : OUT STD_LOGIC_VECTOR(5 DOWNTO 0)
  );
END COMPONENT;
-- COMP_TAG_END ------  End cut for COMPONENT Declaration  ------

-- The following code must appear in the VHDL architecture
-- body. Substitute your own instance name and net names.

-- INST_TAG     ------ Begin cut for INSTANTIATION Template ------
your_instance_name : system
  PORT MAP (
    M_AXI_awaddr => M_AXI_awaddr,
    M_AXI_awlen => M_AXI_awlen,
    M_AXI_awsize => M_AXI_awsize,
    M_AXI_awburst => M_AXI_awburst,
    M_AXI_awlock => M_AXI_awlock,
    M_AXI_awcache => M_AXI_awcache,
    M_AXI_awprot => M_AXI_awprot,
    M_AXI_awregion => M_AXI_awregion,
    M_AXI_awqos => M_AXI_awqos,
    M_AXI_awvalid => M_AXI_awvalid,
    M_AXI_awready => M_AXI_awready,
    M_AXI_wdata => M_AXI_wdata,
    M_AXI_wstrb => M_AXI_wstrb,
    M_AXI_wlast => M_AXI_wlast,
    M_AXI_wvalid => M_AXI_wvalid,
    M_AXI_wready => M_AXI_wready,
    M_AXI_bresp => M_AXI_bresp,
    M_AXI_bvalid => M_AXI_bvalid,
    M_AXI_bready => M_AXI_bready,
    M_AXI_araddr => M_AXI_araddr,
    M_AXI_arlen => M_AXI_arlen,
    M_AXI_arsize => M_AXI_arsize,
    M_AXI_arburst => M_AXI_arburst,
    M_AXI_arlock => M_AXI_arlock,
    M_AXI_arcache => M_AXI_arcache,
    M_AXI_arprot => M_AXI_arprot,
    M_AXI_arregion => M_AXI_arregion,
    M_AXI_arqos => M_AXI_arqos,
    M_AXI_arvalid => M_AXI_arvalid,
    M_AXI_arready => M_AXI_arready,
    M_AXI_rdata => M_AXI_rdata,
    M_AXI_rresp => M_AXI_rresp,
    M_AXI_rlast => M_AXI_rlast,
    M_AXI_rvalid => M_AXI_rvalid,
    M_AXI_rready => M_AXI_rready,
    S_AXI_awaddr => S_AXI_awaddr,
    S_AXI_awlen => S_AXI_awlen,
    S_AXI_awsize => S_AXI_awsize,
    S_AXI_awburst => S_AXI_awburst,
    S_AXI_awlock => S_AXI_awlock,
    S_AXI_awcache => S_AXI_awcache,
    S_AXI_awprot => S_AXI_awprot,
    S_AXI_awqos => S_AXI_awqos,
    S_AXI_awvalid => S_AXI_awvalid,
    S_AXI_awready => S_AXI_awready,
    S_AXI_wdata => S_AXI_wdata,
    S_AXI_wstrb => S_AXI_wstrb,
    S_AXI_wlast => S_AXI_wlast,
    S_AXI_wvalid => S_AXI_wvalid,
    S_AXI_wready => S_AXI_wready,
    S_AXI_bresp => S_AXI_bresp,
    S_AXI_bvalid => S_AXI_bvalid,
    S_AXI_bready => S_AXI_bready,
    S_AXI_araddr => S_AXI_araddr,
    S_AXI_arlen => S_AXI_arlen,
    S_AXI_arsize => S_AXI_arsize,
    S_AXI_arburst => S_AXI_arburst,
    S_AXI_arlock => S_AXI_arlock,
    S_AXI_arcache => S_AXI_arcache,
    S_AXI_arprot => S_AXI_arprot,
    S_AXI_arqos => S_AXI_arqos,
    S_AXI_arvalid => S_AXI_arvalid,
    S_AXI_arready => S_AXI_arready,
    S_AXI_rdata => S_AXI_rdata,
    S_AXI_rresp => S_AXI_rresp,
    S_AXI_rlast => S_AXI_rlast,
    S_AXI_rvalid => S_AXI_rvalid,
    S_AXI_rready => S_AXI_rready,
    DDR_0_cas_n => DDR_0_cas_n,
    DDR_0_cke => DDR_0_cke,
    DDR_0_ck_n => DDR_0_ck_n,
    DDR_0_ck_p => DDR_0_ck_p,
    DDR_0_cs_n => DDR_0_cs_n,
    DDR_0_reset_n => DDR_0_reset_n,
    DDR_0_odt => DDR_0_odt,
    DDR_0_ras_n => DDR_0_ras_n,
    DDR_0_we_n => DDR_0_we_n,
    DDR_0_ba => DDR_0_ba,
    DDR_0_addr => DDR_0_addr,
    DDR_0_dm => DDR_0_dm,
    DDR_0_dq => DDR_0_dq,
    DDR_0_dqs_n => DDR_0_dqs_n,
    DDR_0_dqs_p => DDR_0_dqs_p,
    FIXED_IO_0_mio => FIXED_IO_0_mio,
    FIXED_IO_0_ddr_vrn => FIXED_IO_0_ddr_vrn,
    FIXED_IO_0_ddr_vrp => FIXED_IO_0_ddr_vrp,
    FIXED_IO_0_ps_srstb => FIXED_IO_0_ps_srstb,
    FIXED_IO_0_ps_clk => FIXED_IO_0_ps_clk,
    FIXED_IO_0_ps_porb => FIXED_IO_0_ps_porb,
    FCLK_RESET0_N => FCLK_RESET0_N,
    ext_clk_in => ext_clk_in,
    M_AXI_arid => M_AXI_arid,
    M_AXI_awid => M_AXI_awid,
    M_AXI_bid => M_AXI_bid,
    M_AXI_rid => M_AXI_rid,
    S_AXI_arid => S_AXI_arid,
    S_AXI_arregion => S_AXI_arregion,
    S_AXI_awid => S_AXI_awid,
    S_AXI_awregion => S_AXI_awregion,
    S_AXI_bid => S_AXI_bid,
    S_AXI_rid => S_AXI_rid
  );
-- INST_TAG_END ------  End cut for INSTANTIATION Template  ------

-- You must compile the wrapper file system.vhd when simulating
-- the module, system. When compiling the wrapper file, be sure to
-- reference the VHDL simulation library.
