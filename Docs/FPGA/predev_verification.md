# FPGA Pre-development Verification

`fpga/sim/common` 提供最小化、无第三方 IP 的验证组件：sample/msg/bulk sink 分别执行 ready/valid 接收、时间戳单调性和 frame 完整性检查；`clock_reset_gen` 支持时钟与复位参数化；`wms_reference_stub` 提供连续 phase、sample_enable 及周期起始脉冲。

在包含 `clk` 与 cfg 信号的 testbench 中加入 `cfg_bus_master_bfm.v` 即可调用 `cfg_write(addr,data)` 和 `cfg_read(addr,data)`。运行 `fpga/tests/tb_predev_common.v` 覆盖时间基准、配置总线和 WMS 基本行为，成功时输出 `PREDEV_COMMON_TEST_PASS`。
