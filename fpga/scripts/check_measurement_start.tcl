# 100 MHz OOC synthesis/route smoke; not full-board pad timing signoff.
set root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists ::env(VAPOR_BUILD_ROOT)]} {error "Set external VAPOR_BUILD_ROOT"}
set out [file normalize "$::env(VAPOR_BUILD_ROOT)/measurement_start_ooc"]
file mkdir $out
cd $out
create_project -in_memory -part xcku11p-ffva1156-2-i
set_property include_dirs [list "$root/rtl/include"] [current_fileset]
read_verilog "$root/rtl/time/measurement_start_outputs.v"
synth_design -top measurement_start_outputs -mode out_of_context -part xcku11p-ffva1156-2-i
create_clock -name sys_clk -period 10.000 [get_ports clk]
set_false_path -from [get_ports rst_n]
set_input_delay -clock sys_clk -max 2.000 [get_ports {start_event[*]}]
set_input_delay -clock sys_clk -min 0.500 [get_ports {start_event[*]}]
set_output_delay -clock sys_clk -max 2.000 [get_ports {start_pulse[*]}]
set_output_delay -clock sys_clk -min 0.000 [get_ports {start_pulse[*]}]
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file "$out/timing.rpt"
report_utilization -file "$out/utilization.rpt"
report_cdc -details -file "$out/cdc.rpt"
report_drc -file "$out/drc.rpt"
check_timing -verbose -file "$out/check_timing.rpt"
write_checkpoint -force "$out/routed.dcp"
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {![llength $setup] || [get_property SLACK $setup]<0} {error "Measurement start setup failure"}
if {![llength $hold] || [get_property SLACK $hold]<0} {error "Measurement start hold failure"}
puts "MEASUREMENT_START_OOC_PASS"
exit
