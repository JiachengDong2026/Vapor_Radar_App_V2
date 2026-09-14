# FPGA Pre-development Verification

`fpga/sim/common` 提供最小化、无第三方 IP 的验证组件：sample/msg/bulk sink 分别执行 ready/valid 接收、时间戳单调性、fragment 连续性和 frame 完整性检查；`clock_reset_gen` 支持时钟与复位参数化；`wms_reference_stub` 提供冻结的 `scan_start`、`phase_valid`、`cycle_id` 和连续 phase 接口。

实例化 `cfg_bus_master_bfm` 后可调用 `cfg_write(addr,data)` 和 `cfg_read(addr,data)`；两者均等待 `cfg_ack` 并具有超时保护。运行 `fpga/tests/tb_predev_common.v` 覆盖时间基准、配置总线、三类 stream 和 WMS 基本行为，成功时输出 `PREDEV_INTERFACE_TEST_PASS`。
