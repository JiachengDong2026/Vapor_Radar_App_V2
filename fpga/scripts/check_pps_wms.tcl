# Route both WMS/DAC channels with the optional PPS interface present.
# Internal timing only; no board/pad or full-system signoff is claimed.
set root [file normalize [file join [file dirname [info script]] ..]]
if {![info exists ::env(VAPOR_BUILD_ROOT)]} {error "Set external VAPOR_BUILD_ROOT"}
set out [file normalize "$::env(VAPOR_BUILD_ROOT)/wms_ooc"]
file mkdir $out
cd $out
create_project -in_memory -part xcku11p-ffva1156-2-i
set_property include_dirs [list "$root/rtl/include"] [current_fileset]
read_verilog [glob "$root/rtl/wms/*.v"]
read_verilog "$root/rtl/dac/dac_ad5791_if.v"
file copy -force "$root/rtl/wms/sine_q31.mem" "$out/sine_q31.mem"
synth_design -top wms_dac_dual -mode out_of_context -part xcku11p-ffva1156-2-i
create_clock -name sys_clk -period 10.000 [get_ports sys_clk]
set_false_path -from [get_ports rst_sys_n]
opt_design
place_design
phys_opt_design
route_design
report_timing_summary -file "$out/timing.rpt"
report_utilization -file "$out/utilization.rpt"
report_drc -file "$out/drc.rpt"
report_cdc -details -file "$out/cdc.rpt"
check_timing -verbose -file "$out/check_timing.rpt"
write_checkpoint -force "$out/routed.dcp"
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup]==0 || [get_property SLACK $setup]<0} {error "PPS WMS setup timing failure"}
if {[llength $hold]==0 || [get_property SLACK $hold]<0} {error "PPS WMS hold timing failure"}
puts "PPS_WMS_OOC_PASS"
exit
