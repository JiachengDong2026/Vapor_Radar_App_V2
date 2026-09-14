set files [list E:/Documents/Vapor_Lc_App_v2/fpga/rtl/common/clk_rst_mgr.v E:/Documents/Vapor_Lc_App_v2/fpga/rtl/common/system_timebase.v E:/Documents/Vapor_Lc_App_v2/fpga/rtl/common/cfg_bus_if.v E:/Documents/Vapor_Lc_App_v2/fpga/sim/common/wms_reference_stub.v E:/Documents/Vapor_Lc_App_v2/fpga/tests/tb_predev_common.v]
foreach f $files { read_verilog -sv $f }
set_part xc7a100tcsg324-1
synth_design -top tb_predev_common -part xc7a100tcsg324-1 -mode out_of_context
exit
