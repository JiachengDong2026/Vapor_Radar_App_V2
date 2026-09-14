set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT [file normalize [file join $SCRIPT_DIR ..]]
set rtl_files [list \
 "$ROOT/fpga/rtl/common/clk_rst_mgr.v" \
 "$ROOT/fpga/rtl/common/system_timebase.v" \
 "$ROOT/fpga/rtl/common/cfg_bus_if.v"]
set sim_files [list \
 "$ROOT/fpga/sim/common/cfg_bus_master_bfm.v" \
 "$ROOT/fpga/sim/common/sample_stream_sink.v" \
 "$ROOT/fpga/sim/common/msg_stream_sink.v" \
 "$ROOT/fpga/sim/common/bulk_stream_sink.v" \
 "$ROOT/fpga/sim/common/wms_reference_stub.v" \
 "$ROOT/fpga/tests/tb_predev_common.v"]
create_project -in_memory -part xcku11p-ffva1156-2-i
set_property include_dirs [list "$ROOT/fpga/rtl/include"] [get_filesets sim_1]
add_files -fileset sim_1 $rtl_files
add_files -fileset sim_1 $sim_files
set_property top tb_predev_common [get_filesets sim_1]
launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
exit
