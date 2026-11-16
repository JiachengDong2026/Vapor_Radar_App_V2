# DLIA SOS 上传功能修改与验证记录

日期：2026-11-16。开发基线为正式仓库 `7cf6986`（2026-11-13 最新正式下位机源码）。本次先在外部隔离副本 `Vapor_Lc_App_Test/filter_coeff_upload_20261116/` 修改、仿真和检查；只有 RTL、主机参考实现、协议文档及验证源计划进入正式源码目录。Vivado工程、DCP、波形、回归日志和临时输出留在外部 Test 目录。

## 修改范围

- DLIA原两节固定级联扩为四节固定流水，支持一般`b0/b1/b2/a1/a2`；二至八阶（含奇数阶）可用，每次改变滤波配置时清历史，旧默认四阶系数逐位兼容。
- 新增两路独立SOS shadow/active寄存器、紧凑signed48 Q2.46系数银行、阶数/采样率/截止频率元数据、状态/版本/生效序号。VLP1及模块ID/global capability word未改。
- FPGA在commit时检查30字完整上传、阶数和一阶节位置、单位填充节、二阶节分母Schur稳定条件、Fs和Fc/Nyquist约束；参数在停用或周期边界原子切换。运行中采样率偏离声明时停止该DLIA的新输入并置ERROR bit8。
- 新增Python/SciPy Butterworth SOS生成器，负责统一节增益、Q2.46量化、稳定性复核及寄存器word打包。生成工具不访问设备，不含USB动作。
- 新增详尽的[SOS主机对接规范](protocol/DLIA_SOS_HOST_HANDOFF_20261116.md)，更新寄存器表、VLP历史章节、BIN元数据说明。
- 新增系数配置/非法参数/周期边界测试、VLP完整寄存器上传/回读/背压/权限/双通道隔离测试，以及逐位整数模型精度测试。

## 验证结果

证据目录位于 `E:/Documents/Vapor_Lc_App_Test/` 的 `filter_coeff_*_20261116`：

- 静态检查：`BASELINE_STATIC_CHECK_PASS`。
- 主机Python测试：23 tests通过；频响覆盖500k/1M/12.5M、100/1250/10000Hz和2～8阶63组合。
- `tb_dila_sos_precision`：42配置、86,016样本、四节/IQ/tag和逐级饱和逐位比较。
- `tb_dila_sos_transport`：VLP `cmd_decoder`端到端，覆盖30字批量写/读、ACK背压、来源权限、双通道隔离和生效序号/阶数/profile回读。
- `tb_dila_coeff_upload`：2～8阶、不稳定极点、奇数节形状、未完整上传、只读/未对齐、pending冲突、输入率变化、旧内置恢复。
- DLIA OOC最终源码综合布局布线：27,408 LUT、20,621 FF、747 DSP、32 RAMB36；最终布线 WNS `+0.091ns`、WHS `+0.040ns`，无失败时序端点。DRC无error/critical warning；另有2348项DSP input/output pipelining和无负载warning，需结合顶层实现继续审查。OOC无板级I/O延迟，不能替代整机时序/CDC/DRC签核。
- Vivado完整RTL回归：106/106项通过，逐项结果见`E:/Documents/Vapor_Lc_App_Test/filter_coeff_final_all_20261116/results.json`。
- 完整系统顶层synth-only：通过，`FULL_SYSTEM_BUILD_PASS mode=synth-only`；综合报告0 error、0 critical warning、669 warning。不代表完整布局布线/bitstream通过。
- 公共behavioral/OOC smoke：通过，`PREDEV_COMMON_V12_PASS`及`PREDEV_COMMON_V12_VIVADO_CHECK_DONE`。

## 交付边界

归档BIT `firmware/fpga/releases/20261113_hc2a_rhfix/vapor_lidar_hc2a_gpio_rhfix_20261028.bit`不含本次修改，SHA不应被更新或继续标称匹配新源码。此次修改不包含主机Qt控件/实际USB上传执行器，不进行实板操作，也不宣称新BIT、滤波性能、长期稳定性或真实ADC率切换已实物验收。主机开发需按SOS API ID `0x534F5301`接入；系数参考工具生成数据，主机需自行回读后再单独commit。

生成可下板的新BIT前，仍需整机布局布线、CDC/DRC及管脚时序签核和真实主机联调。新BIT单独归档并更新发布身份/完整源码输入校验。本记录保留旧2026-11-13版本和BIT历史身份。本次合入仅同步验证通过的文件，不创建Git提交或推送。

## 复现命令

在隔离源码根目录执行，以下输出目录均应采用未使用的新名称；不要把完整回归输出放到源码树内。

```powershell
python -B fpga/scripts/check_baseline.py
python -B -m unittest discover -s host -p 'test_*.py'
python -B fpga/scripts/run_regression.py --output E:/Documents/Vapor_Lc_App_Test/next_sos_regression --vivado-bin D:/Software/Vivado/Vivado/2020.2/bin

$env:VAPOR_BUILD_ROOT='E:/Documents/Vapor_Lc_App_Test/next_sos_checks'
& 'D:/Software/Vivado/Vivado/2020.2/bin/vivado.bat' -mode batch -nojournal -log E:/Documents/Vapor_Lc_App_Test/next_sos_common.log -source fpga/vivado_check.tcl
& 'D:/Software/Vivado/Vivado/2020.2/bin/vivado.bat' -mode batch -nojournal -log E:/Documents/Vapor_Lc_App_Test/next_sos_ooc.log -source fpga/scripts/check_dlia_sos.tcl

$env:VAPOR_BUILD_ROOT='E:/Documents/Vapor_Lc_App_Test/next_sos_full_synth'
& 'D:/Software/Vivado/Vivado/2020.2/bin/vivado.bat' -mode batch -nojournal -log E:/Documents/Vapor_Lc_App_Test/next_sos_full_synth.log -source fpga/scripts/run_full_build.tcl -tclargs synth-only
```

正式目录只接收源码/验证源/文档；上述命令的日志、工程、DCP和向量应保持在Test目录。本文的synth-only通过标记不表示产生BIT或整机布线时序通过。
