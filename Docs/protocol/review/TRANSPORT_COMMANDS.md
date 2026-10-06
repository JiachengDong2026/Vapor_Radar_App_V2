## 传输基线与 USB 接入

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

## VLP1 外层帧：精确字节布局

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

## 命令、应答与事务匹配

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

GET 当前常量依次为 `0, 0000FFFF, 00000100, 100000000, 8192, 4096, 1`（十六进制只对带前导零的位图/版本）。capabilities=FFFF 是已实现能力常量，不能作为设备实物在线或已完成实测的证据；extensions.bit0 表示 RAW schema 2。依据 `rtl/cmd_decoder.v:122`、FPGA `docs/PROTOCOL_EXTENSIONS.md:48`。READ 成功固定前导确为 **12 B**，完整应答帧长 `56+4×count`。

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

## 分片和 schema 兼容约束

外层 VLP1 没有通用 fragment 字段，packetizer 不会自动把任意超长 payload 拆片；上游模块必须在 8192 B 内构造完整 payload，非法/超长 fragment 被整体丢弃并累计 format_error_count。一个 USB 包也不是一个应用分片。

RAW `msg_id=1000`：不超过2043点的周期为 schema1（20 B payload头）；更长周期为 schema2（32 B头），每片最多2040点。schema2字段为 +0 u16 schema=2、+2 u16 adc_bits、+4 u32 sample_rate_hz、+8 u32 total_sample_count、+12 u32 sample_format、+16 u16 fragment_index、+18 u16 fragment_count、+20 u32 first_sample_index、+24 u32 fragment_sample_count、+28 u32 reserved=0、+32 samples。index从0开始。格式0=signed32，1=unsigned32，符号解释不能由通道显示单位猜测。依据 `rtl/adc_cycle_framer.v:4`、`:87` 与 `docs/PROTOCOL_EXTENSIONS.md:5`。

RAW 重组按 `(source_id,msg_id,cycle_id,timestamp,schema)` 聚合，检查 fragment_count/总点数/采样格式一致，片索引及 first_sample_index 完整、无重复/重叠；各片先独立验外层 CRC。不要只按 sequence 连续来重组，也不要跨断连会话合并。周期 bank 溢出可只保留前缀并置 PARTIAL_DATA/OVERFLOW；即使全部已发片到齐，也必须检查 flags 和 drop 计数后再认定周期完整。schema2 的 total_sample_count 是实际存储点数，不保证等于理论完整周期点数。

DILA 有自己的 payload 分片结构；具体字段按数据章节，不套用 RAW schema2 的偏移。未知 schema 必须保留原始字节或跳过该帧并提示版本不支持，不能继续按旧结构误解后续数值。

## FX3 EP0 只读诊断 B0 / B1

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

## 可复核请求及已有实测证据

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
