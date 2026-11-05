# MCU-0 on the PYNQ-Z1. Clock and pin names follow the board's master XDC; verify against your board revision.
set_property PACKAGE_PIN H16 [get_ports clk]
set_property IOSTANDARD LVCMOS33 [get_ports clk]
create_clock -name gclk_0 -period 8.000 -waveform {0.000 4.000} [get_ports clk]

set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN P14 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN N16 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

set_property -dict {PACKAGE_PIN D19 IOSTANDARD LVCMOS33} [get_ports {btn[0]}]
set_property -dict {PACKAGE_PIN D20 IOSTANDARD LVCMOS33} [get_ports {btn[1]}]
set_property -dict {PACKAGE_PIN L20 IOSTANDARD LVCMOS33} [get_ports {btn[2]}]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports {btn[3]}]

set_property -dict {PACKAGE_PIN M20 IOSTANDARD LVCMOS33} [get_ports {sw[0]}]
set_property -dict {PACKAGE_PIN M19 IOSTANDARD LVCMOS33} [get_ports {sw[1]}]

# Pmod JA: only the Pmod VGA uses it (mcu_board PMOD_VGA = 1): red on pins 1-4, blue on pins 7-10, bit 0 first.
set_property -dict {PACKAGE_PIN Y18 IOSTANDARD LVCMOS33} [get_ports {ja[0]}]
set_property -dict {PACKAGE_PIN Y19 IOSTANDARD LVCMOS33} [get_ports {ja[1]}]
set_property -dict {PACKAGE_PIN Y16 IOSTANDARD LVCMOS33} [get_ports {ja[2]}]
set_property -dict {PACKAGE_PIN Y17 IOSTANDARD LVCMOS33} [get_ports {ja[3]}]
set_property -dict {PACKAGE_PIN U18 IOSTANDARD LVCMOS33} [get_ports {ja[4]}]
set_property -dict {PACKAGE_PIN U19 IOSTANDARD LVCMOS33} [get_ports {ja[5]}]
set_property -dict {PACKAGE_PIN W18 IOSTANDARD LVCMOS33} [get_ports {ja[6]}]
set_property -dict {PACKAGE_PIN W19 IOSTANDARD LVCMOS33} [get_ports {ja[7]}]
# the VGA signals leave flip-flops; a few ns of skew between them is far below a 25 ns pixel
set_false_path -to [get_ports {ja[*]}]

# Pmod JB, GPIO OUT[15:8]: jb[0..3] = pins 1-4 (top row), jb[4..7] = pins 7-10 (bottom row), as in the master XDC.
# With a Pmod OLEDrgb: CS, MOSI, (NC), SCK / D/C, RES, VCCEN, PMODEN (teaching/oled/README.md).
# With PMOD_VGA = 1 (Pmod VGA across JA + JB): green on pins 1-4, HSYNC pin 7, VSYNC pin 8.
set_property -dict {PACKAGE_PIN W14 IOSTANDARD LVCMOS33} [get_ports {jb[0]}]
set_property -dict {PACKAGE_PIN Y14 IOSTANDARD LVCMOS33} [get_ports {jb[1]}]
set_property -dict {PACKAGE_PIN T11 IOSTANDARD LVCMOS33} [get_ports {jb[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {jb[3]}]
set_property -dict {PACKAGE_PIN V16 IOSTANDARD LVCMOS33} [get_ports {jb[4]}]
set_property -dict {PACKAGE_PIN W16 IOSTANDARD LVCMOS33} [get_ports {jb[5]}]
set_property -dict {PACKAGE_PIN V12 IOSTANDARD LVCMOS33} [get_ports {jb[6]}]
set_property -dict {PACKAGE_PIN W13 IOSTANDARD LVCMOS33} [get_ports {jb[7]}]
# the outputs are slow software-driven levels: no output timing to meet
set_false_path -to [get_ports {jb[*]}]

# the buttons and switches are asynchronous inputs, synchronised inside mcu_gpio / the reset synchroniser
set_false_path -from [get_ports {btn[*] sw[*]}]
