# 成员开工前置基线 V1.0

本目录已经完成“无需 RTL 编码、但必须先冻结”的前置工作。

## 已完成

1. `COMMON_INTERFACE_SPEC_V1.0.md`
   - `sys_clk/rst_sys_n`
   - 64-bit 时间基准
   - `cfg_bus`
   - `sample_stream`
   - `msg_stream`
   - WMS -> DILA reference
   - `source_id/msg_id`
   - 通用 CONTROL/STATUS/ERROR 语义

2. `REGISTER_MAP_FREEZE_V1.0.md`
   - 全局模块地址页
   - WMS/DAC/ADC/DILA/传感器地址冻结
   - 扩展规则

3. 公共 Verilog header（不是功能 RTL）
   - `rtl/common/project_defs.vh`
   - `rtl/common/stream_defs.vh`
   - `rtl/common/register_map.vh`
   - `rtl/common/error_codes.vh`

## 成员开工规则

- 三位成员开工时必须把上述 header 复制到同一工程版本并只读使用。
- 若任务书与本 V1.0 公共规范在接口命名/位宽/地址上冲突，以本基线为准，并立即向项目负责人报告旧任务书需要修订的位置。
- 不允许成员自行建立第二套 `source_id`、寄存器地址、错误位定义或 WMS phase 编码。
- 项目负责人后续的顶层/crossbar/USB 也必须遵循同一基线。
