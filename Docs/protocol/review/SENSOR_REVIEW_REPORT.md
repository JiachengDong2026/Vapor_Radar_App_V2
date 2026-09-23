# 六传感器独立核对报告

日期：2026-09-19。工作范围为离线只读源审查和文档交付；新写入仅为 `host_protocol_20260919/review/SENSOR_PAYLOADS.md` 与本文件。未操作USB/串口/JTAG，未下发设温；V2与封存工程未修改。没有加载约96MB的全量sensor_analysis.json。

## 核对结论

六路source/message/schema、TLV类型/长度、小端/符号及当前换算与RTL一致，可按配套SENSOR_PAYLOADS实现上位机。需明确以下集成差异，不能直接把旧解码统计字段当最终产品语义：

1. **AI8 health在线位例外。** `ai8_modbus_rs485.v:86` 将STATUS bit1设为online、bit4设为core_sample_valid；当前 `analyze_sensors.py::decode_health`对全部page统一按bit4计算online，对AI8不正确。测量payload DEVICE_STATUS按bit0解码正确。产品应按page0x66/source0x46使用bit1；不得从summary latest_health.online=false推断AI8通信失败。
2. **AI8报警数据仍是收到的实时数据。** 六路摘要56条AI8 DEVICE_STATUS=1，transport/exception均0，HOST始终0x0200；52条ALARM=0、4条ALARM=0x20，全部flagged恰符合RTL。HOST bit9已由既有板测报告追溯手册为全局报警。严格all_six_have_valid_samples=false表示无“六路全部无flag”的证据，不是缺失第六路。
3. **温控有三层确认。** 普通WRITE_REG无AUTO_COMMIT仅本地cfg ACK；commit之后要FC10写+FC03读回相等才confirmed_count增加。必须结合0x664C bit16/result、0x6654及0x6648。SET_RESULT初值0不可当成功；0x6620为shadow、0x6640为轮询SP，两者不能冒充本次设温确认。现有60秒实测未发送设温且确认计数为0，SP40℃是已有值。
4. **旧RD105文档不能覆盖AI8。** `member3_uart_sensors/docs/MODBUS_INTERFACE.md`中schema1、ACK即active及禁用时可积压commit是旧RD105语义。当前0x00460200使用schema2，禁用commit被拒、pending遇禁用中止，并要求读回验证。
5. **BMP需主机补偿与校准关联。** 0x0100是21字节元数据，0x0101/0102是24位ADC原码。现有analyze_sensors只输出原码；bmp_compensation及plot_six_sensors才转换为Pa/℃。本板地址77已实测，76只是复位值。单路PWR情况下TLV可能只有一项；无校准/无对应温度时不能生成补偿压力。
6. **EPS只显示已解码姿态，不宣称GNSS有效。** 完整FDILink帧内数据从offset7起；AHRS ID41/L48的姿态在内部offset12/16/20，F32弧度。现有analyze_sensors仅保留payload_hex，plot脚本才解析角度。手册11.2.2核对通过。本次UTC初始化false；有效CRC仅证明通信。
7. **metadata和flag可同时存在。** 当前analyze_sensors对BMP校准优先分类metadata，即使外层flag欠佳仍归metadata；生产解析器还应保留health_reasons/CRC/flags，不能把metadata类别当可信保证。未知tag/枚举的兼容策略须明确；当前解析器遇未知type即报错。
8. **外层bit0是timestamp有效，不是万能sample有效。** PTB任意sticky错误、SHT heater、AI8报警均有不同bit4来源；overflow bit3表示之前丢记录。通用“flagged”只是保守统计，界面应保留当前值与具体原因。
9. **采样时间语义不同。** AI8时间为完整七读完成时，SHT为测量触发时，BMP为INT或raw请求时；PTB/EPS/TFA为串口帧起始。旧通用“所有串口都是响应首字节”的描述不适用于AI8。共同100MHz时间轴不是零延迟同步采样承诺。

## 实测证据及界限

引用 `fx3_gpif_debug_20260918/reports/sensor_six_60s_01/sensor_summary.json`：7,278,076字节，SHA256 `dfd3602bbf5b19c44606c045c4aa3eaf2f999360b0d12252390d2302e6a9a5b2`，91,087帧全部CRC正确，无framing issue；86,944 valid_sample、56 flagged_sample、1 metadata、4,041 health、45 other/diagnostic。

| 源 | 样本/元数据 | 摘要证明的物理值/状态 |
|---|---|---|
| PTB210 | 57 | 101444..101462 Pa |
| EPSILON | 44629 | 内CRC8/16全部通过，AHRS3053；UTC初始化false |
| BMP390 | 60+1校准 | 压力ADC6459904..6463488、温度ADC8494848..8500224；这些不是物理单位 |
| SHT45 | 61 | 23.579..23.710℃、64.414..64.712%RH，heater0 |
| TFA1500-L | 42137 | 360..480 mm |
| AI8 | 56 flagged | PV/SV24.4..24.5℃、SP40℃、online1、HOST0x0200、无transport/exception |

采集末尾已主动禁用多路，因此摘要最后health离线也可能是正常停止的结果；报告不能将结束状态套到整段有效采集。EPS sticky ERROR=2且CRC计数未增的历史解释参见SENSOR_ENABLE_REVIEW，其UART framing路径与内部CRC错误不是同一事件。当前未做温控实板写回验收、GNSS有效定位验收、长期稳定性或精度验收。

## 主要来源定位

- `integrated_20260916/member3_uart_sensors/rtl/ptb210_rs232.v:261` payload；`:704` flags；`:725` timestamp。
- `.../rtl/bmp390_driver.v:135` timestamp；`:152` calibration；`:172` ADC payload。
- `.../rtl/sht45_driver.v:55`单位换算；`:120` heater flag；`:158` timestamp；`:167` payload。
- `.../rtl/tfa1500_uart.v:110` payload；`:298` timestamp/flags；`tfa1500_parser.v:57` HF转mm。
- `.../rtl/epsilon_rs232.v:62`内帧UTC；`:96`转发消息；`:155`帧装配及CRC；`:185`raw转发。
- `.../rtl/ai8_modbus_rs485.v:80`寄存器；`:117`配置校验；`:154`TLV；`:206`commit/结果；`:221`样本/报警。
- `.../rtl/ai8_poll_core.v:55`Modbus地址；`:112`失败/快照；`:151`写及读回确认。
- `.../rtl/sensor_record_fifo.v:59`丢弃/补充overflow标记；`.../include/project_defs.vh`源/消息/tag/type。
- `integrated_20260916/lead_system/rtl/cmd_decoder.v:225`普通写与AUTO_COMMIT分流；`action_controller.v:239`COMMIT计数确认；`:318`SENSOR_ACTION；`:420`CHECK_ACK失败status14。
- `fx3_gpif_debug_20260918/host/analyze_sensors.py`、`bmp_compensation.py`、`plot_six_sensors.py`；`reports/SENSOR_ENABLE_REVIEW.md`、`MULTI_SENSOR_BOARD_REPORT.md`、`sensor_six_60s_01/sensor_summary.json`。
- EPS手册文本 `project_audit/source_review/8-1-组合导航EPSILON使用手册V1.2_20250424.txt:2652`，11.2.2；AI8 HOST手册追溯见SENSOR_ENABLE_REVIEW末节，PDF44/46页。

验证方式：逐项手工比较RTL表达式、Python解码和小型JSON摘要，检查TLV offset/count/长度算术、校准struct布局、AI8结果位图及两层ACK流程。本次无RTL/软件改动，不运行Vivado、综合或硬件测试；未把历史仿真结果冒充本次动态验证。交付只新增文档，未更改现有解码器；上述问题作为上位机实现要求明确记录。
