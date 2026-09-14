set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT [file normalize [file join $SCRIPT_DIR ..]]
set REPORT_DIR "$ROOT/fpga/reports"
file mkdir $REPORT_DIR

set common_rtl [list \
 "$ROOT/fpga/rtl/common/cdc_bit_sync.v" \
 "$ROOT/fpga/rtl/common/cdc_pulse_sync.v" \
 "$ROOT/fpga/rtl/common/cdc_bus_handshake.v" \
 "$ROOT/fpga/rtl/common/sync_fifo.v" \
 "$ROOT/fpga/rtl/common/async_fifo_wrap.v" \
 "$ROOT/fpga/rtl/common/sample_stream_fifo.v" \
 "$ROOT/fpga/rtl/common/msg_stream_fifo.v" \
 "$ROOT/fpga/rtl/common/bulk_stream_fifo.v" \
 "$ROOT/fpga/rtl/common/cfg_bus_if.v"]

set sim_files [list \
 "$ROOT/fpga/sim/common/clock_reset_gen.v" \
 "$ROOT/fpga/sim/common/time_sync_stub.v" \
 "$ROOT/fpga/sim/common/wms_reference_stub.v" \
 "$ROOT/fpga/sim/common/cfg_bus_master_bfm.v" \
 "$ROOT/fpga/sim/common/sample_stream_sink.v" \
 "$ROOT/fpga/sim/common/msg_stream_sink.v" \
 "$ROOT/fpga/sim/common/bulk_stream_sink.v" \
 "$ROOT/fpga/tests/tb_predev_common.v"]

create_project -in_memory -part xcku11p-ffva1156-2-i
set_property target_language Verilog [current_project]
set_property include_dirs [list "$ROOT/fpga/rtl/include"] [get_filesets sources_1]
set_property include_dirs [list "$ROOT/fpga/rtl/include"] [get_filesets sim_1]

# Behavioral regression.
add_files -fileset sources_1 $common_rtl
add_files -fileset sim_1 $common_rtl
add_files -fileset sim_1 $sim_files
set_property top tb_predev_common [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim

# Out-of-context synthesis smoke test for the reusable common RTL.
add_files -fileset sources_1 "$ROOT/fpga/tests/common_synth_smoke.v"
set_property top common_synth_smoke [get_filesets sources_1]
update_compile_order -fileset sources_1
synth_design -top common_synth_smoke -part xcku11p-ffva1156-2-i
create_clock -name clk_a -period 10.000 [get_ports clk_a]
create_clock -name clk_b -period 14.000 [get_ports clk_b]
set_clock_groups -asynchronous -group [get_clocks clk_a] -group [get_clocks clk_b]
report_timing_summary -file "$REPORT_DIR/common_timing_summary.rpt"
report_cdc -details -file "$REPORT_DIR/common_cdc.rpt"
check_timing -verbose -file "$REPORT_DIR/common_check_timing.rpt"
report_utilization -file "$REPORT_DIR/common_utilization.rpt"

puts "PREDEV_COMMON_V12_VIVADO_CHECK_DONE"
exit
