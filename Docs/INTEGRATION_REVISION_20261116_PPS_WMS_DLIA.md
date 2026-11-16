# 2026-11-16 PPS—WMS—DLIA 同步扫描修订

## 基线、范围与交付

基于正式目录/GitHub 已合并的 `4b7e9ebc33c1d9c6cead0b3ece1c4ad7a7853b18` 开发，保留此前 DLIA 2～8 阶 SOS、AI8、SDFM300、DM422、TEC103 等功能。开发工作树为 `E:/Documents/Vapor_Lc_App_Test/pps_wms_dlia_20261116`，分支 `codex/pps-wms-dlia`。全部仿真、综合和实现生成物均位于外部 Test 目录。

新增每通道可选 PPS 单次扫描，默认保持原连续模式。一个经过 TIME 资格检查的 PPS 启动一个完整 WMS 锯齿周期，随后写入等待电平，DLIA 依据实际 DAC 生效窗口处理并封帧排空。双通道共用 PPS、独立就绪，没有全局配对门控或触发队列。上位机详细规范见[PPS 对接文档](protocol/PPS_WMS_DLIA_HOST_HANDOFF_20261116.md)。

此次合并仅更新源码、测试源、验证脚本及文档，不生成发布 BIT、不加载 FPGA、不改 Flash，不把旧 BIT 标注为支持本功能；不修改用户已有的未跟踪分析文档或器件资料。源码初次合并至正式目录时未进行 Git commit/push；随后按用户要求提交并同步至 GitHub，提交身份以仓库历史为准。

## 实现变更

| 范围 | 变更 |
|---|---|
| TIME | 导出已有周期校准/新鲜度/时钟正常组合资格；PPS事件和UTC锚定接口保留 |
| WMS | 新增模式、等待电平、就绪/忙状态、接受/漏接/拒收/完成/中止计数及PPS/实际窗口时间戳；上电模式0 |
| DAC | 由样本SPI写入完成反馈应用事件；事务相位/cycle/window标签与该事件对应 |
| ADC | 双AD4630采集就绪反馈；持续CNV及原capture tag机制保留 |
| DLIA | 每个PPS窗口清滤波历史及抽取状态；过滤窗口外样本；有序ADC终止标签和管线排空控制封帧；异常Fs可排空退出 |
| 整机 | TIME→双WMS→ADC/DLIA窗口及ready/drained回路；原连续通路保留 |
| 寄存器 | WMS +4C…+88，API=50505301；既有ID、stream宽度、帧格式及全局扩展位不变 |

WMS/ADC/DLIA仍同属100MHz系统时钟域。PPS使用现有两级同步；未新增跨时钟域直接采样路径或引脚约束。PPS扫描要求正式双AD4630分支，legacy ADC路径的trigger_ready为0。

## 新增与扩展测试

| Testbench | 覆盖 |
|---|---|
| tb_pps_wms_dlia | 默认连续/模式切换、API/错误读写、无PPS等待、不合格拒收、双通道实际起点、16/8更新的完整扫描、最后样本保持、160/80窗口样本、16/8输出点、滤波清零后两次结果一致、忙时漏接、背压收尾、停止中止、SOS采样率故障退出、返回连续 |
| tb_pps_adc_dlia | 实际双AD4630管脚模型、CNV窗口标签、长时间等待不填满fanout FIFO、正常尾帧以及ADC/DLIA/WMS同时停止排空 |
| tb_pps_vapor_top | 物理PPS输入资格、通过真实GPIF/VLP读API/切模式/START/STOP、双通道起点、DLIA分片/CRC/时间戳/cycle、停止尾帧 |
| tb_pps_calibration | 现有TIME测试增加资格输出断言，覆盖初始四沿、异常间隔与超时撤销 |
| tb_time_sync_core | 将旧位置连接改为具名端口连接，适配新增pps_qualified输出；原有TIME断言不变 |

顶层测试仅将 TIME 参数 SYS_CLK_HZ 改为100000以加速PPS间隔仿真；生产参数及 ADC/WMS 系统时钟保持100MHz。该仿真不代表真实1秒长时间保持测试或模拟延迟测量。

## 最终验证记录

最终专项四项通过，输出：`E:/Documents/Vapor_Lc_App_Test/pps_final_focus_20261116`。

静态检查 `python -B fpga/scripts/check_baseline.py` 输出 `BASELINE_STATIC_CHECK_PASS`；主机现有单元测试 `python -B -m unittest discover -s host -p 'test_*.py'` 共26项通过；`git diff --check`通过。

公共 Vivado 检查完成，日志 `E:/Documents/Vapor_Lc_App_Test/pps_common_20261116.log`，标记 `PREDEV_COMMON_V12_VIVADO_CHECK_DONE`；公共仿真、OOC综合、timing、CDC、check_timing、utilization报告保留于 `pps_common_20261116/common`。

WMS双通道 OOC 100MHz 完成综合、优化、布局布线及DRC/CDC/check_timing报告，`PPS_WMS_OOC_PASS`。实际 routed timing.rpt：WNS **3.316 ns**，WHS **0.040 ns**，TNS/THS=0。输出：`E:/Documents/Vapor_Lc_App_Test/pps_wms_ooc_20261116/wms_ooc`。

WMS OOC DRC包含69条Warning：DSP输入/输出流水建议68条，以及1条无可路由负载提示；没有Error级条目。check_timing无no_clock、无内部未约束端点。OOC端口输入/输出延迟未约束是验证范围限制，未宣称板级签核。

WMS OOC CDC报告仍有CDC-1 Critical 7830条、CDC-13 Critical 44条和CDC-26 Warning 260条；逐行核对全部来源为孤立顶层端口rst_sys_n。该OOC未包含整机复位同步产生链，因此保留原报告，不将其称为CDC零告警/整机签核。新增PPS数据在生产顶层来自已同步的TIME输出，同属sys_clk域。

最终DLIA OOC（USE_CAPTURE_TAGS=1、OUTPUT_FORMAT=1）完成100MHz综合、布局布线，`DLIA_SOS_OOC_PASS`。实际 routed timing.rpt：WNS **0.248 ns**，WHS **0.041 ns**，TNS/THS=0。输出：`E:/Documents/Vapor_Lc_App_Test/pps_final_dlia_ooc_20261116/dlia_ooc`。DRC有2349条Warning（2348条DSP流水建议和1条无可路由负载），无Error级条目；OOC端口缺少HD.PARTPIN_LOCS的提示不作为板级接口时序结论。正式OUTPUT_FORMAT=0由整机综合及实际ADC/顶层仿真覆盖。

整机生产顶层综合完成：`FULL_SYSTEM_BUILD_PASS mode=synth-only`，`BUILD_INPUTS_UNCHANGED count=105`，无推断锁存器。日志记录0个Error、0个Critical Warning、674个Warning（未连接/无负载端口、常量化和原有传感器状态pending_mask位宽等提示；不是零告警综合）。输出及冻结输入清单位于 `E:/Documents/Vapor_Lc_App_Test/pps_final_full_synth_20261116/full_build`，日志为同级 `pps_final_full_synth_20261116.log`。

完整回归共113个testbench：`pps_final_regression_20261116`一次运行112个通过，唯一失败为旧`tb_time_sync_core`位置端口连接错位、无法展开，故该轮脚本退出码为1，不能记作一次全绿。仅将该测试改为具名连接，原TIME行为断言不变；独立重跑`pps_time_bench_fix_20261116`通过，最终**113个不同用例全部完成验证**。生产RTL未因测试修正改变；保留原失败日志和复测通过日志，汇总为外部`pps_resolved_regression_20261116.json`，未覆盖失败证据。其余用例均使用最终生产RTL，含连续模式、PPS专项、数值精度、协议、时钟及传感器回归。

长时`tb_vapor_sensor_integration`通过：807帧、所有CRC正确，七路计数20/12/99/5/15/422/3，共享RS485与USB背压恢复检查通过。它验证既有多设备并发路径，不能代替现场吞吐验收。

## 合并与可追溯性

验证结束后按25个文件的清单复制至`E:/Documents/Vapor_Lc_App_v2`，仅包含RTL、测试源、验证脚本、README及接口/修订文档。复制前备份原有文件到`E:/Documents/Vapor_Lc_App_Test/pps_merge_backup_20261116`；新旧文件SHA256、源/目标和保留的6个用户未跟踪文件记录在`pps_merge_manifest_20261116.json`。完整验证源文件哈希保留在`pps_final_source_hashes_20261116.json`。合并检查要求正式HEAD仍为基线、暂存区和已跟踪文件未被其他操作改动；逐文件复制后校验一致性，Git HEAD与暂存区保持不变。

可复现入口（在仓库根目录执行，输出目录必须为新的外部路径）：

```powershell
python -B fpga/scripts/check_baseline.py
python -B -m unittest discover -s host -p 'test_*.py'
python -B fpga/scripts/run_regression.py --output E:/Documents/Vapor_Lc_App_Test/pps_repeat_regression --vivado-bin D:/Software/Vivado/Vivado/2020.2/bin

$env:VAPOR_BUILD_ROOT='E:/Documents/Vapor_Lc_App_Test/pps_repeat_build'
$ppsRepo='E:/Documents/Vapor_Lc_App_v2'
$ppsVivado='D:/Software/Vivado/Vivado/2020.2/bin/vivado.bat'
New-Item -ItemType Directory -Path $env:VAPOR_BUILD_ROOT
Push-Location $env:VAPOR_BUILD_ROOT
& $ppsVivado -mode batch -nojournal -log common.log -source "$ppsRepo/fpga/vivado_check.tcl"
& $ppsVivado -mode batch -nojournal -log wms.log -source "$ppsRepo/fpga/scripts/check_pps_wms.tcl"
& $ppsVivado -mode batch -nojournal -log dlia.log -source "$ppsRepo/fpga/scripts/check_dlia_sos.tcl"
& $ppsVivado -mode batch -nojournal -log full_synth.log -source "$ppsRepo/fpga/scripts/run_full_build.tcl" -tclargs synth-only
Pop-Location
```

## 验证边界

OOC结果仅证明所报告内部100MHz路径的实现；端口未施加板级输入/输出延迟，不能代替整机时序签核。整机此次仅综合，不进行全板布局布线/bitstream发布。公共CDC报告不等于新增整机CDC签核；本次没有改变时钟域架构。

尚未在实板验收：PPS电气/有效沿、DAC模拟等待电压、PPS到模拟扫描延迟及抖动、双路实际偏差、ADC相位/模拟链路延迟、滤波暂态对有效测量区间的影响、UTC锚点和绝对精度、长时USB吞吐及断连恢复。历史板测/旧BIT的证据只覆盖其原版本。
