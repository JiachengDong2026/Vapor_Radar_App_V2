# Repository Guidelines

## Project Structure & Module Organization

这是面向 Xilinx XCKU11P-2FFVA1156I 的 Verilog-2001 FPGA 工程。可复用 RTL 位于 `fpga/rtl/common`，全局宏、寄存器和错误码位于 `fpga/rtl/include`。公共仿真模型、BFM 和 checker 位于 `fpga/sim/common`；回归 testbench 与综合 smoke top 位于 `fpga/tests`。`fpga/scripts` 保存静态检查脚本，`fpga/vivado_check.tcl` 是 Vivado 验证入口，报告输出到 `fpga/reports`。需求、接口和开发规范集中在 `Docs/`，修改接口前先查阅对应文档。

## Build, Test, and Development Commands

在仓库根目录执行：

```bash
python fpga/scripts/check_baseline.py
vivado -mode batch -source fpga/vivado_check.tcl
```

前者检查必需文件、冻结 ID/位宽及基础 Verilog 结构，并应输出 `BASELINE_STATIC_CHECK_PASS`。后者运行公共 behavioral simulation、out-of-context synthesis、timing、CDC、`check_timing` 和 utilization 检查；需要已配置好的 Vivado 环境，并在 `fpga/reports` 生成报告。

## Coding Style & Naming Conventions

RTL 使用 Verilog-2001，保持 4 空格缩进和小写下划线模块名，文件名与模块名一致。沿用现有端口命名，如 `s_valid`、`m_ready` 和低有效复位 `rst_n`。公共宏使用全大写下划线（例如 `BULK_DATA_WIDTH`），常量和寄存器地址集中维护在 include 文件中。复用既有 FIFO、CDC、stream 和配置总线模块。仓库未配置统一格式化工具，编辑时遵循相邻代码风格。

## Testing Guidelines

每个新增模块应配套独立 testbench，采用 `tb_<模块名>.v` 命名，优先复用 `fpga/sim/common` 的 BFM、sink 和时钟模型。使用 Vivado behavioral simulation，覆盖正常握手、背压、复位、边界条件及错误路径；公共接口变更须同时更新仿真和综合 smoke test。仓库未规定量化覆盖率门槛。提交前至少运行 `check_baseline.py`，涉及公共 RTL 时再运行完整 Vivado 检查；静态通过不能替代动态验证，未运行的检查应明确说明。

## Commit & Pull Request Guidelines

近期提交采用简短、祈使式英文主题（如 `Add project README`、`Remove generated FPGA reports`），一条提交聚焦一个逻辑变更。PR 应说明影响的 RTL/接口、验证命令及结果，链接相关任务或文档；若涉及波形、时序或资源变化，附上报告路径或关键摘要。不要提交生成的 Vivado 工程、临时文件或大体积报告，除非任务明确要求。

## Documentation and Interface Changes

修改公共 stream、寄存器、数据格式、时序语义或硬件管脚时，必须同步更新 `Docs/` 中的规范、头文件、testbench 和版本记录，确保文档、RTL 与验证环境保持一致。
