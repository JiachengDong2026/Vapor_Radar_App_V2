# 下位机最新正式版本说明（2026-11-13）

## 1. 交付身份与同步范围

V2 已合入最近实测使用的 **HC2A GPIO RH 修正版（HCD2）**。源码来自外部测试目录 `hc2a_gpio_20261028_01/rh_case_fix_01/repo`，BIT 为 2026-10-28 构建、2026-11-12 继续实测使用的同一文件。2026-11-13 是正式归档日期，不是新综合或硬件验收日期。

- 器件：Xilinx XCKU11P-2FFVA1156I；RTL：Verilog-2001；工具：Vivado 2020.2。
- [正式 BIT 与校验文件](../firmware/fpga/releases/20261113_hc2a_rhfix/README.md)：`vapor_lidar_hc2a_gpio_rhfix_20261028.bit`，23,581,028 bytes。
- SHA256：`e5d0c1f691fd7a47cf83c108612f51d518f886ca57e7ca9a363f69c619c2f8a6`。
- 128 个构建输入（RTL、头文件、ROM、约束和脚本）与该 BIT 原始源码清单逐字节一致。合入 29 个新增或变化的 FPGA 文件，同时同步接口文档；另将旧HMP传感器整合testbench显式设为 `HC2A_ENABLE=0`，修正其模型与默认模式不一致的问题。生产构建输入及BIT未改变。
- 保留 V2 已有 LC 双 UART、GNSS PPS/UTC、DM422、AI8 实测基线及 2026-11-10 电机窗口和装配方向记录。FX3 固件本次没有改动。
- 本次不操作硬件，不重新实现 BIT，不写 FPGA Flash/FX3 EEPROM。

## 2. 当前功能与接口

| 功能 | 当前实现与使用边界 |
|---|---|
| HC2A 温湿度 | 默认替换逻辑 HMP lane 1；独立 CON11 GPIO UART；兼容 `%RH` 和实际探头 `%rh`；只读 RDD 请求，无探头标定/参数写入 |
| HMP 兼容模式 | 源码保留 `HC2A_ENABLE=0`；必须另行构建，当前归档 BIT 为 HC2A 模式 |
| AI-8 | CON19 Modbus RTU，19200/8N1、地址1、默认通道1；schema 2，主机禁用后选择1..8通道；保留设温写后读回，不支持已撤回的自动扫描/通用参数事务 |
| EPSILON | CON14 MAIN RS232，921600/8N1；保留接收和下行/RTCM邮箱；卫星定位/UTC/PPS有效性须分别判断 |
| 统一时间 | CON22 PPS频率校准、显式UTC锚点；无有效PPS不宣称绝对时间同步 |
| DM422 | 有限脉冲运动、方向/启停、真实主机心跳与2秒看门狗；软件脉冲计数不代表机械位置 |
| LC双路激光UART | CON11 pin5/7为LC0、pin6/8为LC1；可配置原始字节收发，厂家命令由主机生成；默认禁用 |
| TFA/PTB/BMP/SHT | 保留TFA的CON21和CON11-4、PTB的CON25及原I2C接口；BMP实物地址0x77需禁用时配置 |
| ADC/DLIA、WMS/DAC | 保留双AD4630、DLIA精度及截止频率扩展和双WMS/DAC；本次不扩大模拟链路验收结论 |
| USB | CON23；04B4:00F1；OUT 0x02、IN 0x86；VLP1帧格式保持不变 |

扩展能力 word 维持 `0x29`；新设备应按各页 ID 识别，不能仅凭历史设备名称选择初始化流程。原 HMP 的 source `0x0041`、page `0x6100`、RH/T F32 TLV schema 1 由 HC2A 复用；HC2A ID 为 `0x00410106`，0x614C 为 HCD2 `0x48434432`。**不能执行旧 HMP 的压力补偿/COMMIT 或 ACTION16。** 部分旧分析器仍显示“HMP”，不代表板上使用HMP协议。

HC2A 接线：独立稳压3.3V接探头pin1；pin2与电源负极、板卡GND共地；CON11-13/AK13（板TX）接探头pin3 RXD；CON11-15/AL13（板RX）接pin4 TXD。CON11没有电源/地，CON21-3是EN；GPIO为3.3V TTL，不能直接接24V、5V TTL或RS232电平。完整针脚、寄存器、地址发现及诊断定义见[HC2A规范](integration/sensors/HC2A_ROASCII.md)。

## 3. 上电与使用顺序

1. 先核对 BIT SHA256、器件和实际接线。该镜像在近期测试中通过 JTAG 加载到 FPGA SRAM；没有固化到 Flash，断电后需确认 DONE 和固件身份，不能假定仍运行 HCD2。
2. 使用匹配的 FX3 GP01 USB 桥及驱动；如处于 USB Boot，按 [FX3说明](../firmware/fx3/README.md)加载配套固件。FPGA BIT 和 FX3 IMG 为两个独立固件。
3. 读模块ID和状态，确认目标设备均禁用；按设备规范配置，再显式启用。HC2A默认19200/8N1、地址99发现、轮询等待1000ms、响应超时600ms、重试1次。99只用于单探头发现，成功后学习实际地址。
4. HC2A先读0x6100和0x614C，配置后写0x6104=1；检查online、成功计数0x6144、RH/T及错误增量；结束写0x6104=0。错误寄存器为粘滞历史状态，应结合计数和online判断。
5. AI8逐通道采集需先禁用0x6604，再写0x661C，最后启用。设备报警下的PV不能当成真实温度。电机操作见[窗口说明](integration/MOTOR_PANEL_20261110.md)，PPS/UTC及DM422寄存器见[整机接口](integration/GNSS_PPS_DM422_20261027.md)。

## 4. 构建与验证证据

原 BIT 实现：全新 RTL 综合，使用已审查 HCD1 routed DCP 作增量物理参考（参考SHA256 `e911bef04f5dfede3945a80d26f2e7994ff3ae6ba390d4745636ff37a7b3f6ec`）。最终 WNS **+0.079ns**、WHS **+0.003ns**，布线完整，DRC Error/Critical Warning为0，check_timing、脉宽及ADC/DAC管脚检查通过。CDC端点清单与基线一致，历史1个CDC-10 Critical复位链和1个CDC-3 Info已作结构复核。

原增量流程有76条工具Critical Warning：`Project 1-1108` 1条、`Vivado_Tcl 4-425` 75条，涉及复用效率及旧物理优化变换未重放；未通过关闭时钟不确定度或跳过最终关卡消除。它们与最终DRC违规不同，不表述为“零工具告警”。原构建/CDC证据保留在外部 `hc2a_gpio_20261028_01/rh_case_fix_01/{build_01,cdc_review}`。

本次正式同步已完成：静态检查 `BASELINE_STATIC_CHECK_PASS`、20项主机单元测试、BIT及128项源码输入核验、公共Vivado behavioral仿真/OOC综合及报告生成。公共未布局smoke的WNS为+8.439ns、WHS为-0.087ns，存在hold违例，不能将脚本完成标记当作整机实现时序通过；整机签核依据上文归档BIT的路由后报告。

完整RTL回归最终 **103/103通过**，包括HC2A正常/故障/真实报文、HMP兼容、AI8、LC、PPS/电机、双ADC/DLIA和WMS/DAC。初次分组的两个包装测试因未编入其引用的testbench而elaboration失败，补齐同组依赖后通过；旧HMP整合测试因新版默认HC2A模式拒绝旧配置，显式选择HMP后通过。失败及复测日志均保留。简明逐项结果见[validation.json](../firmware/fpga/releases/20261113_hc2a_rhfix/validation.json)。日志、波形和缓存统一位于外部 `Vapor_Lc_App_Test/formal_sync_20261113/`。

复现命令（输出目录必须不存在，路径按本机调整）：

```powershell
python -B firmware/fpga/verify_release.py
python -B fpga/scripts/check_baseline.py
python -B -m unittest discover -s host -p 'test_*.py'
$env:VAPOR_BUILD_ROOT = 'E:/Documents/Vapor_Lc_App_Test/next_common'
vivado -mode batch -nojournal -source fpga/vivado_check.tcl
python -B fpga/scripts/run_regression.py --output E:/Documents/Vapor_Lc_App_Test/next_regression --vivado-bin D:/Software/Vivado/Vivado/2020.2/bin
```

按名称筛选Vivado测试时，包装testbench与其引用的testbench须一同列入参数（例如 `tb_hc2a_ai8_tfa tb_hc2a_ai8_independent`）；不传测试名的完整回归会编译全部测试。

生产源清单为 `fpga/scripts/full_sources.tcl` 与 `sources.json`，不得把两个同名 `clk_rst_mgr.v` 同时递归加入工程。需要全新实现时使用 `fpga/scripts/build.py --output <新Test目录> --vivado <vivado.bat>`，随后按 CDC 端点及网表脚本复核；新构建产生的新 BIT 不能自动继承旧镜像的实板验收。

## 5. 最近实板结论（历史证据汇总）

以下均使用同一 `e5d0…c2f8a6` 镜像，不是本次同步重新做的实板测试。

| 日期 / 设备 | 已证实 | 未证实或已知限制 |
|---|---|---|
| 11-12 HC2A替换探头 | 约60秒55条有效记录；20.65～20.68°C、57.98～58.16%RH；超时/checksum/格式/UART/丢记录增量均0；475个USB帧CRC正确 | 绝对精度、长期稳定性未验证 |
| 11-12 AI8重接线 | 8路依次查询，每路8次、总计64次成功；CRC/超时/丢记录增量0；693个USB帧CRC正确 | 只有CH3当时无已定义输入错误，约21.5°C；其余通道911.0为故障PV，不能视作真实温度；未验收温控闭环 |
| 11-12 EPSILON | 60.023秒保存43,878条导航记录，USB 46,139帧CRC正确，保存序列连续 | 卫星数0、UTC/导航初始化无效、PPS计数0；FPGA计数比保存记录多60，统计范围未完全对齐，不宣称端到端零丢失 |
| 11-10 DM422 | 有限40脉冲动作完成，结束禁用且电机ERROR=0；后续+2000脉冲用户确认上移接入方向 | 未标定端点、绝对距离和机械位置；计数不是反馈；不能据此验收重配置瞬态和所有失联工况 |
| 11-11 双WMS/DAC | 数字配置恢复，周期/写计数递增，相关错误和饱和/夹限计数0 | 实际模拟波形仍待示波器确认；不宣称模拟输出通过 |

可追溯证据目录（均相对于外部 `Vapor_Lc_App_Test`）：`hc2a_replacement_20261112_01`、`ai8_rewired_20261112_01`、`epsilon_reconnect_20261112_01`、`motor_restore_test_20261110_223159`、`motor_5mm_20261110_225453`、`dac_saw_restore_20261111_143523`。同期部分记录保留SYSTEM sticky ERROR=`0x00000009`，不能从单模块成功推断整机无错误。

## 6. 正式目录与版本规则

`fpga/rtl`、`constraints`、`tests`、`sim`、`scripts` 分别保存可维护源文件；`Docs/` 保存规范和精简说明；`host/` 保存工具源码；`firmware/fx3/` 保存FX3自有增量；`firmware/fpga/releases/` 保存本次明确要求的BIT及其清单。

临时图像、PDF中间文件、日志、缓存和测试输出归入外部Test目录。本次将原V2根目录的 `output/`、`tmp/`、`.pytest_cache/`、`.Xil/` 、两处Python `__pycache__/` 和Vivado/webtalk日志原样迁入 `formal_sync_20261113/existing_generated/`；未删除原始内容。同步前工作树修改已备份到同目录 `backup/`，另有 `changes_before.patch` 与 `status_before.txt`。个人资料和与本次发布无关的未跟踪文件不纳入提交。

2026-10-28候选/诊断文档保留为历史过程记录；本说明与HC2A正式接口规范为当前入口。旧HMP、自动扫描/RD105、早期接线和旧BIT说明不得覆盖本版身份及能力边界。


2026-11-14 源码修订：AI8 扫描/schema3 已按 `Docs/protocol/AI8_SCAN_CONTRACT_20261114.md` 实现；通用参数事务和 RD105 仍不支持。此修订不改变本文旧镜像的验收结论，新 BIT 尚受目标器件包缺失阻塞。

2026-11-14 构建续验：Enterprise Vivado 2025.1 已识别 KU11P，但源 a40f2ed 的整机与公共综合均因 Synthesis/xcku11p 许可证 checkout 失败（Common 17-345）停止。未生成新 BIT，WNS/TNS、DRC、CDC 无新结果。详细证据及目录见 `Docs/protocol/AI8_SCAN_CONTRACT_20261114.md` 的 Enterprise 构建续验节。

2026-11-14 最终续验：AI8扫描新镜像已在独立同轮重新签核后生成；接口能力0x2B，默认schema2，扫描schema3。BIT不入库。许可证路径与checker预算问题已解决，原失败证据保留。

2026-11-14 后续实板加载：北京时间16:52:16，SHA256为 `b3de7ad484a442db20bc86e7e0425a6c912b5fc6a8d961e5c7103460c353adab` 的新BIT已通过JTAG加载到唯一XCKU11P的易失SRAM，DONE/EOS及配置错误检查通过；未写Flash/FX3 EEPROM。随后WinUSB只读身份检查通过：`04B4:00F1`、GP01/0x10AC、capability扩展0x2B、AI8 feature0x0B，AI8禁用且扫描为0；151帧CRC错误0。USB已释放，八路实物采集尚未启用或验收，旧镜像的历史板测结论不自动延续。证据见 [AI8构建与加载记录](protocol/AI8_BUILD_QUALIFICATION_20261114.md)，原始日志及生成物仅留本机Test目录。

2026-11-14 DM422范围修订：有限相对目标扩到±1..5000，默认40及20..400Hz/2秒真实心跳等保持。新生产BIT、独立CDC审阅和验证记录见 `Docs/integration/DM422_5000_20261114.md`，未加载/未实板验收，不覆盖本文件旧镜像验收。
