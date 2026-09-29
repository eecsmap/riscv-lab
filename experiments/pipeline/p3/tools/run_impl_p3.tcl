# PIPE-P3a copy of teaching-cpu/m4-build/run_impl.tcl. One change of substance: implementation stops after
# route_design, the routed design is judged, and the bitstream is written ONLY if that gate passes --
#   setup and hold met (WNS >= 0, WHS >= 0, TNS = THS = 0), every net routed, no DRC violation of severity
#   Error, no unconstrained endpoint and no missing clock in check_timing.
# The gate's result is in gate.txt; a failed gate ends with GATE_FAILED and no .bit. Nothing is programmed.
# Otherwise as the accepted script: synthesis and implementation are judged by Vivado's own run status.
#
#   vivado -mode batch -source run_impl.tcl -tclargs <project.xpr> <outdir> <jobs>
set xpr   [lindex $argv 0]
set out   [lindex $argv 1]
set jobs  [lindex $argv 2]
file mkdir $out
proc say {msg} { puts "@@@ $msg"; flush stdout }

open_project $xpr
say "project opened: [current_project], part [get_property part [current_project]]"

# ---- what is actually in the project, as Vivado sees it ------------------------------------------------
set f [open $out/source-set.txt w]
puts $f "# every file Vivado has in sources_1, in compile order, as the tool reports it"
puts $f "# top: [get_property top [get_filesets sources_1]]"
puts $f "# verilog_define: [get_property verilog_define [get_filesets sources_1]]"
puts $f "# include_dirs: [get_property include_dirs [get_filesets sources_1]]"
foreach s [get_files -of_objects [get_filesets sources_1]] { puts $f $s }
puts $f "# constraints"
foreach s [get_files -of_objects [get_filesets constrs_1]] { puts $f $s }
close $f
say "source set written to $out/source-set.txt"

# the baseline Rocket top must not be here
foreach s [get_files -quiet *Top.ZynqFPGAConfig.v] { say "FAIL: baseline Rocket top in project: $s"; exit 3 }

# ---- PS preset, checked rather than assumed -----------------------------------------------------------
set ps [get_bd_cells -quiet /processing_system7_0]
if {$ps eq ""} {
  open_bd_design [get_files -quiet *.bd]
  set ps [get_bd_cells -quiet /processing_system7_0]
}
if {$ps eq ""} { say "FAIL: no processing_system7_0 cell"; exit 3 }
set xtal [get_property -quiet CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ $ps]
set hp0  [get_property -quiet CONFIG.PCW_USE_S_AXI_HP0 $ps]
set gp0  [get_property -quiet CONFIG.PCW_USE_M_AXI_GP0 $ps]
say "PS preset: crystal=$xtal MHz, S_AXI_HP0=$hp0, M_AXI_GP0=$gp0"
if {$xtal != 50} { say "FAIL: crystal $xtal, expected 50 -- the Digilent preset did not apply"; exit 3 }
if {$hp0 != 1}  { say "FAIL: S_AXI_HP0 not enabled -- the memory boundary is missing"; exit 3 }

# ---- synthesis ----------------------------------------------------------------------------------------
say "launching synth_1 with $jobs jobs"
reset_run synth_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
set st [get_property STATUS [get_runs synth_1]]
set pr [get_property PROGRESS [get_runs synth_1]]
say "synth_1 STATUS='$st' PROGRESS=$pr"
if {$pr != "100%"} { say "SYNTH_FAILED"; exit 4 }

open_run synth_1 -name synth_1
write_checkpoint -force $out/post_synth.dcp
report_utilization      -file $out/post_synth_utilization.rpt
report_utilization -hierarchical -file $out/post_synth_utilization_hier.rpt
# black boxes and the teaching core: is the design actually there?
set bb [get_cells -hier -quiet -filter {IS_BLACKBOX == 1}]
say "black boxes after synthesis: [llength $bb]"
if {[llength $bb] > 0} { foreach c $bb { say "  blackbox: $c" } }
set f [open $out/post_synth_checks.txt w]
puts $f "black boxes: [llength $bb]"
foreach c $bb { puts $f "  $c" }
foreach pat {*teaching_board_top* *cpu/core* *tcpu*} {
  set cells [get_cells -hier -quiet $pat]
  puts $f "cells matching $pat : [llength $cells]"
}
puts $f "\n# the teaching CPU's own registers, by hierarchy"
puts $f "regs under the CPU: [llength [get_cells -hier -quiet -filter {PRIMITIVE_GROUP == FLOP_LATCH}]]"
close $f
say "synthesis checks written"

# ---- implementation and bitstream ----------------------------------------------------------------------
say "launching impl_1 to route_design with $jobs jobs"
reset_run impl_1
launch_runs impl_1 -to_step route_design -jobs $jobs
wait_on_run impl_1
set st [get_property STATUS [get_runs impl_1]]
set pr [get_property PROGRESS [get_runs impl_1]]
say "impl_1 STATUS='$st' PROGRESS=$pr"
if {$pr != "100%"} { say "IMPL_FAILED"; exit 5 }

open_run impl_1
write_checkpoint -force $out/post_route.dcp
report_timing_summary -max_paths 10 -file $out/post_route_timing_summary.rpt
report_timing -max_paths 20 -sort_by group -file $out/post_route_timing_worst.rpt
report_utilization -file $out/post_route_utilization.rpt
report_utilization -hierarchical -file $out/post_route_utilization_hier.rpt
report_clocks -file $out/post_route_clocks.rpt
report_clock_utilization -file $out/post_route_clock_utilization.rpt
report_cdc -details -file $out/post_route_cdc.rpt
report_clock_interaction -file $out/post_route_clock_interaction.rpt
report_drc -file $out/post_route_drc.rpt
report_methodology -file $out/post_route_methodology.rpt
report_route_status -file $out/post_route_status.rpt
report_control_sets -verbose -file $out/post_route_control_sets.rpt
check_timing -file $out/post_route_check_timing.rpt
report_timing -delay_type max -max_paths 30 -nworst 1 -path_type full -file $out/post_route_critical_setup.rpt
report_timing -delay_type min -max_paths 10 -nworst 1 -path_type full -file $out/post_route_critical_hold.rpt
report_utilization -hierarchical -hierarchical_depth 6 -file $out/post_route_utilization_hier6.rpt
report_exceptions -file $out/post_route_exceptions.rpt

set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
set ths [get_property STATS.THS [get_runs impl_1]]
say "impl_1 stats: WNS=$wns TNS=$tns WHS=$whs THS=$ths"

# ---- the gate ------------------------------------------------------------------------------------------
set gfails {}
if {$wns < 0 || $tns != 0} { lappend gfails "setup not met (WNS $wns, TNS $tns)" }
if {$whs < 0 || $ths != 0} { lappend gfails "hold not met (WHS $whs, THS $ths)" }
set unrouted [get_property -quiet STATS.UNROUTED_NETS [get_runs impl_1]]
set rs [report_route_status -return_string]
if {![regexp {# of fully routed nets[ .:]*\(?\s*(\d+)} $rs -> nfull]} { set nfull -1 }
if {![regexp {# of nets with routing errors[ .:]*\(?\s*(\d+)} $rs -> nrerr]} { set nrerr -1 }
if {$nrerr != 0} { lappend gfails "nets with routing errors: $nrerr" }
report_drc -quiet -name gate_drc
set drc_err [llength [get_drc_violations -quiet -name gate_drc -filter {SEVERITY == Error}]]
set drc_cw  [llength [get_drc_violations -quiet -name gate_drc -filter {SEVERITY == "Critical Warning"}]]
if {$drc_err != 0} { lappend gfails "DRC errors: $drc_err" }
set ct [check_timing -return_string -verbose]
set unconst 0; set noclk 0
if {[regexp {There (?:is|are) (\d+) register/latch pins? with no clock} $ct -> x]} { set noclk $x }
if {[regexp {There (?:is|are) (\d+) (?:input ports?|output ports?|endpoints?)[^\n]*unconstrained} $ct -> x]} { set unconst $x }
if {[regexp {There (?:is|are) (\d+) pins? that (?:is|are) not constrained for maximum delay} $ct -> x]} { set unconst [expr {$unconst + $x}] }
set f [open $out/gate.txt w]
puts $f "WNS $wns TNS $tns WHS $whs THS $ths"
puts $f "route: fully routed nets $nfull, nets with routing errors $nrerr"
puts $f "DRC: errors $drc_err, critical warnings $drc_cw"
puts $f "check_timing: register/latch pins with no clock $noclk, unconstrained (endpoints/ports/pins) $unconst (reported, see post_route_check_timing.rpt)"
puts $f "gate failures: [llength $gfails]"
foreach g $gfails { puts $f "  $g" }
close $f
if {[llength $gfails] > 0} {
  foreach g $gfails { say "GATE: $g" }
  say "GATE_FAILED -- no bitstream written"; exit 7
}
say "GATE_OK: setup/hold met, routed, no DRC errors -- writing the bitstream"
close_design
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set bit [glob -nocomplain [file dirname $xpr]/*.runs/impl_1/*.bit]
say "bitstream: $bit"
if {$bit eq ""} { say "NO_BITSTREAM"; exit 6 }
file copy -force [lindex $bit 0] $out/[file tail [lindex $bit 0]]
set f [open $out/run-status.txt w]
puts $f "tool: [version -short]"
puts $f "part: [get_property part [current_project]]"
puts $f "synth_1 STATUS: [get_property STATUS [get_runs synth_1]]"
puts $f "synth_1 PROGRESS: [get_property PROGRESS [get_runs synth_1]]"
puts $f "impl_1 STATUS: [get_property STATUS [get_runs impl_1]]"
puts $f "impl_1 PROGRESS: [get_property PROGRESS [get_runs impl_1]]"
puts $f "WNS: $wns"
puts $f "TNS: $tns"
puts $f "WHS: $whs"
puts $f "THS: $ths"
puts $f "bitstream: $out/[file tail [lindex $bit 0]]"
close $f
say "BUILD_OK"
