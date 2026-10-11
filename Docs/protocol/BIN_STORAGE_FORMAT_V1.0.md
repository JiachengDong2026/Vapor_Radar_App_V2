> 2026-10-11 同步：本文存储格式适用于仓库 `host/qt_monitor` V0.2.5；V0.2.5 仅改变 WMS 电压输入显示及边界检查，BIN 格式未变。下述采集记录为历史证据。

# VaporMonitor .bin 数据存储格式说明

版本 1.0 · 2026-10-03 · 适用上位机 VaporMonitor V0.2.4、VLP 1.0。本文件描述“记录数据”生成的采集文件，不是 FPGA 配置 BIN，也不是 FX3 固件 BIN；后两种文件不能用于数据回放。

## 1. 文件里保存了什么

文件是 USB Bulk IN 端点 0x86 收到的字节按接收顺序直接拼接。没有单独的文件头、索引、压缩、文件尾或每次 USB 读取长度标记。每个 VLP 帧自身有长度、来源、时间戳和 CRC。

```text
[VLP帧头40B][payload N字节][CRC32 4B][对齐补零0~3B]
[VLP帧头40B][payload N字节][CRC32 4B][对齐补零0~3B] ... EOF
```

`Worker::consume()` 在解析之前将 bytes 写入 QFile，所以错误帧、半帧也可能原样进入文件。图表抽点、滚轮缩放、增益显示换算和 H2 峰值计算都不改变原始文件。文件包含录制期间实际收到的 DATA、STATUS、EVENT、RESP 等混合帧；不会自动保存未启用的数据源。

**没有自动存入文件的内容：**USB OUT 命令请求、EP0 B0/B1 诊断、主机接收时间、墙钟开始时间、软件版本、所有初始配置、接线方式、实物增益、操作者信息、图表缩放范围。周期 H2 峰值也是上位机从 DLIA 点计算出来的，不是本版本专门存储的一列。

文件中可能有 READ_REG 应答，但不能据此保证完整重建配置：录制前收到的应答不在文件里，WRITE 成功应答也不含所写的值。建议同时填写随包的 `session_metadata_template.json`，这是建议新增的旁车记录，**当前 GUI 不会自动生成**。

## 2. 建议录制步骤

1. 连接设备并核对 FPGA/FX3 版本、接线、实际增益及 WMS/DLIA 参数。
2. 在开始采集前点击“记录数据”，选择不存在的新 `.bin` 文件；软件使用 NewOnly 模式，不覆盖已有文件。
3. 启动需要的 WMS 通道，再开始采集。尽量从传感器初始化前记录，保留 BMP390 本机标定数据。
4. 结束时先“停止采集”，待停止完成，再“停止记录”，以保留收尾数据。仅停止采集不等于停止记录；关闭文件后再复制给他人。
5. 保留 `.bin`、旁车说明及软件/固件版本。设备复位或重新连接时另建新文件，不直接拼接不同会话。

采集中途开始/停止记录可能截断帧或扫描周期。首尾有残片不等于整份文件不可用；必须报告跳过的字节/周期。异常退出或磁盘写入失败也可能截断文件，当前没有崩溃恢复或落盘事务保证。

双 ADC 1 MS/s、每点 4 字节，仅样本部分约 8 MB/s；加帧头、谐波、传感器和状态后更大，按至少约 0.5 GB/min 预留空间（具体取决于启用通道和参数）。

## 3. VLP 外层帧的逐字节定义

所有多字节字段使用**小端序**。`uN` 为 N 位无符号整数，`iN` 为 N 位二进制补码有符号整数，`f32/f64` 为 IEEE 754 浮点数。表中的偏移从当前帧起点计算；禁止直接使用未指定打包方式的 C/C++ 结构体解释磁盘数据。

| 偏移 | 字节数/类型 | 字段 | 说明 |
|---:|---|---|---|
| 0 | 4 | magic | `56 4C 50 31`，ASCII `VLP1` |
| 4 | 1/u8 | major | 1 |
| 5 | 1/u8 | minor | 0 |
| 6 | 1/u8 | kind | 见下表 |
| 7 | 1/u8 | header_words | 10，即头长 40 字节 |
| 8 | 4/u32 | total_len | `44 + payload_len`，不含对齐补零 |
| 12 | 4/u32 | sequence | 帧序号；应答回显命令序号 |
| 16 | 2/u16 | source_id | 数据来源或应答的目标模块 |
| 18 | 2/u16 | msg_id | 消息类型 |
| 20 | 4/u32 | flags | 时间/周期有效性及质量标志 |
| 24 | 8/u64 | timestamp_ticks | FPGA 100 MHz 本地计数，1 tick=10 ns |
| 32 | 4/u32 | cycle_id | flags.bit1 有效时表示扫描周期 |
| 36 | 4/u32 | payload_len | N，范围 0..8192 |
| 40 | N | payload | 按 kind/source/msg/schema 解码 |
| 40+N | 4/u32 | crc32 | 头部及 payload 的 CRC，小端保存 |
| 44+N | 0..3 | padding | 零填充至 4 字节边界，不属于 CRC |

下一帧偏移 = 本帧偏移 + `((total_len + 3) & ~3)`。最大输入帧为 8236 字节。CRC 紧接真实 payload，不要先把 payload 补齐再读 CRC。

| kind | 含义 |
|---|---|
| 0x01 | 主机命令；正常 GUI 录制只记 IN，不应期待其中含有原始 OUT 命令 |
| 0x02 | 命令应答 |
| 0x10 | 测量数据 |
| 0x11 | 事件 |
| 0x12 | 状态 |
| 0x7F | 协议错误响应 |

CRC 使用 CRC-32/ISO-HDLC：反射多项式 0xEDB88320，初值及最终异或均为 0xFFFFFFFF。Python 可直接 `zlib.crc32(header + payload) & 0xffffffff`。标准校验串 `123456789` 得到 0xCBF43926，文件中的字节为 `26 39 F4 CB`。

flags 位：0=时间戳有效，1=周期有效，2=时间同步有效，3=曾发生溢出/丢弃，4=设备错误，5=部分数据，6=配置变化，7=厂家原始 payload，8=紧急事件；9..31 保留。CRC 正确不代表测量有效，DEVICE_ERROR 也不能一概解释成没有新测量，应结合该设备状态字段。

**时间处理：**相对时间 `(ticks - ticks0) / 100000000` 秒，先用 64 位整数相减再转浮点。timestamp 不是 Unix 时间，也不等于电脑时钟；EPSILON 的 UTC 是另一套字段。复位会使本地计数重新开始。不同数据源异步更新，不能把相邻两帧视作同时采样。

**序号处理：**不能要求整个文件的 sequence 严格连续。RESP 使用主机命令序号，其余帧使用下位机序号；会自然出现跳变或重复。ADC/DLIA 完整性按来源、周期和分片验证。

## 4. 数据分发与通道对应

以下行仅在 kind=0x10 时按测量 payload 解码。

| source | msg | 数据 | 实物/界面对应 |
|---|---|---|---|
| 0x0020 | 0x1000 | ADC0 RAW | 界面通道1，CON15，AD4630 CH0 |
| 0x0021 | 0x1000 | ADC1 RAW | 界面通道2，CON16，AD4630 CH1；不是 CON17 高速 ADC |
| 0x0030 | 0x1001 | DLIA0 | 对应 ADC0、WMS0；界面 WMS1/通道1，CON7 |
| 0x0031 | 0x1001 | DLIA1 | 对应 ADC1、WMS1；界面 WMS2/通道2，CON8 |
| 0x0040 | 0x1100 | PTB210 | TLV schema 1 |
| 0x0042 | 0x1200 | EPSILON | 完整 FDILink 厂家帧 |
| 0x0043 | 0x1100 | BMP390 | TLV schema 1，原码及标定数据 |
| 0x0044 | 0x1100 | SHT45 | TLV schema 1 |
| 0x0045 | 0x1100 | TFA1500-L | TLV schema 1 |
| 0x0046 | 0x1100 | AI8 | TLV schema 2，不能按旧 RD105 解码 |

内部编号从0开始，界面从1开始。WMS/DAC 上传控制状态，不会生成一份真实模拟输出测量波形；不能把 ADC 波形当作 DAC 回读。

## 5. ADC RAW payload

下表偏移从 payload 起点算（即文件帧起点+40），**RAW 与 DLIA 的 schema 2 布局不同**。

| 偏移 | 类型 | RAW schema 2 字段 |
|---:|---|---|
| 0 | u16 | schema=2 |
| 2 | u16 | adc_bits；当前两路均24 |
| 4 | u32 | rate_hz；当前常用1000000 |
| 8 | u32 | total_samples；本周期总样本数 |
| 12 | u32 | sample_format：0=i32，1=u32 |
| 16 | u16 | fragment_index，从0开始 |
| 18 | u16 | fragment_count |
| 20 | u32 | first_sample，本片首样本在周期中的索引 |
| 24 | u32 | fragment_samples，本片样本数 |
| 28 | u32 | reserved=0 |
| 32 | 每点4B | 样本，长度必须为4×fragment_samples |

当前格式0：24位 ADC 结果已经符号扩展为 i32，每样本仍占4字节，不能每3字节读取。范围 -8388608..8388607。最大每片2040点。schema 1 兼容头为20字节：0 schema:u16=1，2 adc_bits:u16，4 rate:u32，8 count:u32，12 format:u32，16 reserved:u32=0；20起为全部 count 个样本，无分片字段。

### 本板当前电压换算

适用条件：RLY5 已拆除并桥接2–3、5–6，S3两组OFF，前端增益G=0.5，VREF标称5V，沿用已确认的正/负两路接法。

```text
CON15 电压 = +code0 × 5 / (8388608 × G) V = +code0 × 10 / 8388608 V
CON16 电压 = -code1 × 5 / (8388608 × G) V = -code1 × 10 / 8388608 V
```

例：码值4194304，对应 CON15 +5V、CON16 -5V；码值8388607 对应约+9.9999988V/-9.9999988V。通道2的负号来自模拟前端接法，不表示把文件中的 i32 再按无符号数读一次。

若实物增益改成1，公式分母中的G同步改为1。GUI增益选项只改变显示换算，不控制硬件。文件不记录该选择，因此务必附接线/增益元数据。以上是标称换算，不替代实际参考电压、零点和增益校准。

完整周期内第 j 点的相对位置通常取 `j/rate_hz` 秒，绘制周期横轴则乘1000为毫秒；flags.bit5部分周期的时间位置只能估算，不应用于完整扫描峰值统计。

## 6. DLIA/H1/H2 payload

| 偏移 | 类型 | DLIA schema 2 字段 |
|---:|---|---|
| 0 | u16 | schema=2 |
| 2 | u16 | format：0/1/2 |
| 4 | u32 | output_rate_hz，解调结果实际输出率，不是20kHz调制频率 |
| 8 | u32 | total_points，本周期总点数 |
| 12 | u16 | fragment_index |
| 14 | u16 | fragment_count |
| 16 | u32 | first_point |
| 20 | u32 | fragment_points |
| 24 | u32 | bytes_per_point：8/16/24 |
| 28 | u32 | reserved=0 |
| 32 | 按点宽 | 点数据，按时间先后存储 |

| format | 每点顺序 | 字节数 |
|---|---|---:|
| 0 | i32 H1，i32 H2 | 8 |
| 1 | i32 I1，i32 Q1，i32 I2，i32 Q2 | 16 |
| 2 | i32 I1，i32 Q1，i32 I2，i32 Q2，i32 H1，i32 H2 | 24 |

当前硬件输出使用 format0；不要将 DLIA MODE 寄存器误认为 payload 格式选择。I/Q可以有正负，幅值H1/H2应非负。读取format1时GUI以 `min(2147483647, floor(hypot(I,Q)))` 生成对应幅值；format0/2直接读取H1/H2。

H1/H2单位为数字幅值 code，不能直接套用 ADC 输入电压公式，也没有自动换算成浓度。H2峰值为合格完整周期内的 `max(H2[j])`；转成 ppm 需要另行浓度标定、基线处理及相关实验参数。当前四阶 Butterworth 版本 profile=0x00040101、截止频率固定1kHz（ADC 1MS/s）；这些配置不包含在每个 DLIA payload 中，应另外存档。

常用100Hz扫描、10kHz解调输出，对应约100点/扫描。GUI要求点数与 `output_rate/scan_hz` 相差不超过1且 flags 中无0x38异常位，才生成完整周期峰值。离线处理不能永远硬编码100点，应使用本次实际参数。

## 7. 分片重组与数据有效性

按 `(会话, source_id, msg_id, cycle_id, timestamp_ticks)` 分组。每片先验证外层CRC，再核对 schema、采样率、总点数、格式、位宽、点宽、片数及flags一致；片号从0连续，首样本索引无重叠/缺口，片内数据长度精确匹配，最后样本数等于声明总数。未知schema保留原帧并跳过解码，不猜测结构。

flags.bit0和bit1必须有效。缺片、重复片、元数据冲突、部分周期、丢弃/错误状态均要单独记录，不补0、不把旧峰值复制为新点。帧齐全不代表覆盖整个扫描，启动/停止边界可能是短周期。RAW与DLIA可能交错上传，应分别重组；匹配关联时优先看各自通道/周期信息，不按磁盘相邻顺序配对。

停止 WMS 会影响对应完整扫描分帧；文件里没有该路完整曲线不一定是USB掉线。传感器未接入、未启动或通信失败也不会自动产生有效测量。

## 8. 六传感器负载

除EPSILON之外均为TLV：payload前4字节为 `schema:u16, item_count:u16`；每项为 `tag:u16, type:u8, length:u8, value[length]`，随后零填充到payload内4字节边界。按tag查找，不依赖排列顺序；未知tag按length跳过，重复tag/越界/错误类型应报错。

常见type：1=u8，2=u16，3=u32，4=u64，5=i8，6=i16，7=i32，8=i64，9=f32，10=f64，11=bytes，12=UTF-8字符串，13=bool。长度须匹配实际类型。

| 设备 | tag | 类型及换算 |
|---|---|---|
| 通用诊断 | 0x0001 / 0x0002 / 0x0004 | u32 状态 / 错误或状态组合 / 样本计数，具体状态按设备解释 |
| PTB210 | 0x0012 | i32，值/100000 = hPa |
| SHT45 | 0x0010 | i32，值/1000 = ℃ |
| SHT45 | 0x0011 | u32，值/1000 = %RH |
| TFA1500-L | 0x0013 | u32，毫米；米=值/1000 |
| BMP390 | 0x0100 | type11、21字节，器件0x31..0x45标定寄存器原字节 |
| BMP390 | 0x0101 / 0x0102 | u32容器中的24位无符号压力/温度ADC原码 |
| AI8 | 0x0460 / 0x0461 / 0x0462 | i32 PV/SP/SV原码；本机确认÷10=℃ |
| AI8 | 0x0463..0x0467 | u32 OP、ALARM、CONTROL、HOST、设定结果原码 |

BMP390必须使用同一器件/会话的21字节标定值，并用同条压力/温度原码执行Bosch补偿，才能得到Pa和℃。Pa/100=hPa。仓库 `host/bmp_compensation.py` 可直接使用；缺少标定时只能显示原码，不能套默认系数或借另一块板的标定。

AI8 schema2的status(tag1)：bit0在线，bits4:1通信错误码，bits12:5 Modbus异常码。只有在线、通信错误=0且异常码=0，才把本次PV/SP/SV作为新测量。失败轮询可能带上次缓存值，不能形成新的温度点。HOST bit8系统故障、bit9全局报警，与通信有效性分别处理；带报警但成功的测量仍有参考价值。0x0467为设定结果位域，不能当温度；读取温度回读看SP。

### EPSILON：两层协议

VLP payload是完整厂家帧：`FC, packet_id, data_length, serial, crc8, crc16_hi, crc16_lo, data[data_length], FD`，总长为data_length+8。内层CRC16两字节高字节在前，是本文件多字节小端规则的一个厂家包例外；data中的数值依手册采用小端。

crc8覆盖前4字节，初值0，反射多项式0x8C；crc16覆盖data，初值0，多项式0x1021。VLP CRC通过后仍应验证内层CRC与已知packet长度。

常用packet：0x40 IMU（56B data），0x41 AHRS（48B），0x42 INS（72B），0x50系统状态/融合解（102B），0x51 Unix时间（8B），0x53状态（4B），0x59原始GNSS（74B）。不要把0x42中的局部位置当经纬度。

以下偏移从内层data起点计算：

| packet | 偏移及类型 | 含义 |
|---|---|---|
| 0x41 | 12/16/20 f32 | 横滚/俯仰/航向，弧度；度=值×180/π |
| 0x42 | 24/28/32 f32 | 局部北/东/下位置，米，非经纬度 |
| 0x50 | 0 u16、2 u16、4 u16 | 系统状态、滤波状态、更新状态 |
| 0x50 | 6 u32、10 u32 | Unix秒、微秒 |
| 0x50 | 14 f64、22 f64、30 f64 | 纬度/经度（弧度）/高度（米，基准需按设备配置确认） |
| 0x51 | 0 u32、4 u32 | Unix秒、微秒 |
| 0x53 | 0 u16、2 u16 | 系统状态、滤波状态 |
| 0x59 | 8 f64、16 f64、24 f64 | 原始GNSS纬度/经度/高度 |
| 0x59 | 72 u16 | GNSS状态，低4位fix，bit5时间有效 |

系统滤波状态bit3表示UTC初始化，bits7:4为GNSS fix；要结合状态和数据新鲜度判断。没天线/没定位时，零经纬度或旧位置不能当有效位置。完整字段解码可参考`host/qt_monitor/src/protocol.cpp::epsilon()` 与对应型号手册。

## 9. 状态、应答及扩展处理

DATA之外的帧不能当测量数组。常见READ_REG应答(kind=2,msg=2)：payload偏移0 status:u32；成功时4 address:u32、8 count:u16、10 reserved:u16、12起count个u32寄存器值。失败时可能仅有4字节status。WRITE_REG成功应答(msg=3)只有status=0，不保存写入值。

STATUS/EVENT/未知消息应保留来源、时间、flags和原payload；可先跳过业务解码，不能丢弃其长度后误读下一帧。状态消息的详细字段仍以对应固件接口文档为准。

## 10. 给开发人员的读取示例

随包 `examples/vlp_reference.py` 是标准库增量解析器，支持跨块半帧、CRC、补零及EOF恢复。`examples/read_bin.py` 统计所有帧，并打印第一条RAW/DLIA的格式和样本预览；它是离线格式入口，不负责完整传感器工程量导出或完整扫描重组。

```powershell
python -B Docs/protocol/examples/read_bin.py 'E:/Documents/Vapor_Lc_App_Test/你的采集目录/bulk_in.bin'
python -B Docs/protocol/examples/read_bin.py Docs/protocol/examples/capture_example.bin
python -B Docs/protocol/examples/test_vlp_reference.py
```

示例中的采样点可以按以下方式读取（必须先通过CRC、长度和schema校验）：

```python
# RAW schema2，格式0：每点4字节，已符号扩展
code = struct.unpack_from('<i', payload, 32 + 4*j)[0]
voltage = (1 if source_id == 0x20 else -1) * code * 5 / (2**23 * gain)
# DLIA schema2，格式0：同一点H1和H2交错排列
h1, h2 = struct.unpack_from('<ii', payload, 32 + 8*j)
```

`capture_example.bin`为历史六传感器不连续摘录（656字节、9帧），包括BMP390标定和应答，不适合计算丢包率。原 2026-10-03 交付包另有 `adc_dlia_excerpt.bin` 和 `sample_provenance.json`，本次未复制这两个文件入库；需要时从原交付包获取，不能把该历史 ADC 摘录当作六传感器并发证据。

推荐解析器验收：任意分块得到相同帧；损坏CRC、非法长度、非零补齐、截断尾帧均可定位；payload内出现VLP1不误拆；未知schema保留；大文件流式处理；缺片不补0；跨会话计数回退不连接为连续趋势。

## 11. 实现依据与版本界限

以本次随包源码快照为依据：`worker.cpp`负责写入/回放，`protocol.cpp`负责CRC/分片/工程量，`VaporUsbBridge.cs`将Bulk IN原始字节送给GUI。源工程为 qt_vapor_monitor_fixed_axes_20261002；运行EXE版本0.2.4。正式仓库历史协议文档用于交叉核对，不将其旧硬件验收范围、旧比特流哈希或默认参数当作本次实机配置。

软件和样本的SHA256见运行包 `manifest_sha256.json`。本说明未改变文件格式、软件逻辑或板上输出。

### 当前GUI回放的限制

- 回放按固定间隔读取文件块，不按采集时的时间戳等速播放；曲线刷新速度不能用于估计原采样间隔。
- 当前回放不会从文件中的READ_REG应答自动恢复scanHz，沿用程序当前/历史值（新进程默认100Hz）及显示增益。因此其他扫描频率的文件可能无法正确判断完整扫描/H2峰值，须在独立分析程序中使用旁车参数。
- 当前GUI在EOF时不会调用解析器的残帧恢复函数。界面显示“回放完成”不等于文件无截断，须检查bufferedBytes或用附带离线解析器执行finish()检查尾部。
- 图表保留的是有限长度、抽点后的显示数据；完整历史与全部字段应从.bin读取。回放也不保证重现录制时所有界面状态。
