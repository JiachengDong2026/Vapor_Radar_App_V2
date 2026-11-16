# Synthesize and route the complete programmable DLIA core in isolation.
# No pin/board signoff: this checks the 100 MHz internal programmable datapath.
set root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists ::env(VAPOR_BUILD_ROOT)]} {error "Set external VAPOR_BUILD_ROOT"}
set out [file normalize "$::env(VAPOR_BUILD_ROOT)/dlia_ooc"]
file mkdir $out
cd $out
create_project -in_memory -part xcku11p-ffva1156-2-i
set_property include_dirs [list "$root/rtl/include" "$root/rtl/dila"] [current_fileset]
read_verilog [glob "$root/rtl/dila/*.v"]
synth_design -top dila_core -mode out_of_context -part xcku11p-ffva1156-2-i -generic {USE_CAPTURE_TAGS=1 OUTPUT_FORMAT=1}
create_clock -name sys_clk -period 10.000 [get_ports sys_clk]
set_false_path -from [get_ports rst_sys_n]
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file "$out/timing.rpt"
report_utilization -file "$out/utilization.rpt"
report_drc -file "$out/drc.rpt"
check_timing -verbose -file "$out/check_timing.rpt"
write_checkpoint -force "$out/routed.dcp"
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup]==0 || [get_property SLACK $setup]<0} {error "DLIA setup timing failure"}
if {[llength $hold]==0 || [get_property SLACK $hold]<0} {error "DLIA hold timing failure"}
puts "DLIA_SOS_OOC_PASS"
exit
