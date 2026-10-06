# 最新下位机代码整合记录（2026-09-30）

## 整合范围

本次以 `E:\Documents\Vapor_Lc_App_v2` 为正式工程，以 `E:\Documents\Vapor_Lc_App_Test` 下的双 AD4630 验证快照、完整系统测试快照和成员测试工程为来源进行核对。正式工程只保留可重建的 RTL、仿真、约束、构建脚本和接口文档；缓存、比特流、DCP、采集文件和 FX3 SDK 生成物继续留在测试目录。

## 已纳入正式工程的内容

- 双低速 AD4630 采集链：`fpga/rtl/adc/adc_ad4630_dual_if.v`。
- 双 AD4630 寄存器、DLIA 封装和顶层选择逻辑：
  - `fpga/rtl/adc/adc_channel_regs.v`
  - `fpga/rtl/adc/member1_adc_dila.v`
  - `fpga/rtl/top/vapor_lidar_top.v`
  - `fpga/rtl/include/register_map.vh`
- 双 AD4630 仿真和系统测试：`fpga/tests/adc_dila/`、`fpga/tests/system/tb_vapor_ad4630_dual_integration.v`。
- AD4630、时钟和顶层管脚约束，以及构建输入清单：`fpga/constraints/`、`fpga/scripts/`。
- 六路传感器、双 DAC/WMS、FX3/GPIF、动作控制和电机控制均已按 V2 目录结构保留在正式工程中。
- 对应接口和版本说明：`Docs/INTEGRATION_REVISION_20260928_DUAL_AD4630.md` 及现有 `Docs/integration/`、`Docs/protocol/`。

## 明确排除的测试快照

- `lead_system/rtl` 的扁平化副本不直接覆盖 V2；其中 `vapor_lidar_top.v` 和 `clk_rst_mgr.v` 与正式工程存在内容差异。
- `member3_uart_sensors` 中使用 RD105/独立 RS485 总线的快照不覆盖当前 V2 的 AI8、EPSILON RS232 和共享总线配置。
- 各成员独立 `*_board_top.v`、独立 XDC、BIT、DCP、`.Xil`、`.work`、Vivado 工程缓存、USB capture 和 FX3 SDK 生成物不复制到正式生产源码目录。

## 文件状态

本次整合保留现有工作树中的用户变更，并补齐双 AD4630 源码、testbench 和文档；未删除已有 V2 文件。测试源与正式源的逐项差异见：
`E:\Documents\Vapor_Lc_App_Test\formal_merge_20260930\REPORT_SOURCE_DIFF.md`。

## 验证要求

整合后依次运行：

```powershell
python fpga/scripts/check_baseline.py
vivado -mode batch -source fpga/vivado_check.tcl
```

完整系统构建使用 `fpga/scripts/run_full_build.tcl`，构建产物输出到 `E:\Documents\Vapor_Lc_App_Test\formal_build`，不写入 V2 源码目录。
