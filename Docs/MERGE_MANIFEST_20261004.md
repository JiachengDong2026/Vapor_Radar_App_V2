# 最新下位机同步记录（2026-10-04）

## 来源与范围

本次将 `E:/Documents/Vapor_Lc_App_Test/dlia_precision_20261002/source` 的已上板版本同步至正式V2。同步前逐文件核对：相对于当前工作树，生产RTL仅 `dila_ref_gen.v`、`dila_core.v` 有差异；六传感器、双低速AD4630、WMS/DAC、FX3/GPIF代码、管脚约束和生产源清单已经一致。保留原有未提交改动，不覆盖其他用户文件。

最新逻辑的参考正弦表增加12位分数相位插值；混频后改用四阶Butterworth低通，1MS/s时截止频率固定1kHz。DLIA ID为00300101/00310101，profile为00040101（12.5MHz设计为00040102）；寄存器布局、VLP格式、引脚及数字比例不变。群延迟和数值响应发生变化，见[精度修订](INTEGRATION_REVISION_20261002_DLIA_PRECISION.md)。

## 文件清单

- 2个生产RTL：`fpga/rtl/dila/dila_core.v`、`dila_ref_gen.v`，与已上板来源逐字节一致。
- 2个精度testbench：`fpga/tests/adc_dila/tb_dila_ref_precision.v`、`tb_dila_filter_precision.v`。
- 4个更新后的黄金期望向量：`fpga/sim/adc_dila/vectors/{numeric,magnitude}_expected_{0,1}.hex`。
- 同步开发指南、架构说明、成员1任务书、双ADC修订、DLIA精度修订、协议正文、上位机交接、ADC/DLIA寄存器附录共8份文档。
- `generate_dlia_precision_vectors.py`及`run_regression.py`自动生成滤波验证数据，生成物全部写至外部回归目录；依赖Python、NumPy、SciPy。
- `cdc_endpoint_baseline.json`归档当前已复核2端点，依据见[CDC基线](integration/CDC_BASELINE_20261004.md)。
- `export_flash_image.tcl`归档当前实际使用的SPIx4、32位地址、10.6MHz配置导出流程，只导出文件，不连接硬件或执行烧写。未纳入未烧写的SPIx1压缩候选。

上述testbench/黄金向量是仓库规范要求的可复现验证源；独立测试工程、生成的hex、仿真缓存、日志、报告大文件、BIT/BIN/MCS/DCP及采集数据均留在Test目录。Flash和FX3 EEPROM是两个不同存储器，脚本导出的是FPGA U2 Flash镜像。

## 验证与限制

本次验证记录：`E:/Documents/Vapor_Lc_App_Test/formal_sync_20261004/REPORT.md`，逐文件清单见同目录 `diff_before.json`及`sync_verification.json`。

正式源码静态检查、公共Vivado仿真/综合及13个相关回归最终通过；滤波精度首次因缺向量失败，补齐自动生成后单独复测通过。参考精度检查1,169,656项，滤波逐位检查243,000输入。CDC对历史已验证报告2/2匹配。Flash导出共用.prm的冲突已修正并恢复BIN导出，FDRI逻辑数据比对一致；保留失败/恢复记录。详见上述Test报告。

代码来源已完成2026-10-02实现及实板激光器采集，2026-10-03完成Flash完整断电自启动和120秒采集。板测范围是CON7对应第一路ADC/DLIA；不能据此宣称六传感器或第二路激光器重新验收。曾出现一次冷启动未完成，完整断电后恢复；根因未确定，不宣称根治。

本次仅源码同步和离线复验，不重新实现新BIT、不连接板卡、不改变现场WMS输出。现有已验证BIT仍位于 `dlia_precision_20261002/build/full_build/vapor_lidar_top.bit`，SHA256 `3a25061d4a744ddf7cce9add925d0ab6e66c16c83acb3250fd6ef963f43006f3`；已烧写Flash镜像位于 `fpga_flash_20261002/vapor_lidar_top_spi4.bit`，SHA256 `ab3e6ca7251d0fa1044bc6d6b0ff8946aa6bc1e3680241f14a9ce7f10b59a585`。两者逻辑配置数据相同，启动设置不同。

已知特殊在途prepared-commit边界仍可能遗漏mixer内部valid_product；沿用停机、排空、复位、配置、启动流程。对应历史分析位于 `dlia_precision_20261002/reference_validation/FOLLOWUP_PIPELINE_IDLE.md`，本次未扩大算法修改。

未提交或推送Git；现有工作树中的历史未提交内容不代表本轮全部修改。

## 复现入口

在V2根目录执行（路径替换为本机安装位置，输出必须是新的外部目录）：

```powershell
python -B fpga/scripts/check_baseline.py
python -B fpga/scripts/run_regression.py --output E:/Documents/Vapor_Lc_App_Test/next_precision_check --vivado-bin D:/Software/Vivado/Vivado/2020.2/bin tb_dila_ref_precision tb_dila_filter_precision tb_dila_numeric
```

公共模块使用 `fpga/vivado_check.tcl`，通过环境变量 `VAPOR_BUILD_ROOT`指定Test下输出；从Test工作目录启动Vivado，避免日志写回V2。完整实现仍使用 `fpga/scripts/build.py --output <新Test目录> --vivado <vivado.bat>`。

Flash导出：从Test工作目录启动Vivado，`-source <V2>/fpga/scripts/export_flash_image.tcl -tclargs <已验证routed.dcp> <新Test输出目录>`。导出后应重新检查文件和配置参数，不能把导出成功当作物理断电启动验收。
