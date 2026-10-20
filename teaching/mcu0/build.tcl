# MCU-0 bitstream, non-interactive:
#   vivado -mode batch -source build.tcl -tclargs <core-dir> <blink.hex> <out-dir> [part]
# <core-dir> holds the core's .v files (your teaching/work/cpu, or rtl/cpu for the reference core).
# Produces <out-dir>/mcu_board.bit and the timing/utilisation reports. Not run in this repository's CI.
set core_dir [lindex $argv 0]
set hex      [file normalize [lindex $argv 1]]
set out      [file normalize [lindex $argv 2]]
set part     [expr {[llength $argv] > 3 ? [lindex $argv 3] : "xc7z020clg400-1"}]
set here     [file dirname [file normalize [info script]]]
set rtl      [file normalize "$here/../../rtl/cpu"]

file mkdir $out
create_project -force mcu0 $out/vivado -part $part
add_files [glob $core_dir/*.v]
add_files [list $here/mcu_top.v $here/mcu_router.v $here/mcu_ram.v $here/mcu_clint.v $here/mcu_gpio.v $here/mcu_board.v]
set_property include_dirs [list $rtl $core_dir] [current_fileset]
add_files -fileset constrs_1 $here/pynq-z1.xdc
set_property top mcu_board [current_fileset]
set_property generic "INIT_HEX=\"$hex\"" [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synthesis failed" }
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "implementation failed" }
open_run impl_1
report_timing_summary -file $out/timing.rpt
report_utilization -hierarchical -file $out/utilization.rpt
file copy -force $out/vivado/mcu0.runs/impl_1/mcu_board.bit $out/mcu_board.bit
puts "MCU0_BUILD_OK $out/mcu_board.bit"
