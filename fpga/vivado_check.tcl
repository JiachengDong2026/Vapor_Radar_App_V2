set files [list rtl/common/clk_rst_mgr.v rtl/common/system_timebase.v rtl/common/cfg_bus_if.v sim/common/wms_reference_stub.v tests/tb_predev_common.v]
foreach f $files { read_verilog -sv $f }
set_part xc7a100tcsg324-1
synth_design -top tb_predev_common -part xc7a100tcsg324-1 -mode out_of_context
exit
