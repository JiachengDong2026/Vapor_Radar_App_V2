# TASK-PREDEV-004 完成报告

## 1. 修改文件

- `fpga/rtl/include/stream_defs.vh`：冻结 16 位 source/msg ID、64 位 timestamp、32 位 cycle ID/flags。
- `fpga/sim/common/sample_stream_sink.v`：引用冻结的 sample data/timestamp 位宽定义。
- `fpga/sim/common/msg_stream_sink.v`：统一字段位宽，增加 timestamp 单调性检查和十六进制 ID 输出。
- `fpga/sim/common/bulk_stream_sink.v`：增加完整 bulk 元数据、frame、fragment 连续性与元数据一致性检查。
- `fpga/sim/common/wms_reference_stub.v`：替换概念混乱的旧输出，采用冻结 WMS 参考接口。
- `fpga/sim/common/cfg_bus_master_bfm.v`：改为可实例化 module，提供带 ack 等待和 timeout 的 `cfg_write`/`cfg_read`。
- `fpga/vivado_check.tcl`：移除绝对路径，按脚本位置解析仓库根目录，并使用目标器件 XCKU11P-2FFVA1156I。
- `fpga/tests/tb_predev_common.v`：扩展 timebase、cfg bus、sample、msg、bulk 五类自动检查。
- `Docs/FPGA/predev_verification.md`：同步公共验证组件及 PASS 标识。
- `Docs/FPGA/predev_interface_freeze_v1.1.md`：新增冻结接口唯一参考文档。

## 2. 修改原因与接口变化

原有 `source_id/msg_id` 为 8 位、flags 为 16 位，会截断冻结协议字段；bulk sink 缺少 cycle/fragment 元数据；cfg BFM 只有游离 task；WMS stub 使用了废弃概念；Vivado 脚本绑定开发机绝对路径。本次修正保持系统架构不变，未新增正式功能模块。

冻结后的公共宽度为：source_id 16 位、msg_id 16 位、timestamp 64 位、cycle_id 32 位、flags 32 位。DILA/RAW ADC 使用独立 bulk_stream，一个 frame 对应一个 fragment，并显式携带 fragment index/count。

## 3. 仿真结果

目标 testbench：`tb_predev_common`；成功标识：`PREDEV_INTERFACE_TEST_PASS`。

覆盖场景：1000-cycle timebase 增量；cfg write/read/invalid address；100 个带 timestamp 的 sample；HMP/EPSILON 16 位 source/msg ID；cycle_id=100、fragment_count=4、index 0..3 的 DILA frames。

当前执行环境未安装或未暴露 Vivado、xvlog、xsim、Icarus Verilog、Verilator/Yosys，因此无法在本机实际启动 HDL 编译器。已完成静态接口复核和 `git diff --check`；动态仿真状态记为 **未执行（工具缺失）**，不能虚报 PASS。克隆到 Vivado 环境后运行：

```text
vivado -mode batch -source fpga/vivado_check.tcl
```

## 4. 公共接口冻结状态

sample_stream、msg_stream、bulk_stream、source_id、msg_id、timestamp、cycle_id 和 fragment 规则已在 V1.1 文档中冻结。后续三成员应直接引用该规范，不再自行定义或改变公共字段。当前无系统架构变更，无新增 USB、FX3、packetizer、stream arbiter、sensor hub、register crossbar、ADC、DAC、WMS 或正式 DILA 模块。
