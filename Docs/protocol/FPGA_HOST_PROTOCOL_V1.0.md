> 2026-10-04：已将2026-10-02上板验证的DLIA精度版本同步至正式V2，当前ID/profile为0101/00040101。历史构建记录保留；本次范围及验证见[同步记录](../MERGE_MANIFEST_20261004.md)。

> 2026-09-28 硬件映射修订（VLP1 帧版本不变）：ADC1 改为 CON16 / AD4630 CH1，24位，共同1MS/s；见[修订说明](../INTEGRATION_REVISION_20260928_DUAL_AD4630.md)。

> 2026-09-23正式归档：线协议和payload语义维持1.0。正文BIT哈希标识2026-09-18实测旧产物；本轮新BIT身份由新的构建清单记录，尚未上板。当前GP01固件源码位于[firmware/fx3](../../firmware/fx3)，协议正文的e705…镜像哈希仍是固件基线。详见[正式集成修订](../INTEGRATION_REVISION_20260923.md)。本仓库维护Markdown及离线示例，不包含旧Word排版产物。

# FPGA 下位机—上位机通信协议说明

交付版 1.0 · 2026-09-19 · 面向上位机开发与联调


**内容索引**

- [1. 适用版本与阅读顺序](#section-1)
- [2. 上位机软件组织建议](#section-2)
- [3. 模块寻址总表](#section-3)
- [4. 传输基线与 USB 接入](#section-4)
- [5. VLP1 外层帧：精确字节布局](#section-5)
- [6. 命令、应答与事务匹配](#section-6)
- [7. 分片和 schema 兼容约束](#section-7)
- [8. FX3 EP0 只读诊断 B0 / B1](#section-8)
- [9. 可复核请求及已有实测证据](#section-9)
- [10. 六传感器 payload 与温控确认协议](#section-10)
- [11. 状态、事件与时间语义](#section-11)
- [12. 六路传感器联调流程](#section-12)
- [13. 后续 ADC / DILA / WMS 接口](#section-13)
- [14. 交付文件与依据](#section-14)
- [15. 离线参考示例使用](#section-15)

<a id="section-1"></a>

## 1. 适用版本与阅读顺序

本文描述当前已实现并完成六路传感器 USB 收发测试的接口。文档版本 1.0 与线上的 VLP 1.0、各 payload 的 schema_version 是三个独立版本。

| 项目 | 本次基线 |
|---|---|
| FPGA | integrated_20260916/lead_system，系统时钟 100 MHz，GPIF 时钟 50 MHz |
| FPGA BIT SHA256 | 99ef3e1a7605c793d0d22c871f53ac751db18127e6a79aad7919c644d617f46f |
| 当前 FX3 应用 | fx3_gpif_debug_20260918/output/vapor_fx3.img，GP01 修正版 |
| FX3 IMG SHA256 | e705c3032aece44c2ef1890e45c9f6b5d5aa31fc6facc8ab02ddb2847e043dd5 |
| 接口 | CON23 USB；应用设备 04B4:00F1；Bulk OUT 0x02，Bulk IN 0x86 |
| 线协议 | VLP1；40 字节固定头；小端；CRC32；4 字节传输对齐 |
| 已实测传感器 | PTB210、EPSILON、BMP390、SHT45、TFA1500-L、AI8 |
| 本轮未纳入实测 | HMP、ADC/DILA、WMS/DAC、电机；不能由能力位或接口存在推断已验收 |

上位机首先实现 USB 持续收包、VLP 拆包及 CRC、请求应答匹配，然后实现六路传感器解析、配置与状态管理。后续 ADC/DILA 接口见扩展章节。附带 examples 可在没有板卡时运行，不依赖 USB 库；当前正式仓库维护本 Markdown 正文。

**当前实现差异优先按本文处理：**0x0046 是 AI8，不是旧 RD105；惯导使用 CON14 主航插 RS232；BMP390 上传 ADC 原码与标定系数，需要主机补偿；AI8 数据使用 schema 2；AI8 STATUS 位不能套用通用 online=bit4；FX3 必须核对 GP01，而不仅看 VID/PID。历史独立工程的 ASCII `SET 40.0`、`NAV ...`、`AI8 ...` 不是完整系统 USB 协议。

<a id="section-2"></a>

## 2. 上位机软件组织建议

建议分为 USB 传输、VLP 流解析、命令队列、设备解码、存储与界面五部分。唯一的 USB IN 接收者持续读取，将 RESP/PROTOCOL_ERROR 交给命令队列，将 DATA/STATUS/EVENT 交给解码器。界面不直接读端点，Control Center 与正式程序也不能同时消费端点数据。

- 命令串行发送；同一时刻最多一个等待完成的命令。持续接收数据不能因等待应答而停止。
- 启动时分配新的本机会话 ID，命令 sequence 单调递增；复位/掉线后清理未完成请求及旧缓存，重新握手。
- `u64 timestamp` 在 C++ 使用 uint64_t，在 JavaScript 使用 BigInt 或先做整数差再转换；不要直接用 double 保存全精度计数。
- 存储原始收包文件、实际接收长度、主机接收时间、解析错误、命令请求及最终结果。工程量与原始值、单位、质量标志一并保存。
- 图形界面可以按窗口降采样刷新；完整原始数据落盘与界面刷新分离。六路实测约 7.28 MB/60 s；不能拿此吞吐证明未来 ADC 满速可用。
- 质量状态至少区分：未启用、等待首样本、在线新鲜、数据过期、设备报警、通信错误。CRC 正确仅表示传输完整，不能替代测量有效性或 GNSS 定位判定。

<a id="section-3"></a>

## 3. 模块寻址总表

寄存器地址为字节地址，32 位宽，当前仅低 16 位有效，按 4 字节对齐。表中 source 是 VLP 目标/来源，设备的 Modbus/I2C 地址不等于 source。SYSTEM=0x0001 可访问各合法寄存器；普通源只能访问自己拥有的页。

| 模块 | source_id | 寄存器基址 | mask bit | 主要上传消息 |
|---|---|---|---:|---|
| SYSTEM | 0x0001 | 0x0000；时钟 0x0100 也由 SYSTEM 访问 | — | 0x1400/0x1401/0x1402 |
| TIME | 0x0002 | 0x1000 | 2，有别名 | 0x1201 |
| WMS0 / DAC0 | 0x0010 | 0x2000 / 0x3000 | 16 | 状态/事件；DAC 无独立采样流 |
| WMS1 / DAC1 | 0x0011 | 0x2100 / 0x3100 | 17 | 同上 |
| ADC0 / ADC1 | 0x0020 / 0x0021 | 0x4000 / 0x4100 | 32 / 33 | 0x1000 |
| DILA0 / DILA1 | 0x0030 / 0x0031 | 0x5000 / 0x5100 | 48 / 49 | 0x1001 |
| PTB210 | 0x0040 | 0x6000 | 0 | 0x1100 |
| HMP，暂不接入 | 0x0041 | 0x6100 | 1 | 0x1100 |
| EPSILON | 0x0042 | 0x6200 | 2 | 0x1200 |
| BMP390 | 0x0043 | 0x6300 | 3 | 0x1100，含标定元数据 |
| SHT45 | 0x0044 | 0x6400 | 4 | 0x1100 |
| TFA1500-L | 0x0045 | 0x6500 | 5 | 0x1100 |
| AI8 温控 | 0x0046 | 0x6600 | 6 | 0x1100 schema 2 |
| 电机 | 0x0047 | 0x6700 | 7，仅相关动作 | 0x1300 |
| STREAM / USB | 0x0050 | 0x7000 / 0x8000 | 不用于普通采集启动 | 状态/事件 |

mask 的冻结映射是 `source_id & 0x3F`，存在别名，不能把所有 source 通用地 OR 成无歧义列表。SYSTEM/0xFFFF 广播的 bit2 表示 EPSILON，不是 TIME；TIME reset/clear 必须显式 source=0x0002。六个已接传感器 mask=0x000000000000007D（不含 HMP bit1）；禁止将此掩码解释成寄存器页编号。

数字约定：地址通常带0x；source_id、msg_id、frame_type、tag及报文十六进制示例均按十六进制，相关表格可省略0x。字节长度、样本数、status枚举、位号及温度换算值按十进制理解；例如DATA类型0x10是十进制16，SENSOR_ACTION的action=17是十进制17（0x11）。


<a id="section-4"></a>

## 4. 传输基线与 USB 接入

本章核对对象为 2026-09-19 已存在的实测固件 `E:/Documents/Vapor_Lc_App_Test/fx3_gpif_debug_20260918`（下称 FX3）和封存 FPGA `E:/Documents/Vapor_Lc_App_Test/integrated_20260916/lead_system`（下称 FPGA）。源 v2 规范提供字段名称，实际边界取自 RTL；本章不表示重新烧录或运行了实板测试。

| 项目 | 当前实现 |
|---|---|
| 应用设备 VID:PID | `04B4:00F1`，不能把 FX3 bootloader 枚举当作运行设备 |
| 配置/接口/alternate | `1 / 0 / 0`；接口类 `0xFF`；设备没有 USB 序列号字符串 |
| 命令 OUT | Bulk EP `0x02`，主机→FX3→FPGA |
| 数据/应答 IN | Bulk EP `0x86`，FPGA→FX3→主机，所有帧类型混合在同一字节流 |
| USB 最大包 | SS 1024 B，HS 512 B，FS 64 B；SS burst 16 packets，不使用 USB streams |
| DMA | 每方向 4 个 16384 B buffer，自动 DMA；这是传输缓存参数，不是 VLP 帧长 |
| 已测 Windows 接口 | Cypress 驱动、CyUSB.dll；`SensorRun.cs`/`CaptureIn.cs` 使用 CyBulkEndPoint |

依据：FX3 `src/cyfxslfifousbdscr.c:38`、`:57`、`:115`；`include/cyfxslfifosync.h:38`、`:55`、`:78`；`src/cyfxslfifosync.c:127`、`:173`；`host/SensorRun.cs:107`。多设备场景需由上位机明确选设备/物理端口，当前实测工具只接受唯一匹配设备。

持续运行一个 IN 接收循环；命令等待应答时也必须读 IN，否则数据流、应答和 STOP 排空都可能背压。一次 USB 读取可含半帧、多帧或跨帧数据；USB packet、short packet、DMA buffer、读取返回边界均不能替代 VLP 帧边界。当前已测工具以 16384 B 为读取 buffer；读取超时可以只是暂时无数据，不能记成 CRC 错误。传输 API 报错且返回非零长度时，必须按所选 USB 库确认其字节有效性；当前 `SensorRun.cs:44` 把这种情况作为不确定部分传输终止处理。

<a id="section-5"></a>

## 5. VLP1 外层帧：精确字节布局

所有多字节整数均为 little endian。基本帧为 `40 B header + N B payload + 4 B CRC32`。`total_len=44+N`。IN 线上帧后再补 0 到 4 字节边界：`wire_len=(total_len+3)&~3`，填充长度 0..3；填充不计入 `payload_len`、`total_len` 或 CRC。CRC 紧贴真实 payload，其起点不要求 4 字节对齐。

| 字节偏移 | 类型/长度 | 字段 | 当前语义 |
|---:|---|---|---|
| 0 | 4 B | magic | 固定 `56 4C 50 31`，ASCII `VLP1` |
| 4 | u8 | ver_major | 1 |
| 5 | u8 | ver_minor | 0 |
| 6 | u8 | frame_type | CMD=0x01，RESP=0x02，DATA=0x10，EVENT=0x11，STATUS=0x12，PROTOCOL_ERROR=0x7F |
| 7 | u8 | header_words | 10，固定头长 40 B |
| 8 | u32 | total_len | 44+payload_len，不含帧后填充 |
| 12 | u32 | sequence | CMD 由主机分配；RESP/7F 原样回显 |
| 16 | u16 | source_id | CMD 为目标，数据为来源；应答回显目标 |
| 18 | u16 | msg_id | CMD 命令号或数据消息号；应答回显命令号 |
| 20 | u32 | flags | 有效性/错误状态位，见下表 |
| 24 | u64 | timestamp | 本地 100 MHz tick；1 tick=10 ns，不能直接当 UTC |
| 32 | u32 | cycle_id | 仅 flags.bit1=1 时有效 |
| 36 | u32 | payload_len | N，实际负载字节数 |
| 40 | N B | payload | 按命令/消息 schema 解码 |
| 40+N | u32 | CRC32 | 对偏移 `[0,40+N)` 的所有字节计算 |
| 44+N | 0..3 B | padding | IN 零填充到 4 B；不属于基本帧 |

字段构造直接依据 FPGA `rtl/data_packetizer.v:72`；零填充与 CRC 位置见 `:85`；实测解析格式为 FX3 `host/analyze_capture.py:17` 的 `<4sBBBBIIHHIQII`。请求接收器只校验 4..7 字节整体等于 `01 00 01 0A`（FPGA `rtl/vlp_cmd_rx.v:96`），请求 flags/timestamp/cycle_id 不用于执行。主机生成请求时把这三个字段置 0。对于任意非 4 B 对齐的 PING，请在整帧 CRC 后补 0 发送，适配 32 位 GPIF；FPGA 字节扫描器会丢弃帧间零字节，不能把 padding 放在 payload 与 CRC 之间。

| flags bit | 名称/解释 |
|---:|---|
| 0 | TIMESTAMP_VALID |
| 1 | CYCLE_ID_VALID |
| 2 | TIME_SYNC_VALID |
| 3 | OVERFLOW_SINCE_LAST |
| 4 | DEVICE_ERROR |
| 5 | PARTIAL_DATA |
| 6 | CONFIG_CHANGED |
| 7 | RAW_VENDOR_PAYLOAD |
| 8 | URGENT_EVENT |
| 31:9 | 保留；记录原值，不自行赋义 |

命名来自源 v2 `Docs/FPGA下位机Verilog开发指南_V1.1.md:534`。RESP/7F 固定 flags=1、cycle_id=FFFFFFFF，timestamp 为 decoder 接到候选命令时的本地 tick（FPGA `rtl/cmd_decoder.v:102`、`:152`）。cycle_id 虽非零但没有有效位，不得当作实际周期。

### CRC 算法及长度上限

CRC-32/ISO-HDLC：宽度 32，反射多项式 `0xEDB88320`（正常表示 `0x04C11DB7`），init=`FFFFFFFF`，RefIn/RefOut=true，xorout=`FFFFFFFF`。可直接使用 `zlib.crc32(header+payload)`，结果按 u32 LE 写入。标准向量 ASCII `123456789` 的 CRC 为 `CBF43926`，线上四字节为 `26 39 F4 CB`。不要对每个 USB transfer 单独做 CRC。RTL 算法见 `rtl/vlp_cmd_rx.v:41`、`:101`、`:108` 及 `rtl/data_packetizer.v:44`。

| 限制 | 数值 |
|---|---:|
| 最大 CMD 基本帧 | 4096 B |
| 最大 CMD payload | 4052 B |
| 最大 IN payload | 8192 B |
| 最大 IN 基本帧/对齐后线上帧 | 8236 B |
| 最大 READ_REG count | 1021 个 u32 |
| 最大 WRITE_REG count | 1011 个 u32（8 B 参数+4×count ≤4052） |
| PING 最大请求 payload | 4052 B；成功应答 payload=4056 B |

限制来自 `rtl/vlp_cmd_rx.v:5`、`:93`、`rtl/data_packetizer.v:4`、`rtl/cmd_decoder.v:174`、`:179`。WRITE 的上限是按接收 ring 推导，仍须同时满足有效寄存器范围与权限。READ 的应答最大 payload 为 `12+4×1021=4096 B`，不是 4096 B 的完整应答帧。

### 字节流解析和恢复

建议生产解析器按以下顺序实现，且使用独立于 USB 调用生命周期的累积 buffer：

1. 搜索 magic；无匹配时保留末尾最多 3 B，以便接续跨读取 magic。
2. 收齐 40 B 头后先验证版本/头长、`44≤total_len≤8236`、`payload_len≤8192`、`total_len=44+payload_len`；做溢出安全的整数运算，错误长度不能导致无限分配/等待。
3. 收齐 `wire_len` 后校验 CRC 和帧后零填充。CRC 失败、头非法时从候选起点加 1 B 继续找 magic，不能直接相信坏头的长度跳过。
4. 验证通过后消费整个 `wire_len`，按 frame_type/source_id/msg_id 分发。未知消息或 schema 记录并跳过整帧，不能把 payload 内偶然出现的 `VLP1` 当新头。
5. 保存半帧直到下次读取。断连、复位和主动重连建立新的会话；清空旧累积 buffer 和旧 pending 命令关系。

FPGA OUT 接收同样保留坏候选内容并在长度/版本/CRC 失败后只前进 1 B，因此坏帧内部的有效命令仍可恢复；正确帧执行完成后消费完整 total_len。见 `rtl/vlp_cmd_rx.v:2`、`:45`、`:48`、`:92`。接收中等待下一个字节默认超时 10000000 sys_clk（100 MHz 下约 100 ms）；等待命令应答背压不计这个超时。拆开发送命令时应避免长间隔，优先一次发送完整已构造帧。USB API 的超时与此 FPGA 收帧超时不同。

实测 `SensorRun.cs:41` 已正确累积半帧并按对齐长度消费，但其宽松上限 1 MiB 不是硬件能力，而且它遇到坏头/CRC 会终止；`analyze_capture.py:11` 是严格离线完整流验证器，不是带重同步的生产增量解析器。移植时应补齐上述上限、恢复与未知 schema 策略。

<a id="section-6"></a>

## 6. 命令、应答与事务匹配

每个应答 payload 的偏移 0 都是 u32 `status`。**仅 CRC 正确、type=02、status=0 才表示命令成功**。解析层失败（帧长、VLP 版本/type、CRC、收帧超时）返回 type=7F；合法帧中的未知命令、非法参数、寄存器错误或 action 失败仍返回 type=02，status 非零。解析出错前请求头可能未完整，因此 7F 回显的序号/来源/命令也可能是不完整候选值；没有匹配 pending 的 7F 应记录为链路错误。依据 `rtl/cmd_decoder.v:152`、`:165` 与 `rtl/vlp_cmd_rx.v:114`。

应答原样回显 `(sequence, source_id, msg_id)`；主机应同时匹配三者和帧类型，不要把“下一帧”当应答。每个连接会话分配不与未完成请求冲突的 u32 sequence。FPGA 没有按 sequence 去重/缓存应答；重复 sequence 的命令会再次执行。建议单写者、一次一个待完成命令，IN 始终并行读取。批量 WRITE、MASKED_WRITE 和 action 不具有回滚保证；超时或发送结果不确定后先读状态/active/ACK 计数，再决定下一步，不自动重发有副作用命令。

**IN 不能直接按全流 sequence 连续性判断丢帧。** packetizer 自增序号用于 DATA/EVENT/STATUS；RESP/7F 使用请求序号覆盖。每发送一个帧，包含应答，内部自增计数仍加 1。因此应答可以产生序号跳跃、回退或与数据序号重复；只按消息/周期/片号以及硬件 drop/error 计数判定相应完整性。依据 `rtl/cmd_decoder.v:102`、`rtl/data_packetizer.v:130`、`:140`。

下表偏移均相对于 payload 起点；u16/u32/u64 全部 LE。除 GET、READ、PING 外，成功响应只有 4 B status；所有失败响应只有 status。

| msg_id（十六进制）/ 命令 | 请求 payload | 成功响应 payload |
|---|---|---|
| 0001 GET_CAPABILITIES | 空 | 7 个 u32：status、capabilities、protocol_version、time_clk_hz、max_bulk_payload、max_cmd_frame、extensions |
| 0002 READ_REG | +0 u32 addr；+4 u16 count；+6 u16 reserved=0（8 B） | +0 status；+4 addr；+8 u16 count；+10 u16 reserved=0；+12 u32 data[count] |
| 0003 WRITE_REG | +0 u32 addr；+4 u16 count；+6 u16 flags；+8 u32 data[count] | status |
| 0004 WRITE_REG_MASKED | +0 u32 addr；+4 u32 mask；+8 u32 value（12 B） | status |
| 0005 COMMIT_CONFIG | +0 u64 module_mask（8 B） | status，action 完成结果 |
| 0006 START_ACQ | +0 u64 source_mask；+8 u32 options=0；+12 u32 reserved=0（16 B） | status |
| 0007 STOP_ACQ | 同 START（16 B） | status，包含硬件排空等待 |
| 0008 RESET_MODULE | +0 u64 module_mask（8 B） | status |
| 0009 CLEAR_ERROR | +0 u64 module_mask（8 B） | status |
| 000A SET_STREAM_MASK | +0 u64 enable_mask；+8 u64 raw_enable_mask（16 B） | status |
| 000B SENSOR_ACTION | +0 u32 action；+4 u32 value（8 B） | status |
| 000C MOTOR_ACTION | +0 u32 action；+4 u32 value（8 B） | status |
| 000D TIME_ACTION | +0 u32 action；+4 u32 value（8 B） | status |
| 00FE PING | 任意 0..4052 B | +0 status；+4 原请求 payload，逐字节回显 |

GET 当前常量依次为 `0, 0x0000FFFF, 0x00000100, 100000000, 8192, 4096, 1`。capabilities=FFFF 是已实现能力常量，不能作为设备实物在线或已完成实测的证据；extensions.bit0 表示 RAW schema 2。依据 `rtl/cmd_decoder.v:122`、FPGA `docs/PROTOCOL_EXTENSIONS.md:48`。READ 成功固定前导确为 **12 B**，完整应答帧长 `56+4×count`。

READ/WRITE 地址按字节计，必须 4 B 对齐，addr 高 16 位为 0，count 非零，末字节不超过 FFFF。READ reserved 必须 0。WRITE 的 u16 flags 仅 bit0=AUTO_COMMIT 有效，亦即合并的第二个 u32 bit16；其他 flags 位必须 0。MASKED_WRITE 执行 `(old & ~mask) | (value & mask)`。对只读/特殊写语义寄存器不能假设通用 RMW 总是合适。

decoder 在第一次寄存器访问前逐页检查完整范围的 source ownership，SYSTEM=0001/FFFF 可访问全部页，但未实现地址仍返回错误。AUTO_COMMIT 只允许同一 256 B 页内且该页支持提交；全部写成功后才提交，前序写成功后发生错误不会回滚。详细归属与寄存器语义参见寄存器章节；执行证据为 `rtl/cmd_decoder.v:51`、`:63`、`:165`、`:204`、`:224`。

### Action 兼容边界

module/source mask 位采用 `source_id & 0x3F`。广播/SYSTEM 的采集集合：WMS0/1 bit16/17，ADC0/1 bit32/33，DILA0/1 bit48/49，传感器0040..0046 bit0..6；电机0047 bit7仅用于 RESET/CLEAR。FFFF 全 1 mask 会扩展为当前命令支持集合。TIME0002 与 EPSILON0042 都映射 bit2，因此 TIME RESET/CLEAR 必须明确 source0002；广播 bit2 表示 EPSILON。STREAM0050 与 WMS0010 的 bit16 别名不能互换。明确模块 source 时 mask 只能包含该模块位。见 `rtl/action_controller.v:91` 和 `docs/ACTION_CONTROLLER.md:7`。

START/STOP 选择 WMS/ADC/DILA 任一位会控制对应完整采集通道；START 预检并按顺序启用，不隐式提交参数；STOP 等待管线排空。SET_STREAM_MASK 的 raw_enable_mask 只允许 ADC bits32/33。正常 action 总超时默认 200000000 tick=2 s；top 给 decoder 300000000 tick=3 s 上限，最终主机等待还应覆盖 USB 排队/背压。实际实测工具等待命令应答上限为 10 s。不能从应答超时推断操作一定未生效。

SENSOR_ACTION：1=enable(value0/1)，2=commit(value0)，3=clear FIFO(value0)，4=soft reset/disable(value0)，5=clear error(value为W1C mask)；16 仅 HMP0041，value 为压力 F32 位模式；17 仅 AI8 **0046**，value 为 signed 微摄氏度；32/33 仅 TFA0045，分别为模式0..2和命令1..4。当前0046是AI8，不能继续按旧RD105理解。MOTOR_ACTION：1=有符号相对目标并启动（成功表示接受，不表示运动完成），2=stop并等待idle(value0)，3=idle时位置清零(value0)，4=enable(value0/1)。TIME_ACTION：1=enable0/1，2=rearm(value0)，3=边沿0上升/1下降，4=timeout_ms范围1..3600000，5=W1C error mask。见 `rtl/action_controller.v:114` 和 `docs/ACTION_CONTROLLER.md:39`；HMP/电机实物验证状态应单独说明。

### status 错误枚举

| 值 | 名称 | 使用注意 |
|---:|---|---|
| 0 | OK | 成功 |
| 1 | ERR_UNKNOWN_CMD | 未识别 msg_id |
| 2 | ERR_BAD_LENGTH | 帧长/负载长度/部分保留字段非法 |
| 3 | ERR_BAD_CRC | 外层 CRC 错误，不执行请求 |
| 4 | ERR_BAD_SOURCE | 来源未知或不拥有目标页/动作 |
| 5 | ERR_BAD_ADDRESS | 未映射/非法寄存器地址；decoder 部分对齐预检返回7 |
| 6 | ERR_READ_ONLY | 写只读寄存器 |
| 7 | ERR_RANGE | 数值/范围/保留位/参数组合非法 |
| 8 | ERR_BUSY | 当前忙，拒绝本次访问 |
| 9 | ERR_TIMEOUT | 收帧、cfg 或 action 超时；需结合帧类型与请求上下文 |
| 10 | ERR_DEVICE_OFFLINE | 保留给明确以 offline 拒绝事务的 slave；不是自动在线检测 |
| 11 | ERR_NOT_READY | 预检未就绪等 |
| 12 | ERR_PROTOCOL | 当前帧版本、type 或 header_words 不受支持等 |
| 13 | ERR_UNSUPPORTED | 已识别但不支持的操作/option/auto-commit页 |
| 14 | ERR_COMMIT_REJECTED | HMP/AI8 缺少要求的新确认等 |
| 15 | ERR_INTERNAL | 例如 cfg error=1 但原因=0 |

**status 是枚举，模块 ERROR 寄存器是位掩码，FX3 B0 的 last_error 又是第三种错误域。三者不能共享一张数值解释表。** 后台传感器超时不自动导致 READ_REG 返回 status9；仍应检查该模块状态/错误寄存器。错误枚举依据源 v2 指南`:634`，真实传递见 FPGA `rtl/cmd_decoder.v:217`、`:235`、`:256` 和 `docs/CFG_ERROR_CODES.md:3`。

<a id="section-7"></a>

## 7. 分片和 schema 兼容约束

外层 VLP1 没有通用 fragment 字段，packetizer 不会自动把任意超长 payload 拆片；上游模块必须在 8192 B 内构造完整 payload，非法/超长 fragment 被整体丢弃并累计 format_error_count。一个 USB 包也不是一个应用分片。

RAW `msg_id=1000`：不超过2043点的周期为 schema1（20 B payload头）；更长周期为 schema2（32 B头），每片最多2040点。schema2字段为 +0 u16 schema=2、+2 u16 adc_bits、+4 u32 sample_rate_hz、+8 u32 total_sample_count、+12 u32 sample_format、+16 u16 fragment_index、+18 u16 fragment_count、+20 u32 first_sample_index、+24 u32 fragment_sample_count、+28 u32 reserved=0、+32 samples。index从0开始。格式0=signed32，1=unsigned32，符号解释不能由通道显示单位猜测。依据 `rtl/adc_cycle_framer.v:4`、`:87` 与 `docs/PROTOCOL_EXTENSIONS.md:5`。

RAW 重组按 `(source_id,msg_id,cycle_id,timestamp,schema)` 聚合，检查 fragment_count/总点数/采样格式一致，片索引及 first_sample_index 完整、无重复/重叠；各片先独立验外层 CRC。不要只按 sequence 连续来重组，也不要跨断连会话合并。周期 bank 溢出可只保留前缀并置 PARTIAL_DATA/OVERFLOW；即使全部已发片到齐，也必须检查 flags 和 drop 计数后再认定周期完整。schema2 的 total_sample_count 是实际存储点数，不保证等于理论完整周期点数。

DILA 有自己的 payload 分片结构；具体字段按数据章节，不套用 RAW schema2 的偏移。未知 schema 必须保留原始字节或跳过该帧并提示版本不支持，不能继续按旧结构误解后续数值。

<a id="section-8"></a>

## 8. FX3 EP0 只读诊断 B0 / B1

这两个请求直接访问 FX3 固件，不经过 FPGA VLP，不添加 VLP头/CRC。Setup：`bmRequestType=C0`（device/vendor/IN），`bRequest=B0或B1`，`wValue=0`，`wIndex=0`，`wLength=32`。固件返回最多32 B，按8个u32 LE解析；短读应视为字段不完整。B0/B1读取不清错、不重启GPIF。依据 FX3 `src/cyfxslfifosync.c:309`、`:325`。

| B0偏移 | 字段 | 当前解释 |
|---:|---|---|
| 0 | mapping_version | `00010001`，映射协议版本 |
| 4 | application_active | 1=配置完成并启动应用；不是传感器在线位 |
| 8 | pib_error_count | PIB错误回调累计次数 |
| 12 | dma_error_count | 两方向DMA错误回调累计次数 |
| 16 | last_error | PIB错误为`80000000 OR callback_argument`；致命API错误路径保存API返回码；不是VLP status |
| 20 | dma_rx_count | USB→PIB生产buffer事件数，不是命令数/字节数 |
| 24 | dma_tx_count | PIB→USB生产buffer事件数，不是VLP帧数/字节数 |
| 28 | dma_config | 高16位DMA_BYTES=16384，低16位watermark=12；当前`4000000C` |

依据 `src/cyfxslfifosync.c:61`、`:89`、`:102`、`:312`。计数是固件全局累计，不能假定一次 B0 读取清零或每次USB重配置清零；比较同一会话前后增量，并考虑u32回绕。

| B1偏移 | 字段 | 当前解释 |
|---:|---|---|
| 0 | diagnostic_magic | `31305047`，线上 ASCII `GP01`，用于识别此诊断构建 |
| 4 | GPIF_BUS_CONFIG | 实时硬件寄存器快照 |
| 8 | GPIF_WAVEFORM_CTRL_STAT | 实时硬件寄存器快照，会随状态机变化 |
| 12 | GPIF_STATUS | 实时硬件寄存器快照 |
| 16 | gpif_phase | 0初始化前；1加载前；2加载后；3启动前；4启动后；5停止阶段 |
| 20 | last_pib_error_phase | 最近PIB错误回调发生时的phase；初始0 |
| 24 | errors_before_start | 调用SMStart前的PIB累计错误快照 |
| 28 | errors_after_start | SMStart返回后的PIB累计错误快照 |

依据 `src/cyfxslfifosync.c:327`、`:230`、`:253`、`:471`。B1 的后三项为阶段诊断快照，不是独立错误累计计数。B0/B1 各字段逐项采集，不宣称跨所有字段的原子快照。不要把某次WAVEFORM快照固定成健康常量；实测 `reports/auto_protocol_01.log` 的前后快照已不同，而PIB/DMA错误均0。B1可能不在普通旧固件中存在；上位机应记录不支持，不能假设所有PID相同设备都有GP01。

<a id="section-9"></a>

## 9. 可复核请求及已有实测证据

以下为既有 `commands/read_system.bin`，sequence=2、source=0001、READ_REG addr0000/count5，共52 B。最后4 B是小端CRC `DBB788C6`：

```text
56 4C 50 31 01 00 01 0A 34 00 00 00 02 00 00 00
01 00 02 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00 00 08 00 00 00 00 00 00 00 05 00 00 00
C6 88 B7 DB
```

2026-09-19 本次只读离线复核调用既有 `host/analyze_capture.py` 的 analyze 函数，未打开 USB、未修改原捕获：

| 既有捕获（FX3 reports/下） | 字节 | VLP帧 | CRC通过/失败 |
|---|---:|---:|---|
| continuous_capture_01/bulk_in.bin | 11680 | 154 | 154 / 0 |
| auto_protocol_01/bulk_in.bin | 7816 | 103 | 103 / 0 |
| sensor_six_60s_01/bulk_in.bin | 7278076 | 91087 | 91087 / 0 |

首个捕获的第96帧是既有PING应答：type02、seq1、source0001、msg00FE、status0、payload回显`PING`，flags1、cycleFFFFFFFF；基本帧52 B，CRC=`BFBEBCF3`。这验证当前实板输出格式和CRC，不代表本次又发送PING，也不扩展为所有命令/边界已实板验证的结论。


<a id="section-10"></a>

## 10. 六传感器 payload 与温控确认协议

核对日期：2026-09-19。依据封存 `integrated_20260916/member3_uart_sensors/rtl`、`lead_system/rtl`、`common_baseline/fpga/rtl/include`，对照当前 `fx3_gpif_debug_20260918/host/analyze_sensors.py`、`bmp_compensation.py`、`plot_six_sensors.py` 以及六路实测摘要。本文件只描述已实现接口；本次未操作硬件，未修改 V2、封存源码或现有解码脚本。

### 1. 分流及公共规则

表内 offset 均从 **VLP payload 第一个字节**开始；EPS 的内部数据另以 D 表示。整数均为小端，I32 为二进制补码；不能将传感器线上 Modbus 的大端寄存器直接当作 VLP 字段端序。

| 设备 | source_id | frame_type | message_id | payload schema | FPGA寄存器页 / ID_VERSION |
|---|---|---|---|---|---|
| PTB210 | 0x0040 | 0x10 | 0x1100 | 1 | 0x6000 / 0x00400100 |
| EPSILON | 0x0042 | 0x10 | 0x1200 | 无TLV，完整FDILink帧 | 0x6200 / 0x00420101 |
| BMP390 | 0x0043 | 0x10 | 0x1100 | 1 | 0x6300 / 0x00430101 |
| SHT45 | 0x0044 | 0x10 | 0x1100 | 1 | 0x6400 / 0x00440101 |
| TFA1500-L | 0x0045 | 0x10 | 0x1100 | 1 | 0x6500 / 0x00450100 |
| AI8 | 0x0046 | 0x10 | 0x1100 | 2 | 0x6600 / 0x00460200 |

0x0041 为未接入的 HMP；0x0046 当前必须按 AI8 schema 2 处理，不能套旧 RD105 schema 1。上述数据 `cycle_id=0xFFFFFFFF`。health `(type,msg)=(0x12,0x1400)/(0x12,0x1401)/(0x11,0x1402)` 不是测量样本。

TLV record：offset 0 为 schema U16，offset 2 为 count U16；offset 4 起每项是 `tag U16, type U8, length U8, value[length]`，value 之后补零到四字节边界。常用 type：3=U32，7=I32，11=原始字节；标量 length=4。按 tag 解析并验证长度、类型、count 和 padding，勿把示例的固定 offset 当作永远不变的结构，尤其 AI8 有可选项、BMP有两类记录。

外层 flags：bit0=时间戳有效，bit2=采样时捕获的同步状态，bit3=之前发生记录丢弃，bit4=设备/测量状态异常。bit0 不保证设备无报警或 GNSS 有效；bit3 不是本条数值必坏，应保留数据并标明连续性损失。具体 bit4：PTB 将任意 sticky ERROR 映射到此位；SHT heater 非零置位；AI8 离线/报警/HOST[9:8]非零置位。不能只看 CRC 判全正常。保留 raw flags、错误位和计数器增量。

### 2. PTB210 压力

payload 固定12字节、schema=1、count=1：

| TLV header offset | value offset | tag/type/length | 内容及换算 |
|---:|---:|---|---|
| 4 | 8 | 0x0012 / I32 / 4 | pressure_mPa；Pa=值/1000，hPa=值/100000 |

这里 mPa 是毫帕，宏名 `PRESSURE_MPA` 不表示 MPa。实测原值101459000对应101459 Pa、1014.59 hPa。原始串口文本已由 FPGA 转为整数；上位机不再解析 ASCII。

### 3. BMP390 校准与原始采样

本板有效 I2C 地址为 **0x77**（FPGA地址0x6310）；0x76只是RTL复位默认值，芯片 ID 读回0x60。`0x6338 COMPENSATION_MODE` 当前只支持0，FPGA不输出已补偿的 Pa/℃。

| 记录 | schema/count | payload长度 | TLV header/value offset | tag/type/length | 内容 |
|---|---|---:|---|---|---|
| 初始化校准 | 1/1 | 32 | 4 / 8 | 0x0100 / BYTES / 21 | 芯片0x31..0x45按地址升序的21字节；payload29..31为零padding |
| 压温双开采样 | 1/2 | 20 | 4 / 8 | 0x0101 / U32 / 4 | pressure_adc_raw，低24位有效，高8位零 |
| 同一双开采样 | 同上 | 同上 | 12 / 16 | 0x0102 / U32 / 4 | temperature_adc_raw，低24位有效，高8位零 |
| 单通道采样 | 1/1 | 12 | 4 / 8 | 压力0x0101或温度0x0102 / U32 / 4 | 由PWR低两位选择；不能要求永远有两项 |

0x0100是元数据，不应计为压力样本。启动/重新初始化后缓存同一设备、本次采集阶段的校准；在收到校准和对应温度原码前，不输出虚构的补偿压力。后接入流的主机可能错过初始化校准，当前没有独立“重发校准”命令。保留原码、校准及来源，避免跨设备/复位阶段套用。

校准21字节精确解析格式为 Python `'<HHbhhbbHHbbhbb'`，顺序 `t1,t2,t3,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11`；对应字节offset为0,2,4,5,7,9,10,11,13,15,16,17,19,20。H/U16无符号，h/I16及b/I8有符号。现有 `bmp_compensation.compensate(calibration, pressure_raw, temperature_raw)` 按 Bosch 附录返回 `(pressure_Pa, temperature_C)`；先求温度，再代入压力多项式。需要hPa再除100。主机补偿不等同于传感器精度/标定验收。

### 4. SHT45 温湿度

payload 固定28字节，schema=1、count=3：

| TLV header offset | value offset | tag/type | 内容及单位 |
|---:|---:|---|---|
| 4 | 8 | 0x0010 / I32 | temperature_mC，℃=值/1000 |
| 12 | 16 | 0x0011 / U32 | humidity_milli_pct，%RH=值/1000 |
| 20 | 24 | 0x0001 / U32 | 当前 heater 模式，0=关闭，1..6=加热模式 |

三个length均4。FPGA已验证原始两组CRC，执行 `floor(rawT*175000/65535)-45000` 和 `clamp(floor(rawRH*125000/65535)-6000,0,100000)`；不要把湿度值再按65535缩放。heater非零同时使外层bit4置位，须标为加热测量；常规环境温湿度显示应保留该标识。

### 5. TFA1500-L 距离

payload固定12字节、schema=1、count=1，header offset4、value offset8，tag=0x0013/type=U32/length=4，数值已经是 **mm**。HF原始距离由FPGA乘10；LF使用配置的比例。主机不能再统一乘10。checksum/格式/无效距离由解析器处理，只有 distance_pulse 形成测量记录；寄存器 LAST_DISTANCE 的历史值不能代替当前有效样本。

### 6. EPSILON FDILink与姿态

VLP payload 保留完整内帧；不能从 VLP offset0直接按AHRS浮点读数。

| VLP payload offset | 长度 | 内容 |
|---:|---:|---|
| 0 | 1 | 0xFC |
| 1 | 1 | FDILink message ID（与VLP 0x1200不同） |
| 2 | 1 | 内部数据长度L |
| 3 | 1 | 内部序号U8，回绕不代表VLP序号回绕 |
| 4 | 1 | header CRC8 |
| 5 | 2 | payload CRC16，**高字节在前** |
| 7 | L | 内部数据D，小端字段 |
| 7+L | 1 | 0xFD；VLP payload总长=L+8 |

CRC8覆盖内帧offset0..3，init=0，反射多项式0x8C；CRC16覆盖D，init=0、多项式0x1021、MSB-first。外层CRC通过后仍校验内部长度/结束符/两重CRC。当前RTL仅转发ID 0x40..0x7F中掩码允许的完整帧；默认全选。

姿态首选 **FDILink ID=0x41、L=48**，不是ID=0x40。以下 D offset 对应VLP payload offset加7：

| D offset | VLP payload offset | 类型 | 字段 | 单位 |
|---:|---:|---|---|---|
| 0/4/8 | 7/11/15 | 3×F32 | RollSpeed/PitchSpeed/HeadingSpeed | rad/s |
| 12/16/20 | 19/23/27 | 3×F32 | Roll/Pitch/Heading | rad；显示度=值×180/π |
| 24/28/32/36 | 31/35/39/43 | 4×F32 | Q1/Q2/Q3/Q4 | 无量纲，保留手册顺序 |
| 40 | 47 | I64 | 设备Timestamp | µs，设备自身时间语义 |

用逐字节小端读取或 `struct.unpack_from`，这些字段相对 VLP payload并非4字节对齐。拒绝NaN/Inf进入普通曲线。现有 `plot_six_sensors.py` 读取 `<3f` 于D offset12，符合手册11.2.2；`analyze_sensors.py` 本身只保留raw payload，不直接输出三个姿态角。

ID0x40为56字节IMU：D0/4/8角速度rad/s，D12/16/20含重力加速度m/s²，D24/28/32磁场mG，D36 IMU温度℃、D40压力Pa、D44压力温度℃（以上F32），D48设备I64时间µs。若扩展显示须按内部ID和长度分派。

导航/时间状态：ID0x50且L=102时，D2为 **Filter_status U16**，D4为 **Filter_Update_status U16**，D6/D10为UTC秒/微秒U32；Filter_status bit3为UTC初始化。现有分析器的 `navigation_status_raw` 把D2/D4拼为U32，只是原始打包值，不是手册定义的单一导航状态字段。ID0x53且L=4的D2同为Filter_status；ID0x51且L=8的D0/D4为UTC秒/微秒。RAW值不是已有效UTC。当前实测UTC初始化均false；室内无GNSS天线应显示姿态和“GNSS/UTC未有效”，不能把通信正常或有姿态推断成定位、绝对时间有效。RTL进一步要求UTC秒>=946684800、微秒<1000000才发布对应时间标签。

#### 6.1 位置与速度：MSG_INS/GPS，内部ID0x42

手册11.2.3定义内部数据长度 **L=72**、完整FDILink帧长80。以下全部offset从内部数据D开始，换成VLP payload offset统一加7。F32/F64均为IEEE-754小端浮点，数值可为负；不得按整数重解释或截断为无符号数。

| D offset | 长度/类型 | 字段顺序 | 单位与语义 |
|---:|---|---|---|
| 0/4/8 | 3×4/F32 | BodyVelocity_X/Y/Z | m/s，机体系速度 |
| 12/16/20 | 3×4/F32 | BodyAcceleration_X/Y/Z | m/s²，机体系加速度 |
| 24/28/32 | 3×4/F32 | Location_North/East/Down | m，上电为0，从坐标原点到当前的北/东/地向距离 |
| 36/40/44 | 3×4/F32 | Velocity_North/East/Down | m/s，NED速度 |
| 48/52/56 | 3×4/F32 | Acceleration_North/East/Down | m/s²，NED加速度 |
| 60 | 4/F32 | Pressure_Altitude | m，由气压计直接得到、未经融合的高度 |
| 64 | 8/I64 | Timestamp | µs，设备上电以来时间，MCU外部晶振时钟源（手册11.4.1） |

此0x42是内部消息ID；与VLP source_id=0x0042只是数值碰巧相同。Location_N/E/D是局部距离，**不是纬度/经度/海拔**。NED的Down向下为正；不能直接把Down显示成“海拔”。本消息自身没有导航有效位，必须关联同源当前0x50或0x53的Filter_status及状态时效。手册9.1.2明确：导航初始化完成后位置、速度、加速度值才有效；外部位置源也可能完成导航初始化，因此导航初始化与当前GNSS fix应分别显示。

#### 6.2 融合经纬度、速度、UTC：MSG_SYS_STATE，内部ID0x50

手册11.2.4定义 **L=102**、完整FDILink帧长110；该消息包含本条自己的状态和数值，优先用于避免跨消息状态关联。表中D offset加7即VLP payload offset。

| D offset | 长度/类型 | 字段 | 单位/说明 |
|---:|---|---|---|
| 0 | 2/U16 | System_status | 设备系统故障/报警位图，见6.4 |
| 2 | 2/U16 | Filter_status | 初始化与GNSS状态，见6.4 |
| 4 | 2/U16 | Filter_Update_status | 滤波量测更新有效位，见6.4 |
| 6 | 4/U32 | Unix_time | UTC秒，自1970-01-01 00:00:00 UTC |
| 10 | 4/U32 | Microseconds | 秒内微秒，必须<1000000 |
| 14 | 8/F64 | **Latitude** | WGS84纬度，**rad** |
| 22 | 8/F64 | **Longitude** | WGS84经度，**rad** |
| 30 | 8/F64 | Height | m；此字段表用词为“海拔” |
| 38/42/46 | 3×4/F32 | Velocity_north/east/down | m/s，北/东/地向速度 |
| 50/54/58 | 3×4/F32 | Body_acceleration_X/Y/Z | m/s²，机体系加速度 |
| 62 | 4/F32 | G_force | m/s²，估计重力加速度 |
| 66/70/74 | 3×4/F32 | Roll/Pitch/Heading | rad，范围分别[-π,π]、[-π/2,π/2]、[0,2π] |
| 78/82/86 | 3×4/F32 | Angular_velocity_X/Y/Z | rad/s，机体系角速度 |
| 90/94/98 | 3×4/F32 | Latitude/Longitude/Height_standard_deviation | **m**，不是rad或度 |

经纬度在线顺序为 **纬度在前、经度在后**；均乘180/π转为地图API通常需要的度，再按目标API要求排列，例如需要[longitude,latitude]时显式交换。保留double精度，并检查有限数、纬度范围[-π/2,π/2]、经度范围[-π,π]。这些范围是主机输入合理性检查，不能代替导航状态判断；(0,0)是合法地理坐标，也不能单靠“非零”判定位成功。

高度基准须保留原始字段名和来源：手册此表写Height为“海拔”，基础坐标章节5.7又描述椭球体高度；仅凭这两处文本不能确认已做哪个大地水准面转换。交付API宜名为 `height_m_raw` 并附消息来源，未进一步核定前不自动把它标成特定椭球高或正高，不自行添加/减去Geo_sep。

#### 6.3 原始GNSS与独立位置/速度消息

MSG_RAW_GNSS（手册11.2.13，ID **0x59，L=74**，完整帧82字节）提供原始接收机输出，不与0x50融合结果混名。

| D offset | 长度/类型 | 字段 | 单位/说明 |
|---:|---|---|---|
| 0/4 | 2×4/U32 | Unix_time_stamp / Microseconds | UTC秒 / 秒内µs |
| 8/16/24 | 3×8/F64 | Latitude / Longitude / Height | 纬度rad / 经度rad / 高度m |
| 32/36/40 | 3×4/F32 | Velocity_north/east/down | m/s |
| 44/48/52 | 3×4/F32 | Latitude/Longitude/Height_standard_deviation | m |
| 56 | 4/F32 | Course | **度**，GPS航向；此项不能再乘180/π |
| 60 | 4/F32 | Geo_sep | m，手册描述“大地高与椭球高的高度差”；本文不推断其正负转换约定 |
| 64 | 4/F32 | Diff_age | s，差分龄期 |
| 68 | 4/F32 | Reserved4 | 保留 |
| 72 | 2/U16 | Status | 原始GNSS状态，位定义见下表 |

0x59 Status（手册11.4.7）bits3:0为GNSS fix枚举（与6.4表相同），bit4=多普勒速度有效，bit5=时间有效，bit6=外部GNSS，bit7=倾斜有效，bit8=航向有效，bit9=浮点模糊度航向，bits15:10保留。按字段分别检查有效位：时间使用bit5，速度使用bit4，航向使用bit8；不能以时间有效替代定位有效。位置fix=0/1不显示为有效定位，2仅标2D，不承诺高度有效。

| 内部ID / 手册节 | L / 完整帧长 | 精确D布局 | 说明 |
|---|---|---|---|
| 0x51 / 11.2.5 | 8 / 16 | D0 U32 Unix_time秒；D4 U32 Microseconds | 需关联Filter_status UTC初始化；没有自身valid位 |
| 0x53 / 11.2.7 | 4 / 12 | D0 U16 System_status；D2 U16 Filter_status | 没有Filter_Update_status字段 |
| 0x5A / 11.2.14 | 9 / 17 | D0 F32 HDOP；D4 F32 VDOP；D8 U8 GNSS_satellites | 精度因子及卫星数；不代替fix状态 |
| 0x5C / 11.2.16 | 32 / 40 | D0 F64 Latitude rad；D8 F64 Longitude rad；D16 F64 Height m；D24 F32 hAcc m；D28 F32 vAcc m | 纬度仍在经度前；自身无状态/时间字段 |
| 0x5D / 11.2.17 | 24 / 32 | D0/8/16三个F64 ECEF_X/Y/Z，m | 地心地固直角坐标，不能当经纬度 |
| 0x5F / 11.2.19 | 12 / 20 | D0/4/8三个F32 Velocity_north/east/down，m/s | NED速度；自身无状态/时间字段 |
| 0x60 / 11.2.20 | 12 / 20 | D0/4/8三个F32 Velocity_X/Y/Z，m/s | 机体系速度；自身无状态/时间字段 |

独立消息缺少自身状态时，必须保存关联的0x50/53及FPGA时间戳并标记关联新鲜程度；状态缺失/过期显示“状态未知”，不得沿用上一次会话的有效状态。手册未在这些字段表给出统一状态过期阈值，应作为上位机策略配置，不能冒称设备协议常量。

#### 6.4 导航、UTC与GNSS有效状态

Filter_status（0x50 D2或0x53 D2）为U16；手册11.4.3：

| 位 | 手册名称/语义 |
|---:|---|
| 0 | Orientation_Filter_Initialised，姿态滤波器初始化 |
| 1 | Navigation_Filter_Initialised，导航初始化 |
| 2 | Heading_Initialised，航向初始化 |
| 3 | UTC_Time_Initialised，UTC初始化 |
| 7:4 | GNSS_Fix_Status，四位枚举 |
| 8 | Event_Occurred，保留 |
| 9 | Internal_GNSS_Enabled，内部GNSS使能 |
| 10 | Magnetic_Heading_Active，磁航向有效 |
| 11 | Velocity_Heading_Enabled，航向轨迹使能 |
| 12 | Atmospheric_Altitude_Enabled，气压高度使能 |
| 13/14/15 | External_Position/Velocity/Heading_Active，当前手册标保留 |

GNSS fix枚举（手册11.4.4）：

| 值 | 状态 |
|---:|---|
| 0 | NO_GPS，无GPS模块连接或GPS故障 |
| 1 | NO_FIX，GPS没有信号 |
| 2 | 2D_FIX，2D定位 |
| 3 | 3D_FIX，3D定位 |
| 4 | DGPS，DGPS/SBAS辅助 |
| 5 | RTK_FLOAT，RTK浮点解 |
| 6 | RTK_FIXED，RTK固定解 |
| 7 | STATIC，静态定点模式，通常用于基站 |
| 8 | PPP，精密单点定位 |
| 9 | RTK_DUAL，双天线均为RTK固定解 |
| 10..15 | 此手册未定义，保留raw并显示未知，不当成更高质量等级 |

System_status（0x50 D0或0x53 D0，手册11.4.2）：bit0系统故障、bit1加速度计故障、bit2陀螺仪故障、bit3磁力计故障、bit4气压计故障、bit5 GNSS故障；bit6/7/8/9分别加速度计/陀螺仪/磁力计/气压计超量程；bit10低温、bit11高温、bit12低压、bit13高压报警；bit14 GNSS天线未连接；bit15数据输出溢出报警。它是EPS自身状态，不同于VLP外层flags或FPGA寄存器ERROR。

Filter_Update_status（仅0x50 D4，手册11.4.8）每bit为1表示该量测更新有效：bit0加速度计、1磁力计、2 GPS位置、3 GPS速度、4 GPS航迹角、5 GPS双天线航向、6零位置、7零速度、8零角速度、9外部位置、10外部速度、11外部航向、12里程计速度、13 NHC零速度、14 NHC向心加速度、15保留。**量测更新有效位不是滤波器初始化位**，不能把“本条未做GPS更新”直接等同于融合导航无效；应按原义分别保存/展示。

实现上至少分开输出 `orientation_initialized`、`navigation_initialized`、`heading_initialized`、`utc_initialized`、`gnss_fix`、`system_status`、`filter_update_status`，而不是一个万能valid。融合位置/速度先要求导航已初始化并检查对应故障/当前数据；GNSS是否有fix、是否RTK、GPS更新是否有效分别呈现。UTC要求UTC初始化且秒内微秒合法；设备I64 Timestamp是上电运行µs，不可当Unix时间。当前室内无GNSS这组数据继续只作姿态显示，新增位置解码能力不代表已有有效位置验收。

本节字段来源为本地官方手册提取文本 `E:/Documents/Vapor_Lc_App_Test/project_audit/source_review/8-1-组合导航EPSILON使用手册V1.2_20250424.txt`：11.2.3–11.2.7（第2672行起）、11.2.13–11.2.20（第2869行起）、11.4.1–11.4.4（第3816行起）、11.4.7–11.4.8（第3957行附近起）及9.1初始化说明（第767行附近）。长度按各表末字段offset+size精确计算；本次未新增或更改EPS/主机解析代码。

### 7. AI8 schema 2

先检查0x6600=0x00460200。固定11个TLV，末尾可选2个温度TLV，因此count=11..13、payload长度92/100/108字节。每项length=4。

| header offset | value offset | tag | 类型 | 字段 |
|---:|---:|---|---|---|
| 4 | 8 | 0x0460 | I32 | PV原始I16符号扩展，0.1℃/count |
| 12 | 16 | 0x0461 | I32 | SP原始I16符号扩展，0.1℃/count |
| 20 | 24 | 0x0462 | I32 | SV原始I16符号扩展，0.1℃/count |
| 28 | 32 | 0x0463 | U32 | OP原始U16零扩展，保留raw，不臆定百分比 |
| 36 | 40 | 0x0464 | U32 | ALARM U8零扩展 |
| 44 | 48 | 0x0465 | U32 | CONTROL U8零扩展 |
| 52 | 56 | 0x0466 | U32 | HOST U16零扩展 |
| 60 | 64 | 0x0467 | U32 | SET_RESULT / COMMAND_STATUS（下文位图） |
| 68 | 72 | 0x0001 | U32 | DEVICE_STATUS，bit0 online，bits4:1 transport_error，bits12:5 exception |
| 76 | 80 | 0x0002 | U32 | DEVICE_ERROR：`HOST<<16`、`CONTROL<<8`、`ALARM`三者按位或 |
| 84 | 88 | 0x0004 | U32 | SAMPLE_COUNTER，完整成功轮询次数 |
| 92（若有） | 96 | 0x0014 | I32 | SP×100000，µ℃ |
| 前述之后 | 前述之后+4 | 0x0015 | I32 | PV×100000，µ℃ |

SP或PV只有在raw∈[-21474,21474]时才分别附带对应µ℃ TLV，以避免I32溢出。若没有SP可选项但有PV，PV header/value就在92/96。原始三个量除10显示℃，µ℃除1000000显示℃，禁止混用比例或当U16处理负温。

AI8每个样本为七次成功FC03读组成的完整快照，设备地址为SP=`0x0000+channel-1`、PV=`0x0600+channel-1`、SV=`0x0480+channel-1`、OP=`0x0360+channel-1`、ALARM=`0x0680+(channel-1)/2`、CONTROL=`0x06C0+(channel-1)/2`、HOST=`0x0851`。ALARM/CONTROL奇数通道取寄存器高字节、偶数取低字节。失败的部分轮询不会覆盖上一完整快照，但会发出离线失败记录；其数值可能陈旧，必须依DEVICE_STATUS隔离。成功样本计数不能当失败记录总计数。

通信可信条件：外层CRC及结构正确、DEVICE_STATUS bit0=1、transport_error=0、exception=0。设备健康另检查ALARM和HOST[9:8]。HOST bit8=系统故障、bit9=全局报警；不能仅凭bit9推断断线或具体通道。实测56条DEVICE_STATUS=1，HOST全为0x0200，ALARM为0或0x20，因此数值可显示但全保留 **flagged/全局报警**，并非通信失败。DEVICE_ERROR并非“零才正常”的通用错误码：正常CONTROL值也占其中一字节。

### 8. AI8温控写入、寄存器与返回确认

下表是已实现的协议说明，本次没有执行设温。FPGA页地址与前述AI8内部Modbus地址属于两层地址空间。

| FPGA地址 | 属性 | 精确语义 |
|---|---|---|
| 0x6600 | RO | ID_VERSION=0x00460200 |
| 0x6604 | RW | bit0 enable；bit1本地复位；bit2 commit；bit3清FIFO。写入同时给出期望enable |
| 0x6608 | RO | bit0 enabled；**bit1 online**；bit2 pending；bit3 bus_busy或pending；**bit4单周期sample_valid**；bit5 afull；bit6 overflow；bit7任意sticky错误；bit8 time_sync；bit9 result_valid；bit10 PV可表为µ℃；bit11 SP可表为µ℃ |
| 0x660C | W1C | sticky错误位图 |
| 0x6610/14/18/1C | RW，禁用时 | baud/slave/serial_format/channel；当前共享总线19200/8N1，slave1..80，wrapper通道1..8 |
| 0x6620 | RW | I32 shadow目标µ℃；值须≥-999000000且为100000整数倍；I32可表示的最大合法倍数2147400000 |
| 0x6624 | RO | 最近PV µ℃；不可表示时0，须查STATUS bit10 |
| 0x6628 | RO | HOST左移16、CONTROL左移8，与ALARM按位或组合 |
| 0x662C | RW，禁用时 | interval_ms，1..3600000；完成轮询后的间隔，不是严格采样周期 |
| 0x6630/34/38/3C | RO | CRC错误数 / 超时数 / FIFO level / drop count |
| 0x6640 | RO | 最近成功轮询SP µ℃；不可表示时0，须查STATUS bit11；不是shadow |
| 0x6644 | RO | 在线完整样本记录数 |
| 0x6648 | RO | 成功FC10写入并FC03读回相等的确认计数 |
| 0x664C | RO | COMMAND_STATUS，下文位图 |
| 0x6650 | RW | I32符号扩展的shadow raw；合法-9990..32000，单位0.1℃；超出µ℃可表示范围时0x6620读回0，应使用raw |
| 0x6654 | RO | 高16位last_readback，低16位last_requested；两者各按I16解释 |
| 0x6658 | RO | 高16位SP，低16位PV；各I16 |
| 0x665C | RO | 高16位SV(I16)，低16位OP(U16) |
| 0x6660/64 | RW，禁用时 | timeout_ms=1..65535；retry_limit=0..3 |

serial_format=0/1/2/3对应8N1/8N2/8E1/8E2；当前共享总线只能0且baud只能19200。影子目标可在运行时写，传输/地址/通道/轮询/超时/重试配置要禁用。范围是RTL接受范围，界面可另按仪表及实验范围限制，不能误认为整个RTL范围都适合实物温控。

普通寄存器流程：先读0x6648确认数和pending；写0x6620（例如40000000表示40℃）或0x6650（400）只更新shadow；再向0x6604写5（enable+commit，full-word）。commit快照shadow并清result_valid。禁止以4代替5：AI8拒绝“commit但enable=0”；pending时再次commit返回BUSY。写shadow后尚未commit不会写外部仪表。两个影子入口互相更新表示，应选择一个使用。

普通WRITE_REG count=1成功响应只表示本地cfg写入被接受，**不能显示“温度设置成功”**。commit后核心先FC10写选中通道SP，再FC03读同一SP；两次传输校验正确且readback=requested才增加0x6648。主机等待pending=0且COMMAND_STATUS bit16=1，再要求result=0、确认计数相比基线加1（32位回绕）、0x6654请求和读回等于此次目标。没有主机事务ID嵌入SET_RESULT，主机必须串行关联本次请求并保存基线。0x6640是下次成功完整轮询刷新，可能晚于设置确认；实际PV达到目标是另一个过程。

COMMAND_STATUS与TLV0x0467：bits3:0=result，bits7:4=transport_error，bits15:8=exception，bit16=result_valid，bits31:17=0。result=0成功；1=写事务失败；2=读回事务失败；3=读回不匹配；4=核心范围错误；5=配置错误或禁用中止。result_valid=0时result=0不表示成功。transport_error=0成功、1超时、2CRC、3地址/功能/长度/echo不匹配、4Modbus异常、5UART/间隔错误、6无效请求。设备异常码、result、外层VLP命令status、sticky ERROR是不同编码空间。

禁用会中止pending请求并置result_valid=1/result=5/transport_error=6，不保证物理设备此前未接受写入；失败/超时结果也不等同于SP绝未变化，应通过后续读回确认。core不会因设置成功直接刷新轮询SP/PV缓存。

动作路径：lead `action_controller.v` 的COMMIT和AI8 SENSOR_ACTION设温路径会先保存0x6648+1，执行commit、等待pending清零，再检查确认计数。计数不符合返回VLP status=14；动作超时等另报对应命令状态。WRITE_REG的AUTO_COMMIT会转入该动作等待；它与普通count=1本地写ACK语义不同。上位机仍应读取0x664C/54保留详细结果。旧 `MODBUS_INTERFACE.md` 描述的RD105“ACK即active/禁用可排队”不适用于当前AI8。

### 9. 其余传感器寄存器检索

所有地址为字节地址，单字U32。各页公共+00 ID、+04 CONTROL、+08 STATUS、+0C ERROR；ERROR是W1C。只读快照推荐使用完整合法范围，越界可能使整条READ返回错误。在线位除AI8外为STATUS bit4；enable bit0、afull bit5、overflow bit6、error bit7、sync bit8。bit1/2/3按设备解释，禁用后online可能保留历史状态（PTB）。

| 设备 | 可连续读范围/字数 | 专用offset→含义 |
|---|---|---|
| PTB | 0x6000..6038 / 15 | +10 baud；+14 UART格式；+18 poll_ms；+1C mode；+20压力mPa；+24帧数；+28解析错误数；+2C timeout_ms；+30 ID_HASH固定0；+34 FIFO；+38 drop |
| EPS | 0x6200..623C / 16 | +10 baud；+14/+18 ID0x40..5F/60..7F掩码；+1C raw_forward；+20 good_frames；+24 CRC计数；+28 sync事件数；+2C最后内部ID；+30/+34最近有效GNSS时间标签µs低/高字；+38 FIFO；+3C drop |
| BMP | 0x6300..6340 / 17 | +10 I2C地址；+14 poll_ms；+18 OSR；+1C ODR；+20 IIR；+24 PWR；+28 chip_id；+2C压力ADC；+30温度ADC；+34 I2C错误数；+38 compensation_mode=0；+3C FIFO；+40 drop |
| SHT | 0x6400..643C / 16 | +10固定I2C0x44；+14 poll_ms；+18 repeatability；+1C heater；+20 rawT；+24 rawRH；+28 CRC错误数；+2C I2C错误数；+30 serial低字；+34 serial高字固定0；+38 FIFO；+3C drop |
| TFA | 0x6500..655C / 24 | +10 baud；+14 mode；+18 command（读0）；+1C距离mm；+20距离有效；+24 APD温度raw；+28帧数；+2C checksum错误；+30无效帧数；+34 FIFO；+38 drop；+3C timeout_ticks；+40超时数；+44 silence_ticks；+48 gap_ticks；+4C LF比例；+50 LF mask；+54设备status raw；+58 version命令；+5C格式错误数 |

CRC/解析错误为历史诊断，不应由单个非零sticky位推出所有当前数据失效。禁用、复位、清FIFO和enable的外部行为各不相同：enable可触发设备初始化/测量命令，不能把寄存器写1叫“纯被动读取”。

### 10. 时间戳和显示建议

六路共用100MHz FPGA tick，1 tick=10ns；`(tick-t0)/1e8`为相对秒。保存U64原值，JavaScript应使用BigInt或先减t0，不能长期用Number存绝对U64。设备内部EPS µs时间与FPGA tick是两个时域。

| 源 | 当前RTL捕获时刻 |
|---|---|
| PTB210 | 响应第一个UART起始脉冲 |
| EPSILON | 完整FDILink帧起始0xFC字节的UART起始脉冲 |
| TFA1500-L | 解析帧首字节的UART起始脉冲 |
| BMP390 | 优先此前捕获的INT上升沿；否则raw读取I2C请求被接受时；校准记录为校准发布时 |
| SHT45 | 启动本次测量的I2C请求被接受时 |
| AI8 | 七次读取完成、完整快照发布时；失败记录为失败完成时 |

时间戳适合共同时间轴，但六设备的物理采样时刻与延迟并不相同。当前60秒记录实测：PTB57、EPS44629（其中AHRS3053）、BMP60样本+1元数据、SHT61、TFA42137、AI8 56 flagged样本。全部91087外层帧CRC通过、无framing issue；这一结论不消除AI8报警或赋予EPS GNSS有效性。


<a id="section-11"></a>

## 11. 状态、事件与时间语义

下列五类管理 payload 均为 **32 字节、8 个小端 u32**，第一个字为 schema=1；这里的 schema 是 u32，不能按传感器的 `u16 schema + u16 field_count` 解析。

| msg_id / 类型 | +0 | +4 | +8 | +12 | +16 | +20 | +24 | +28 |
|---|---|---|---|---|---|---|---|---|
| 0x1400 SYSTEM_STATUS / 0x12 | 1 | system_status | error_summary | observed_online_mask | 0 | event_drop_count | total_drop_count | reset_reason |
| 0x1401 MODULE_STATUS / 0x12 | 1 | page | status | error | present | 0 | 0 | 0 |
| 0x1402 ERROR_EVENT / 0x11 | 1 | page | error累计位 | 本次新增错误位 | status | 0 | 0 | 0 |
| 0x1201 TIME_SYNC_EVENT / 0x11 | 1 | sync_seq | sync_tick低32 | sync_tick高32 | gnss_tag低32 | gnss_tag高32 | gnss_tag_valid | 0 |
| 0x1300 MOTOR_STATUS / 0x11 | 1 | motion_id | position（s32脉冲） | remaining（u32脉冲） | error | 0 | 0 | 0 |

0x1400 默认约每秒产生；0x1401 在轮询到 STATUS 改变时产生；0x1402 在观察到新置位 ERROR 时产生。它们不是每条测量对应一个状态帧。`present` 表示配置总线轮询响应，不等于外部传感器在线。ERROR_EVENT 的 `new_error` 是本次新出现的位集合，不能当累计错误次数。

0x1400的error_summary是管理器对已轮询模块错误的汇总，不等同于0x000C保存的sticky系统汇总。0x1400的total_drop_count是当前生产端累计量，也不等同于0x701C可清除的显示计数；对各自字段分别保存基线、比较增量。

`observed_online_mask` 的位号按轮询页序排列：0x00、01、10、20、21、30、31、40、41、50、51、60、61、62、63、64、65、66、67、70、80；不是 source mask。当前管理器统一观察各模块 STATUS.bit4，对 AI8 等具有不同位语义的模块不能据此单独判在线。上位机应结合该模块定义、有效样本到达时间和 device_status。

TIME_SYNC_VALID 表示 FPGA 同步输入的状态，并不自动保证 GNSS 定位有效或 UTC 已初始化。外层 timestamp 单位 10 ns，是本地下位机时间；当前硬件重载或时钟/复位事件可能划分新时间段。显示曲线时使用 `(tick - session_first_tick)/100000000` 秒。未经明确 UTC 初始化及语义核对，不要将 tick 或 gnss_tag 强行转换成北京时间。

### 系统与传输诊断寄存器

表中 RO=只读，RW=读写，W1C=写 1 清对应位。寄存器错误值与 VLP 响应 status 枚举不同。读多个连续寄存器可能跨越未实现空洞；首个失败会使整个 READ 仅返回错误 status，因此优先按本文列出的连续区间读取。

| 地址 | 访问 | 定义 |
|---|---|---|
| 0x0000 | RO | 系统 ID=0x00010101 |
| 0x0004 | RW/脉冲 | bit0 global_enable；bit1 系统软复位。传感器专用测试可在 global_enable=0 时逐路启用 |
| 0x0008 | RO | bit0 global_enable、bit1 clock_locked、bit3 acquisition_running、bit4 link_ready、bit7有错误；acquisition_running受global_enable门控，不能据此判断六路是否正在输出 |
| 0x000C | W1C | sticky error_summary；仍存在的底层错误会再次置位 |
| 0x0010 | RO | 构建标记 0x20260916 |
| 0x0020 | RO | capabilities0 当前 0x0000FFFF，不能推断实板验收状态 |
| 0x0024 / 0x0028 | RO | 本地 tick 低/高32位；读低字锁存高字，应先低后高 |
| 0x002C / 0x0030 | RW | stream_mask 低/高32位；复位全1 |
| 0x0034 / 0x0050 | RW | raw_stream_mask 低/高32位；复位0 |
| 0x0038 | W1C | IRQ 汇总，位按管理器轮询索引 |
| 0x003C | W1C | reset_reason：bit0初始、bit1看门狗、bit2软件、bit3时钟故障 |
| 0x0040 | RW | watchdog_timeout_ms，0关闭，最大3600000 |
| 0x0044 | WO | 喂狗寄存器；当前六路联调未启用看门狗 |
| 0x0048 / 0x004C | RO | 命令协议错误/命令CRC错误累计计数 |
| 0x0110 / 0x0114 / 0x0118 | RO | sys/time/gpif 时钟Hz，当前100M/100M/50M |
| 0x7004 / 0x8004 | RW/脉冲 | STREAM/USB bit0 enable；正常接收保持1 |
| 0x7014 / 0x802C | RO | TX FIFO level |
| 0x701C | RO/清除写 | 汇总丢弃计数；联调先保存原值并观察增量 |
| 0x7020 / 24 / 28 / 2C | RO | ADC0/ADC1/DILA0/DILA1缓存量，单位按模块，不统一视为字节 |
| 0x7030 | RO | sensor FIFO 汇总量 |
| 0x7038 / 0x703C | RO | msg / bulk pending mask；属于内部仲裁索引 |
| 0x7040 / 0x7044 | RO | 仲裁 grant 计数低/高，先读低锁存高 |
| 0x8010 / 0x8014 | RO | GPIF时钟Hz / link_ready |
| 0x8018 / 0x801C | RO | TX word计数低/高，先低后高 |
| 0x8020 / 0x8024 | RO | RX word计数低/高，先低后高 |
| 0x8028 | RO | RX FIFO level |
| 0x8030 | RW | FX3复位保持时间ms，1..10000；普通采集不修改 |
| 0x8034 | RO | GPIF stall累计计数 |
| 0x8038 / 0x803C | RO | 最近接收/发送 sequence，仅诊断 |

link_ready 表示 FX3 复位后曾观察到 DMA 就绪标志，不是持续在线证明。掉线应由 USB 设备移除、传输状态及超时联合判断。常用复核值应存储“开始/结束及增量”；清错不能修复底层原因，也不能补回丢失数据。

**START source_mask与stream_mask用途不同。** 当前stream_mask.bit1同时门控整个P2管理状态队列（SYSTEM_STATUS、MODULE_STATUS、MOTOR_STATUS），bit2同时门控TIME事件队列。因此不能将六传感器START掩码0x7D直接写入stream_mask，否则会屏蔽管理状态。六路初始联调保持stream_mask=0xFFFFFFFFFFFFFFFF、raw_stream_mask=0，通过HMP自身CONTROL=0避免启用HMP。

### 时间模块常用寄存器

0x1000 ID=0x00020101；0x1004 bit0 enable、bit1 rearm；0x1008 bit4及bit8 sync_valid；0x100C W1C错误；0x1010/14当前tick低/高、0x1018/1C最近sync tick低/高（都先低后高）；0x1020 sync序号；0x1024选择边沿（0上升、1下降）；0x1028同步超时ms（1..3600000，默认2000）；0x102C/30/34最近/最小/最大同步间隔tick；0x1038/3C最近GNSS原始tag；0x1040 tag有效标志。TIME rearm不清零本地tick。未连同步线时本地相对时间仍可用于画图。


<a id="section-12"></a>

## 12. 六路传感器联调流程

### 设备加载和连接

当前使用 USB Boot 与 RAM 应用。断电后先加载本交付基线 FPGA BIT，再通过 Cypress Control Center 的 Program → FX3 → RAM 加载 GP01 IMG；FPGA重载可能复位FX3，因此次序不能颠倒。应用枚举后退出或停止 Control Center 传输，交由上位机独占 Bulk 端点。当前 IMG 为 93,724 字节，本板 32 KiB EEPROM 不能容纳，不能把 RAM 加载成功等同于已持久烧录。

连接后读取 B1/B0，检查 GP01 标记、DMA/PIB错误计数。先启动持续IN接收循环，再发送 PING、GET_CAPABILITIES、READ_REG(0x0000,5)、READ_REG(0x6600,1)，AI8 ID应为0x00460200。保存诊断基线，接收循环在后续命令和启用阶段始终运行。

### 逐路及同时接收（已实测路径）

以下是语义操作，不是可以直接发给USB的ASCII文本；每个 R/W 都必须封装为 VLP READ_REG/WRITE_REG，source=SYSTEM 0x0001，WRITE auto_commit=0，并等待 status=0。

| 顺序 | 操作 | 目的与检查 |
|---:|---|---|
| 1 | R 0x6104、0x6704，必要时读取六路CONTROL | HMP、电机保持未启用；保存当前状态 |
| 2 | BMP处于disabled时 W 0x6310=0x77，读回 | 本板真实BMP地址是0x77；BIT默认0x76。复位/重载后重新设置 |
| 3 | W 0x6404=1 | 启用SHT45 |
| 4 | W 0x6304=1 | 启用BMP390，等待chip ID及标定元数据，再解码测量 |
| 5 | W 0x6004=1 | 启用PTB210 |
| 6 | W 0x6604=1 | 启用AI8轮询；不会自动设温或启动加热 |
| 7 | W 0x6204=1 | 启用EPSILON，已有导航流时被动接收 |
| 8 | W 0x6504=1 | 启用TFA1500-L |
| 9 | 连续接收约60s，间隔读取STATUS/ERROR/计数 | 核对六种source均收到数据，记录CRC、错误、drops增量 |
| 10 | W 0x6504=0，等待约1s并读STATUS | TFA退出并进入standby |
| 11 | W 0x6204、0x6004、0x6604、0x6304、0x6404=0 | 依次停止其余采集，每次确认写响应 |
| 12 | 持续接收尾部数据，读取状态及B0/B1 | 禁用不会撤回已排队记录；存档并结束本次会话 |

正常首次配置直接在BMP禁用时设置地址。若此前错误地址导致BOOT一直重试，应先保存诊断，再仅对BMP写0x6304=2进行局部复位，随后重新写0x6310=0x77并启用。不能把这种恢复操作作为每次接收超时的自动反应。

正式应用可使用 START_ACQ / STOP_ACQ：source=0x0001，payload=`u64 mask=0x7D, u32 options=0, u32 reserved=0`。这条命令还具有全局enable和排空等待语义，与上面的逐路W路径不同；本次60秒实板证据对应逐路W路径。STOP返回超时可能是共享通路未排空，应继续读并检查实际CONTROL/队列状态，不代表所有禁用写都失败。

采集期间保持 stream_mask=0xFFFFFFFFFFFFFFFF，STREAM/USB CONTROL.bit0=1；不要把START的0x7D写入stream_mask，因为stream bit1也控制管理状态队列。传感器直接启用路径不要求 global_enable=1；因此SYSTEM acquisition_running=0不能单独推断传感器停采。原始ADC掩码保持0，HMP/电机保持未启用。

### 温控设温操作

给上位机用户的输入单位用℃。本设备已核实0.1℃/raw，必须检查输入精度，不做静默截断。建议使用 SENSOR_ACTION（msg=0x000B，source=0x0046），payload=`u32 action=17, i32 value=40000000` 表示40.0℃；40000000是十进制，编码为小端 `00 5A 62 02`。action编码为 `11 00 00 00`。

在发送前读取0x6648确认计数。收到动作最终status=0后，再读0x6648/4C/54，检查确认计数相对之前增加、最近结果有效且成功、requested/readback都是400。显示“设备设定已确认”必须以这组证据为准；普通WRITE写shadow的status=0只表示FPGA寄存器接受。

温控目标可通过0x6620（signed微℃且整除100000）或0x6650（signed raw，范围及写回细节见传感器章节）写shadow后COMMIT。选择一种路径，不混用旧RD105寄存器单位。设置SP不修改设备启停、自动整定或锁定参数；当前PV不跟随SP上升不能仅凭通信层归因。超时后先查状态和确认计数，不盲目重复执行动作。

### 已有实板数据与验收建议

2026-09-18六路并发约60秒：91,087个VLP帧，7,278,076字节，CRC全部通过；PTB57条、EPSILON44,629条（其中AHRS 0x41共3,053条）、BMP60测量+1标定、SHT61条、TFA42,137条、AI856条。此频率是本次观测值，不是协议保证。

AI8本次PV=24.4..24.5℃、SP=40℃，HOST=0x0200始终有全局报警，4条ALARM=0x20；上位机要显示报警并保留真实数据。EPSILON室内无天线，不要求有效GNSS坐标/UTC；有一次启动相关UART错误记录而后续FDILink CRC均正确。系统/事件历史drop计数为778，在稳定并发期间未增加，各传感器drop为0。

上位机交付验收应至少包括：离线golden通过；任意USB拆包/粘包能恢复同一帧序列；单路及六路持续收包；CRC损坏不更新测量值；未知tag可跳过；掉线后明确失效并重新握手；命令失败和超时可见；AI8写后确认；新鲜度超时与设备报警分别显示。未接HMP、无天线GNSS、ADC和模拟输出不属于本次已通过项。

### 常见现象定位

| 现象 | 首先检查 |
|---|---|
| 只看到BootLoader或完全无设备 | FPGA/FX3加载次序、PMODE、供电和数据线；BootLoader尚不是VLP应用 |
| OUT成功但没有PING响应 | 是否持续读IN、B1是否GP01、是否加载正确BIT、B0错误计数 |
| 收到状态帧但没有测量值 | 对应CONTROL、stream mask、外部接线及模块STATUS/ERROR |
| BMP无数据 | 禁用时核对0x6310=0x77；是否收到0x60 chip ID及21字节标定 |
| AI8有PV但“offline”闪烁 | 不要把STATUS.bit4当online；使用该模块bit1及样本device_status |
| CRC全过但图形断点 | 模块drops、事件drops、源内计数、新鲜度；USB CRC不能证明全链路无丢弃 |
| 收到未知schema或tag | 保存原始帧并标记不支持，按长度跳过，不错位解析后续帧 |


<a id="section-13"></a>

## 13. 后续 ADC / DILA / WMS 接口

本章是当前 RTL 接口说明，供后续上位机预留解析和配置；ADC、WMS/DAC模拟输出及电机未纳入本次六路实板验证。高采样率时需独立吞吐测试，不能直接沿用六路测试的低负载结论。

### ADC RAW schema 1

source=0x0020或0x0021，msg=0x1000，type=DATA。不超过2043点时，payload如下；更长周期使用前述RAW schema 2。

| payload偏移 | 类型 | 定义 |
|---:|---|---|
| 0 | u16 | schema=1 |
| 2 | u16 | adc_bits，当前ADC0=24、ADC1=24；旧ADC3660版ADC1=16，以本字段为准 |
| 4 | u32 | sample_rate_hz，实际采样率 |
| 8 | u32 | sample_count=N |
| 12 | u32 | sample_format，0=signed32，1=unsigned32 |
| 16 | u32 | reserved=0 |
| 20 | 4×N字节 | samples |

当前两路有符号原码都扩展到32位：ADC0为CON15/AD4630 CH0，ADC1为CON16/AD4630 CH1，均为24位。旧高速ADC版source0021为16位，上位机须按adc_bits解码量程。长度应为20+4N。外层timestamp和cycle_id来自采集时保存的WMS周期标签，不是USB发送时刻。近似第k点时间为`cycle_tick + round(k*100000000/sample_rate_hz)`；出现丢点或PARTIAL标志时不得据此构造无缺口的真实时间轴。原码转V或浓度还需前端量程与校准，不由VLP协议定义。

### DILA schema 2

source=0x0030或0x0031，msg=0x1001，type=DATA。

| payload偏移 | 类型 | 定义 |
|---:|---|---|
| 0 | u16 | schema=2 |
| 2 | u16 | format |
| 4 | u32 | output_rate_hz，实际输出点率 |
| 8 | u32 | total_point_count |
| 12 | u16 | fragment_index，从0起 |
| 14 | u16 | fragment_count |
| 16 | u32 | first_point_index |
| 20 | u32 | fragment_point_count=N |
| 24 | u32 | bytes_per_point=B |
| 28 | u32 | reserved=0 |
| 32 | N×B字节 | 点数组 |

format=0：I32 H1,H2（8B/点）；format=1：I32 I1,Q1,I2,Q2（16B/点）；format=2：I32 I1,Q1,I2,Q2,H1,H2（24B/点）。**当前封存BIT使用编译默认format=0**；MODE寄存器不是运行时format切换接口。H1/H2是幅值，按整数sqrt(I²+Q²)计算并饱和到0x7FFFFFFF。I/Q与幅值按ADC码域的整数处理，不应套用WMS的Q1.31缩放，也不等于电压。

低通后I/Q没有额外乘2补偿，因此理想匹配正弦的I可约为输入幅值一半；接口本身不输出浓度。每片默认最多256点，最后一片可不足；长度=32+N×B。按会话/source/msg/cycle/timestamp分组，核对总点数、format、B、片号、首点、非重叠及flags；按first_point_index放入目标数组。超时或缺片时标记不完整，不用后一周期补前一周期。RAW与DILA两种schema 2的偏移不同，必须先按msg分派。

### 常用配置与提交

WMS0/1的页为0x2000/0x2100；DAC0/1为0x3000/0x3100。波形及DAC映射参数写shadow，调用COMMIT_CONFIG（对应WMS source和bit16/17）进行协调提交；会停WMS、等DAC空闲、提交DAC和WMS，再恢复原enable。不能用单独DAC CONTROL.bit2替代联合提交。

| WMS页offset | 含义 |
|---|---|
| +0x10 | saw频率，mHz；100Hz编码100000 |
| +0x14 / +0x18 | saw幅度/offset，signed Q1.31（实际归一化值=I32/2^31） |
| +0x1C | sine频率，mHz；20kHz编码20000000 |
| +0x20 | sine幅度，signed Q1.31 |
| +0x24 | sine相位，U32整圈；角度=value×360/2^32 |
| +0x28 / +0x2C | 请求/实际DAC更新率Hz |
| +0x30 | 周期ID |
| +0x34 / +0x38 | 最近scan tick低/高；跨scan需高/低/高复读确认 |
| +0x3C | 饱和计数，W1C |
| +0x40 | phase_mode，bits1:0 |
| +0x44 / +0x48 | 更新超限计数 / 实际周期ticks |

频率单位是millihertz，不是MHz。DAC模拟输出电压取决于参考电源、偏置/增益、滤波与接线，界面不能直接把Q1.31的1解释为1V。

| ADC页offset（0x4000/0x4100） | 含义 |
|---|---|
| +0x04 | bit0 enable、bit1 reset、bit2 commit、bit3 clear；发脉冲时保留enable |
| +0x10 / +0x14 | 请求/实际采样率Hz；ADC0请求1000..1000000并控制共同采样率，ADC1两字段只读共同实际率（默认1000000） |
| +0x1C | 周期预期样本数；0关闭DILA数量检查 |
| +0x20 / +0x24 | FIFO level / sample drop计数 |
| +0x28 / +0x2C | sample count低/高，未锁存；高/低/高复读 |
| +0x3C | RAW上传enable，默认0 |

RAW上传还需要raw_stream_mask对应bit32/33、global_enable及STREAM/USB使能。使用SET_STREAM_MASK可同时设置掩码和两路RAW_STREAM_ENABLE；不代表启动模拟采样。

| DILA页offset（0x5000/0x5100） | 含义 |
|---|---|
| +0x00 | 2026-10-02隔离精度版：0x00300101 / 0x00310101，模块版本0x0101 |
| +0x10 | 独立参考频率mHz |
| +0x14 / +0x18 | 1f相位/2f独立修正，U32整圈 |
| +0x1C | 请求输出Hz（1..input_rate/8） |
| +0x20 | MODE bit0用WMS参考、bit1启用幅值计算、bit2旁路低通；当前format0要求bit1=1 |
| +0x24 / +0x28 | 四阶1kHz低通profile：0x00040101（1MHz）或0x00040102（12.5MHz）；数值格式描述仍为0x20112E10 |
| +0x2C / +0x30 / +0x34 | 输入/混频/滤波饱和计数 |
| +0x38 / +0x3C | 输出点计数 / 排队点数 |
| +0x40 | 分片点数1..256 |
| +0x44 / +0x48 | 最近片数 / 周期容量drop计数 |
| +0x4C / +0x50 / +0x54 | 实际输出Hz / decimation / 独立参考相位增量 |

ADC/DILA同样shadow→commit→active。双AD4630版ADC0共享时序commit/reset要求两ADC均停止且PHY空闲，pending时拒绝启动；ADC1reset仅清本路。改变共同采样率前须排空旧队列，之后重新commit两DLIA。ADC1的4130/4134为只读共同CNV/BUSY参数，4138=80，4140不再映射。DILA实际点率为整数抽取后的读回值，不能总等于请求值。START选择某通道任一WMS/ADC/DILA位会启用完整通道，不能把三者视为互不相关的启动动作。未来高频开发的详细DAC限制与数值规则另见包内source_reference附录。

2026-10-02隔离精度版采用参考LUT线性插值及两级单位DC增益biquad；旧模块0x0100/二阶profile0x00020101、0x00020102保留为历史构建标识。此修订不改变VLP、DILA schema2、寄存器地址/位域或H2参考相位公式。运算流水增加3个100MHz时钟，基带滤波群延迟也增加，主机不得把曲线响应延后解释为H2相位寄存器改义；详见[精度修订与验证边界](../INTEGRATION_REVISION_20261002_DLIA_PRECISION.md)。本段只描述隔离候选源码，不构成已烧录或实板通过的声明。

<a id="section-14"></a>

## 14. 交付文件与依据

主文档：`FPGA_HOST_PROTOCOL_V1.0.md`。旧交付包的Word文件未纳入本仓库。独立章节复核报告在`review/`；真实报文摘录、golden和可运行示例在`examples/`。

协议根据当前实现核对，不将历史需求中的“计划”写成已实现功能。关键依据：集成lead_system的`rtl/vlp_cmd_rx.v`、`cmd_decoder.v`、`data_packetizer.v`、`action_controller.v`、`system_registers.v`、`status_manager.v`、`adc_cycle_framer.v`；member3_uart_sensors各设备驱动；member1_adc_dila的`dila_block_framer.v`；当前GP01的USB descriptor及固件；以及六路实测原始帧。各专业复核报告列有来源和定位。

source_reference包含已核对的高级模块原始接口说明，便于后续扩展；使用时仍以本主文档注明的当前硬件版本与实测边界为准。BMP补偿函数及其公式审查报告随包提供，EPS导航字段按使用手册V1.2解释。

版本记录：1.0（2026-09-19），首次面向上位机交付，覆盖USB、VLP、命令、六传感器、温控写确认、事件与寄存器、RAW/DILA分片、联调流程、离线golden。此次不更改线协议、FPGA/FX3固件或封存工程。


<a id="section-15"></a>

## 15. 离线参考示例使用

包内examples只处理字节和文件，Python 3.9+标准库即可运行VLP示例，不需要连接板卡。它实现基本PING/READ/普通WRITE、CRC、增量拆包、响应匹配；完整设备解码按本协议实现，提供的capture_example_summary.json可对照结果。

在交付目录执行：

```powershell
python -B examples/test_vlp_reference.py
python -B examples/vlp_reference.py examples/capture_example.bin --chunk-size 7
```

预期13项自测通过；9帧小样本CRC/结构均通过、无残留。小样本由本次捕获中不连续的原始帧摘录组成，覆盖六路、BMP标定及READ/WRITE响应，不能用此摘录计算采样率或丢包率。AI8保留flags=0x11和HOST=0x0200报警，因此summary中的all_six_have_valid_samples=false与“六路都有数据”并不矛盾。

golden_vectors.json提供三个请求完整十六进制及真实响应。PING(seq1)请求为48字节，CRC=0x764CD5B6；READ(seq2,0x0000,count5)为52字节，CRC=0xDBB788C6。真实READ应答来自另一笔seq1002，不要误匹配给seq2；响应timestamp是观察值，不作为固定生成常量。

在examples目录导入参考函数：

```python
from vlp_reference import pack_ping, pack_read, pack_write, StreamParser

request = pack_ping(sequence=1, echo=b'PING')
request2 = pack_read(address=0x0000, count=5, sequence=2)
# 只构造字节，不发送到硬件；实际发送前接收循环必须已启动。
enable_ptb = pack_write(address=0x6004, values=[1], sequence=3)
parser = StreamParser()  # 当前IN最大帧8236字节；自动处理4字节补零
```

这些pack函数返回可以交给Bulk OUT的wire bytes，已在CRC后补齐4字节；头内total_len和CRC都不包含补零。解析器的expire_partial由调用方按真实超时策略触发；USB调用短读不是半帧失效条件。

BMP390补偿示例（examples/bmp_compensation.py）：

```python
from bmp_compensation import compensate

cal = bytes.fromhex('986d4c4bf9fd1c4d1706019349005a03fa800f08f5')
pressure_pa, temperature_c = compensate(cal, 6462464, 8499712)
pressure_hpa = pressure_pa / 100.0
```

以上系数和ADC值取自附件小样本，只用于校验实现。正式运行必须使用正在连接的传感器本次收到的0x0100标定数据，不能硬编码这组系数。函数公式依据Bosch BMP390 Rev1.7附录，计算结果是Pa和℃。

上位机可使用CyUSB.dll/CyAPI接入当前Cypress驱动。若采用其他USB库，需确认驱动绑定与端点调用方式；协议示例不负责安装或切换Windows驱动。建议先完成离线样本比对，再接入真实USB，最后接界面刷新与文件存储。

