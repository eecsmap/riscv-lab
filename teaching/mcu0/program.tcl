# Program the PL over JTAG with the hardware manager, leaving the PS alone:
#   vivado -mode batch -source program.tcl -tclargs <bitstream>
# On a Zynq the JTAG chain shows the ARM DAP and the xc7z020; only the latter is programmed.
if {[llength $argv] < 1} { puts "usage: vivado -mode batch -source program.tcl -tclargs <bitstream>"; exit 1 }
set bit [file normalize [lindex $argv 0]]
if {![file exists $bit]} { puts "no such bitstream: $bit"; exit 1 }
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7z020*] 0]
if {$dev eq ""} { puts "no xc7z020 on the JTAG chain: [get_hw_devices]"; exit 1 }
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
refresh_hw_device -quiet $dev
puts "PROGRAMMED $bit -> $dev ([get_property PART $dev])"
close_hw_target
disconnect_hw_server
close_hw_manager
