# 4.11 时间同步测试：启动观测输出（2026-11-19）

## 范围与版本

在2026-11-16 PPS单次扫描源码上增加三个真实事件观测输出，供测试大纲4.11使用。此次不增加双通道共同触发门控、PPS诊断记录FIFO、UTC锚定或新的上行数据格式；沿用现有独立通道调度和PPS/cycle寄存器。固件身份需记录源码版本及后续构建BIT的SHA256，历史BIT不包含本功能。

## 接线

| 端口 | 板卡位置 | FPGA ball | 电气 |
|---|---|---|---|
| ADC_START | CON11-12 | AL12 | Bank88、LVCMOS33、8mA、SLOW |
| DLIA1_START | CON11-14 | AE13 | Bank88、LVCMOS33、8mA、SLOW |
| DLIA2_START | CON11-16 | AF13 | Bank88、LVCMOS33、8mA、SLOW |

三针从预留GPIO分配，不占用两路TEC103 UART、HC2A、电机或I2C。CON11没有GND，示波器参考地接已确认板卡地，例如CON21-4；采用高阻探头，不接50欧姆并联终端。接线前确认预留针脚无额外线束连接。

## 精确事件定义

事件在生产100MHz系统域采样，输出上升沿与被观测事件发生在同一系统时钟沿；寄存器到输出焊盘、PCB、探头及门限的传播延迟计入实际示波器读数。

- ADC_START：双AD4630接口实际发出CNV，并且该次转换同时是两路各自PPS窗口中的首个有效采样。要求两ADC逻辑通道均启用，两路均为PPS模式且窗口有效。两路分别按各自cycle变化识别首采样，cycle_id不必因历史启动次数不同而相等。
- 两路首采样落在不同CNV、单通道工作、一路连续/一路PPS、窗口外后台采样时，不产生共用ADC_START；不会在较晚一路开始时伪造共同首样本。无ADC_START属于测试条件不满足或同步异常，不能作为零延时通过。
- DLIA1_START：source0030/core0实际接受本次PPS窗口第一个有效输入样本的握手沿；DLIA2_START对应source0031/core1。
- DLIA事件包含真实enable、burst窗口、参考有效、采样率有效和ready/cooldown约束，不由PPS、scan_start或enable复制。样本尚未交到DLIA时不提前发出。
- 连续模式没有PPS启动观测脉冲。legacy ADC3660分支不产生ADC_START；4.11使用正式双AD4630顶层。

每个独立窗口最多产生一次对应事件。两DLIA输出独立，可观察单路缺失或时差。ADC继续连续CNV，观测输出只标识窗口首采样，不改变物理采样时钟。

## 脉宽与复位

宏`MEASUREMENT_START_PULSE_US=10`定义标称脉宽。模块按`ceil(SYS_CLK_HZ * PULSE_US / 1000000)`计算时钟数，生产100MHz时为1000拍、10us。三路分别计时，上升沿不增加额外流水拍。高电平时的重复事件被忽略，不延长脉宽、不排队；正常1PPS满足事件间隔要求，不能用展宽信号统计超过其分辨能力的高频重复事件。

观测模块使用ADC子系统复位；复位立即清低并清除计数，可截短正在输出的脉冲。普通扫描结束/STOP不提前结束观测脉冲。ADC/DLIA的软件清空语义沿用原模块；活动窗口清空或重配置不作为正常同步测量条件。

## 4.11 测试条件与证据

1. 两路DAC/ADC/DLIA提前初始化并完成commit；双路WMS设置PPS单次模式。两路使用一致的DAC SPI时序、更新率和初始事务状态，PPS前确认均armed。此次没有增加全局共同触发门控，独立就绪仍可能造成单路漏触发。
2. TIME使用上升沿；冷启动至少四个有效PPS，按大纲在连续正常PPS后测量。窗口内不写配置、不清FIFO、不执行软件复位。
3. 实测标定CON7/8等待0V、首点1V。WMS启动按模拟输出首次向上越过0.5V测量，不能用数字DAC应用tick替代。
4. 第一种接线：CH1=CON22 PPS，CH2/3=CON7/8，CH4=CON11-12。第二种：CH1=PPS，CH2=CON11-12，CH3=CON11-14，CH4=CON11-16。数字脉冲取实际高低电平中点的上升沿。
5. 辅助传感器、USB接收及保存持续开启；两种接线各5次。全部启动延时非负，所有启动延时及各次事件最大时差的最大值小于1ms，核对漏触发、重复触发和序号对应错误为0。
6. 沿用WMS的LAST_PPS_SEQ、cycle_id和ACTUAL_START/END建立关联，按原规范在完成后、下次覆盖前取一致快照。示波器波形不携带PPS序号，须另存截图/波形与序号记录；本次GPIO不自动完成关联存储。

DLIA_START测开始处理；低通群延迟、滤波建立时间、扫描收集和USB到达延时不由START信号测量。此修订不等于已通过4.11验收。

## 实现、测试与版本记录

事件源：`adc_ad4630_dual_if.v`、`dila_core.v`；展宽：`measurement_start_outputs.v`；连线：`member1_adc_dila.v`和`vapor_lidar_top.v`。头文件、两套正式源清单及管脚/时序约束同步更新。

新增`tb_measurement_start_outputs`验证10us宽度、三路独立、重复事件不展宽、复位及重触发；`tb_adc_measurement_start`验证连续/窗口外抑制、共同CNV、错位/单路抑制和cycle回绕。扩展`tb_pps_adc_dlia`核对真实采样/握手及两次扫描，扩展`tb_pps_vapor_top`核对顶层管脚及不合格PPS抑制。`check_measurement_start.tcl`提供100MHz综合/布局布线smoke及timing/CDC/check_timing报告，整机综合smoke使用生产顶层和新端口。

2026-11-19：新增观测输出源码、约束、头文件、回归和本规范。2026-11-20完成下述首轮验证；生成物均放外部Test目录。后续整机实现及BIT状态见下节；尚未进行实板4.11验收。

### 已完成的验证

- `python -B fpga/scripts/check_baseline.py`：`BASELINE_STATIC_CHECK_PASS`。
- 最终源码10项Vivado/XSim专项及相关回归全部通过：`tb_measurement_start_outputs`、`tb_adc_measurement_start`、`tb_pps_adc_dlia`、`tb_pps_vapor_top`、`tb_ad4630_dual`、`tb_dila_core`、`tb_pps_wms_dlia`、`tb_vapor_ad4630_dual_integration`、`tb_pps_calibration`、`tb_member1_adc_dila`。目录`E:/Documents/Vapor_Lc_App_Test/start_outputs_final_focus_20261119`包含`results.json`、日志和`source_sha256.json`。不是完整115项回归。
- 公共Vivado检查：`PREDEV_COMMON_V12_VIVADO_CHECK_DONE`；目录`E:/Documents/Vapor_Lc_App_Test/start_outputs_common_20261119`保留公共仿真、综合、timing、CDC、check_timing及资源报告。
- 新模块100MHz OOC布局布线：`MEASUREMENT_START_OOC_PASS`；WNS=7.542ns、WHS=0.047ns、TNS/THS=0；39 LUT、33寄存器、无锁存器；DRC零违例。目录`E:/Documents/Vapor_Lc_App_Test/start_outputs_ooc_20261119/measurement_start_ooc`。
- OOC `check_timing`无no_clock、无未约束内部端点、无未约束输出；独立复位端口`rst_n`使用false path，报告一个no_input_delay例外。CDC有33条CDC-26 Warning，逐行均为独立`rst_n`到33个寄存器CLR的复位路径；生产顶层复用ADC子系统复位，不据此宣称整机CDC零告警。
- 正式顶层整机综合：`FULL_SYSTEM_BUILD_PASS mode=synth-only`，0 Error、0 Critical Warning、332 Warning；检查点为`E:/Documents/Vapor_Lc_App_Test/start_outputs_full_synth_20261119/full_build/synth.dcp`。综合结束时106项输入一致性检查通过，最终131项构建输入及250项回归源码哈希复核通过；该综合结果不代替整机布局布线后的时序收敛。
- 综合后实际端口核对：`MEASUREMENT_START_PIN_AUDIT_PASS pre_route_only`；三路管脚、电平、8mA和SLOW均与上表一致。加载正式整机时序约束后，ADC_START、DLIA1_START、DLIA2_START的建立时间余量分别为3.367ns、3.302ns、3.392ns（布线前估计，不能当作实测延迟）。NSTD-1、UCIO-1、BIVC-1三项I/O DRC零违例；`check_timing`无缺失时钟、未约束内部端点或未约束普通输出，仅转发时钟`FPGA_GPIF_PCLK`列为一个no_output_delay低等级条目。报告位于`E:/Documents/Vapor_Lc_App_Test/start_outputs_full_synth_20261119/start_pin_audit`。

### 2026-11-23 整机时序修复

首轮整机实现于11月20日在布线阶段中断，无BIT；11月23日核对输入哈希并从本轮`placed.dcp`续跑。续跑脚本及封存记录位于外部目录`start_outputs_full_synth_20261119/resume_20261123`，保留原始脚本和检查点哈希；`full_resolved.xdc`属于续跑正常重写的生成文件，其重写前后哈希另行留档，生产约束输入没有改变。

续跑完成284642/284642条网络布线、路由错误0，23条已审阅Gray同步器端点经局部重布线后WHS=0.001ns、THS=0；但WNS=-0.508ns、TNS=-993.560ns，5263个setup端点仍违例，因此`FULL_SYSTEM_BUILD_FAIL: Full top timing failed`，未写BIT。CDC两项与此前PPS版本逐字段完全一致（既有CDC-10 Critical一项、CDC-3 Info一项）；此失败轮不作为时序通过证据。

最差路径由`ref_phase`经过参考插值及混频乘法器，共33级组合逻辑。修复在`dila_core`内将插值后的四路参考值寄存，再进入混频器；样本及194位捕获标签同步延迟一拍，参考值和样本数值算法不变。100MHz时从输入接收到混频结果增加10ns，输入吞吐间隔及三个START事件定义不变。新增流水有效位覆盖寄存参考值及混频乘积的在途周期，配置切换、扫描边界和STOP排空都等待这些在途样本；复位清空，PPS新窗口清除旧参考有效位。

`tb_dila_reference_alignment`以四分之一周期相位的解析值核对正负样本、舍入、标签对齐、STOP排空及复位恢复。修复后116项全量Vivado/XSim回归全部通过（`FORMAL_REGRESSION_PASS count=116`），250项RTL/测试/模型输入哈希与当前文件一致；证据目录`E:/Documents/Vapor_Lc_App_Test/start_outputs_pipeline_full_regression_20261123`。公共Vivado检查再次通过，证据目录`start_outputs_pipeline_common_20261123`。新增用例第一轮因测试配置误用默认格式而拒绝配置，已修正为支持IQ格式的`OUTPUT_FORMAT=1`；失败日志保留，最终全量回归采用修正后的用例。修复后从综合重新构建，输出目录`start_outputs_pipeline_build_20261123`；首轮已通过结果不能替代修复后的检查。

### 最终BIT与签核（2026-11-23）

Vivado 2020.2对`xcku11p-ffva1156-2-i`完成全新综合、布局、物理优化和布线，输出`FULL_SYSTEM_BUILD_PASS`；写BIT前及写出后131项构建输入一致性检查通过。BIT生成完成于2026-11-23 17:48，尚未下载或烧录，尚未实板验证4.11。

| 项目 | 最终结果 |
|---|---|
| BIT | `E:/Documents/Vapor_Lc_App_Test/start_outputs_pipeline_build_20261123/full_build/vapor_lidar_top.bit` |
| 大小 | 23581028字节 |
| BIT SHA256 | `21f786684b501f91d7254f68e9a207aeaecc0ce4c8d9d44ba176177406346b4a` |
| routed.dcp SHA256 | `af3d657299ec276f2480e7f67b987e5937efee2126220c77aff02e2955236fd8` |
| setup | WNS=+0.009ns、TNS=0，370330端点中失败0 |
| hold | WHS报告值=0.000ns、THS=0，370316端点中失败0 |
| 路由 | 283954/283954条可布线网络完成，路由错误0 |
| 脉宽 | 失败端点0 |
| DRC | 最终routed报告4861条Warning，0 Error、0 Critical Warning；写BIT时DRC为4851条Warning、0 Error |
| check_timing | 无缺失时钟、未约束内部端点、缺失输入延迟或普通输出延迟；仅转发时钟FPGA_GPIF_PCLK为预期no_output_delay条目 |
| DAC/AD4630管脚预算 | 检查通过，最小余量分别7.409ns、2.571ns |
| bus skew | 无违例，报告最小余量7.627ns |

时序余量很小，特别是hold报告值舍入到0.000ns；这些数值是当前源码、约束、工具和布局的静态签核结果，不能外推到后续构建，也不是实板同步延迟测量。

保持时间修复只对23个已核对的USB/FIFO Gray一级同步端点执行局部重布线，目标延迟根据Fast/Slow角计算，原始时钟、setup/hold及I/O约束未放宽。完整端点、目标和进度保存在`full_build/hold_repair_endpoints.tsv`、`derived_interconnect_targets.tsv`、`pin_route_progress.tsv`。

最终CDC与此前PPS版本逐字段2/2一致：既有CDC-10 Critical一项（GPIF复位链）、CDC-3 Info一项。只读网表审查通过，复核16级ASYNC_REG复位释放链的直接连接和有效时序，并核对PTB210、AI8、EPSILON、SDFM300、HC2A的两级UART同步器。不能表述为CDC零Critical。复核标记为`FORMAL_CDC_NETLIST_REVIEW_PASS memory_entries=0 reset_entries=1`。

三个观测输出最终网表核对通过（`MEASUREMENT_START_ROUTED_PIN_REVIEW_PASS`），实际管脚、电平、8mA和SLOW均符合上表，均由SYS域观测寄存器驱动；ADC_START、DLIA1_START、DLIA2_START的setup余量分别2.495ns、2.471ns、2.706ns，hold余量分别3.769ns、3.823ns、3.662ns。证据在`start_outputs_pipeline_build_20261123/final_cdc_review`，总记录`BUILD_RESULT.json`封存BIT、DCP、实现输入、日志和回归证据的SHA256。

复现时选择新的外部输出目录：

```powershell
python -B fpga/scripts/run_regression.py --output E:/Documents/Vapor_Lc_App_Test/start_outputs_repeat --vivado-bin D:/Software/Vivado/Vivado/2020.2/bin tb_measurement_start_outputs tb_adc_measurement_start tb_pps_adc_dlia tb_pps_vapor_top tb_ad4630_dual tb_dila_core tb_pps_wms_dlia tb_vapor_ad4630_dual_integration tb_pps_calibration tb_member1_adc_dila
$env:VAPOR_BUILD_ROOT='E:/Documents/Vapor_Lc_App_Test/start_outputs_repeat_build'
# Vivado工作目录也应放在上述外部输出目录，避免产生仓库临时文件。
vivado -mode batch -source E:/Documents/Vapor_Lc_App_v2/fpga/vivado_check.tcl
vivado -mode batch -source E:/Documents/Vapor_Lc_App_v2/fpga/scripts/check_measurement_start.tcl
vivado -mode batch -source E:/Documents/Vapor_Lc_App_v2/fpga/scripts/run_full_build.tcl -tclargs synth-only
```
