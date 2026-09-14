# 机载三维水汽激光雷达 FPGA 下位机 Verilog 开发指南

> 文档版本：V1.1  
> 文档性质：**开发与联调规范（Normative Development Specification）**  
> 适用 FPGA：Xilinx XCKU11P-2FFVA1156I  
> 开发环境：Xilinx Vivado  
> RTL 语言：**Verilog-2001**（不依赖 SystemVerilog interface/struct）  
> 上位机链路：CYUSB3014 FX3 + USB SuperSpeed（项目称 USB3.1，物理能力对应 5 Gbit/s SuperSpeed / USB 3.x Gen1）  
> 参考文档：`FPGA下位机详细架构与接口分配方案.md`、项目需求、板卡原理图/UCF、各设备说明书  
> 目标：开发人员只依据本指南、对应器件数据手册和模块任务书，即可独立完成 RTL、testbench、寄存器、数据接口和联调；上位机开发人员可据此完成 USB 命令、数据解析和状态管理。

---

# 1. 文档优先级与设计原则

## 1.1 文档优先级

若项目资料之间存在冲突，按以下优先级执行：

1. **本开发指南 V1.1 及后续变更记录**：内部接口、寄存器、USB 协议、模块边界；
2. 当前 `下位机需求分析.md`：功能需求；
3. 电路板原理图 + FPGA 管脚文件：物理接口、芯片连接、PACKAGE_PIN；
4. 设备官方说明书：设备原生通信协议、电气和时序；
5. 旧版项目开发表：仅作历史参考，不得覆盖当前需求。

任何修改已经冻结的接口、地址、`source_id`、包格式或顶层引脚，都必须提升协议/文档版本并记录兼容性影响。

## 1.2 必须遵守的总体规则

- 所有 RTL 使用 Verilog-2001；推荐文件扩展名 `.v`。
- 模块不得直接依赖 Qt/USB；设备模块只面向**统一寄存器总线**和**统一数据流接口**。
- 全局只有一个 `time_sync_core`，设备模块不得各自维护独立时间基准。
- ADC 原始样点**不逐点携带时间戳**；每个 WMS 锯齿扫描周期只锁存一个周期时间戳。
- 其他传感器每个有效数据记录必须带时间戳。
- ADC 物理数据源不可背压；ADC 接口之后必须先进入 FIFO，再向 DILA/RAW 两支路分发。
- 任何会改变实时链路的多寄存器参数必须采用 **shadow -> commit -> active** 机制。
- 跨时钟域：单 bit 用同步器；脉冲用 toggle/pulse CDC；多 bit 配置用握手；数据流用异步 FIFO。
- FIFO 溢出不得静默丢弃：必须累计 `drop_count`/`overflow` 并上传状态。
- 所有保留位写 0、读 0；未知命令返回明确错误，不得无响应。
- 所有 USB 多字节整数统一 **little-endian**；设备原生协议字节序在各 driver 内转换。

## 1.3 V1.1 冻结的系统参数

| 项目 | V1.1 规定 |
|---|---|
| `sys_clk` | 100 MHz，主要控制、寄存器、时间基准逻辑 |
| 时间 tick | 10 ns/tick，64 bit 自由运行 |
| `timestamp` | 64 bit local tick，单调不跳变 |
| GPIF 数据宽度 | 32 bit |
| GPIF 目标时钟 | 100 MHz；首轮上板可降至 50 MHz 验证 |
| 内部数据字宽 | 32 bit |
| 寄存器数据宽度 | 32 bit |
| 寄存器地址宽度 | 32 bit；V1.1 只占低 16 bit |
| USB/协议端序 | little-endian |
| 协议 magic | ASCII `VLP1`，字节 `56 4C 50 31` |
| CRC | CRC-32/ISO-HDLC（IEEE），poly 0x04C11DB7，reflected 0xEDB88320，init/final XOR 0xFFFFFFFF |

> `sys_clk=100 MHz` 是逻辑开发基线。ADC3660、AD4630 和 GPIF 等可以拥有独立 I/O 时钟域，必须通过 CDC 进入 `sys_clk` 数据平面。

> **V1.1 数据流变更**：DILA/RAW ADC 不再与低速传感器共用 `msg_stream` 语义。低速记录使用 `msg_stream`，高速曲线/原始块使用 `bulk_stream`；所有独立 producer 前置独立 FIFO，系统采用消息/fragment 级仲裁。

---

# 2. 总体模块层次与文件树

```text
rtl/
├── top/
│   └── vapor_lidar_top.v
├── common/
│   ├── cdc_bit_sync.v
│   ├── cdc_pulse_sync.v
│   ├── cdc_bus_handshake.v
│   ├── sync_fifo.v
│   ├── async_fifo_wrap.v
│   ├── stream_fanout_1to2.v
│   ├── crc16_modbus.v
│   └── crc32_ieee.v
├── clock/
│   └── clk_rst_mgr.v
├── time/
│   ├── time_sync_core.v
│   └── timestamp_capture.v
├── control/
│   ├── reg_ctrl_crossbar.v
│   ├── cmd_decoder.v
│   ├── status_manager.v
│   └── watchdog.v
├── wms/
│   ├── wms_wavegen.v
│   └── sine_lut.v
├── dac/
│   ├── dac_ad5791_if.v
│   └── dac_ad3552_if.v       # 预留，不作为 V1.1 必选
├── adc/
│   ├── adc_ad4630_if.v
│   ├── adc_adc3660_if.v
│   └── adc_cycle_framer.v
├── dila/
│   ├── dila_core.v
│   ├── ref_dds.v
│   ├── iq_mixer.v
│   ├── butterworth_lpf.v
│   └── dila_output_framer.v
├── sensors/
│   ├── uart_rx.v
│   ├── uart_tx.v
│   ├── rs485_halfduplex_ctrl.v
│   ├── modbus_rtu_master.v
│   ├── i2c_master.v
│   ├── ptb210_rs232.v
│   ├── hmp_modbus_rs485.v
│   ├── epsilon_rs422.v
│   ├── bmp390_driver.v
│   ├── sht45_driver.v
│   ├── tfa1500_uart.v
│   ├── rd105_uart.v
│   └── sensor_hub.v
├── motor/
│   └── stepper_ctrl.v
├── stream/
│   ├── stream_fifo.v
│   ├── stream_arbiter.v
│   └── data_packetizer.v
└── usb/
    └── usb_fx3_gpif_if.v

sim/
├── tb_clk_rst_mgr.v
├── tb_time_sync_core.v
├── tb_wms_wavegen.v
├── tb_dac_ad5791_if.v
├── tb_adc_ad4630_if.v
├── tb_adc_adc3660_if.v
├── tb_dila_core.v
├── tb_ptb210_rs232.v
├── tb_hmp_modbus_rs485.v
├── tb_epsilon_rs422.v
├── tb_bmp390_driver.v
├── tb_sht45_driver.v
├── tb_tfa1500_uart.v
├── tb_rd105_uart.v
├── tb_stepper_ctrl.v
├── tb_protocol.v
└── tb_full_e2e.v

constraints/
└── vapor_lidar_top.xdc
```

> 项目提供的是 UCF 风格 `NET ... LOC` 文件。Vivado 正式工程应维护一份 XDC；PACKAGE_PIN 根据 UCF 转换，IOSTANDARD/时钟约束必须结合原理图 Bank 电压确认，不能只做 LOC 转换后就直接上板。

---

# 3. FPGA 内部统一接口规范

# 3.1 统一配置寄存器总线 `cfg_bus`

所有可配置模块必须实现同一种同步 request/response 接口：

```verilog
input  wire        cfg_valid;
input  wire        cfg_write;
input  wire [31:0] cfg_addr;
input  wire [31:0] cfg_wdata;
input  wire [3:0]  cfg_wstrb;
output wire        cfg_ready;
output wire [31:0] cfg_rdata;
output wire        cfg_error;
```

### 时序

- 全部信号位于 `sys_clk` 域。
- Master 在 `cfg_valid=1` 时保持地址/数据/写使能稳定。
- Slave 在本拍完成访问时拉高 `cfg_ready`。
- `cfg_valid && cfg_ready` 代表一次访问完成。
- `cfg_error=1` 与 `cfg_ready=1` 同拍有效，表示地址非法、只读寄存器写入或参数不合法。
- 简单寄存器推荐 1-cycle 响应；需要 CDC 的访问允许多周期等待。
- 一次只允许一个 outstanding transaction，不需要乱序返回。

### `cfg_wstrb`

- bit0 对应 `wdata[7:0]`；bit3 对应 `wdata[31:24]`。
- 普通 32 bit 寄存器推荐要求 `4'b1111`；调试工具可使用 byte write。

---

# 3.2 高速样点流 `sample_stream`

用于 ADC FIFO -> DILA / RAW cycle framer：

```verilog
output wire        s_valid;
input  wire        s_ready;
output wire [31:0] s_data;
output wire [7:0]  s_flags;
```

握手：`s_valid && s_ready`。

`sample_data` 统一规则：

- 有符号 ADC：二补码符号扩展到 32 bit；
- 无符号 ADC：零扩展到 32 bit；
- 数据不得在上层做设备私有 bit packing；
- `s_flags[0]` = overrange；`[1]` = ADC device error；`[7:2]` 保留。

### ADC 特殊规则

ADC 物理采样不能由 `s_ready` 停止：

```text
ADC pins -> adc_xxx_if (non-stallable valid)
         -> capture FIFO
         -> stream_fanout_1to2
             ├-> RAW FIFO / adc_cycle_framer
             └-> DILA FIFO / dila_core
```

只要 capture FIFO 满就置 `ADC_ERROR.OVERFLOW` 并增加 `DROP_COUNT`。严禁“等 USB ready 再采样”。

---

# 3.3 统一低速消息流 `msg_stream`

`msg_stream` 只用于低速传感器、状态、事件和控制类短消息。DILA 曲线与 RAW ADC 大块数据从 V1.1 起改走 `bulk_stream`。

```verilog
output wire        m_valid;
input  wire        m_ready;
output wire [31:0] m_data;
output wire [3:0]  m_keep;
output wire        m_sof;
output wire        m_last;
output wire [15:0] m_source_id;
output wire [15:0] m_msg_id;
output wire [63:0] m_timestamp;
output wire [31:0] m_cycle_id;
output wire [31:0] m_flags;
```

### 规则

- `m_sof=1` 仅第一拍；`m_last=1` 仅最后一拍；
- 一条消息从 SOF 到 LAST 期间所有 metadata 必须保持不变；
- `m_keep` 非最后拍固定 `4'b1111`；
- backpressure 时全部输出保持；
- 与 WMS 无关的传感器 `cycle_id=32'hFFFF_FFFF`；
- V1.1 推荐低速消息 payload <= 1024 B；
- **每个独立传感器必须先进入自己的 msg FIFO，禁止多个 driver 直接并联一套 stream。**

# 3.4 高速块数据流 `bulk_stream`

DILA 曲线和 RAW ADC 周期数据使用独立的高速块流：

```verilog
output wire        b_valid;
input  wire        b_ready;
output wire [31:0] b_data;
output wire [3:0]  b_keep;
output wire        b_sof;
output wire        b_last;
output wire [15:0] b_source_id;
output wire [15:0] b_msg_id;
output wire [63:0] b_timestamp;
output wire [31:0] b_cycle_id;
output wire [31:0] b_flags;
```

握手与 `msg_stream` 相同，但一个 SOF..LAST 表示一个可独立仲裁的 **fragment**。V1.1 冻结：

- `BULK_FRAGMENT_MAX_BYTES = 8192`；
- DILA 默认每 fragment 最多 256 个输出点；
- DILA0/DILA1 各自具备独立 bulk FIFO / ping-pong buffer，至少能缓冲 2 个最大 fragment；
- RAW ADC0/1 也使用独立深缓存；
- arbiter 只能在 fragment 的 `b_last` 完成后切换源，禁止 beat-level interleave。

---

# 3.5 时间戳服务接口

所有模块都从 `time_sync_core` 获取：

```verilog
input wire [63:0] timestamp_now;
input wire        time_sync_valid;
input wire [31:0] time_sync_seq;
```

不要跨异步域直接逐 bit 同步 64 bit 二进制计数器。需要在异步 I/O 域捕获事件时采用以下任一方式：

1. 把事件 pulse CDC 到 `sys_clk` 后锁存 `timestamp_now`（低速传感器首选）；
2. 使用专用 `timestamp_capture` 请求/应答握手；
3. 高频、亚周期精度确实必要时使用 Gray counter snapshot。

---

# 4. 统一数据模型与数据格式

# 4.1 数据源编号 `source_id`

| ID | 数据源 |
|---:|---|
| `0x0001` | SYSTEM |
| `0x0002` | TIME |
| `0x0010` | WMS0 原位 |
| `0x0011` | WMS1 遥测 |
| `0x0020` | ADC0 原位 |
| `0x0021` | ADC1 遥测 |
| `0x0030` | DILA0 原位 |
| `0x0031` | DILA1 遥测 |
| `0x0040` | PTB210 |
| `0x0041` | HMP |
| `0x0042` | EPSILON2 |
| `0x0043` | BMP390 |
| `0x0044` | SHT45 |
| `0x0045` | TFA1500-L |
| `0x0046` | RD105 |
| `0x0047` | STEPPER |
| `0x0050` | DIAGNOSTICS |
| `0x8000–0xFFFE` | 后续扩展/实验模块 |
| `0xFFFF` | 广播/无特定 source，仅用于命令 |

`source_id` 已经发布后不得改变其含义。

# 4.2 数据消息编号 `msg_id`

| `msg_id` | 含义 |
|---:|---|
| `0x1000` | `ADC_RAW_CYCLE` |
| `0x1001` | `DILA_BLOCK` |
| `0x1100` | `SENSOR_TLV_RECORD` |
| `0x1200` | `GNSS_FDILINK_RAW` |
| `0x1201` | `TIME_SYNC_EVENT` |
| `0x1300` | `MOTOR_STATUS` |
| `0x1400` | `SYSTEM_STATUS` |
| `0x1401` | `MODULE_STATUS` |
| `0x1402` | `ERROR_EVENT` |
| `0x7F00–0x7FFF` | 预留调试数据 |

---

# 4.3 `ADC_RAW_CYCLE` payload

每个 WMS 锯齿周期形成一个独立数据记录，USB frame header 中已经携带 `timestamp` 和 `cycle_id`。

payload：

| Offset | 类型 | 字段 |
|---:|---|---|
| 0 | u16 | schema_version = 1 |
| 2 | u16 | adc_bits，例如 24/16 |
| 4 | u32 | sample_rate_hz |
| 8 | u32 | sample_count |
| 12 | u32 | sample_format：0=signed32，1=unsigned32 |
| 16 | u32 | reserved |
| 20 | s32/u32 × N | samples |

总 payload 长度 = `20 + 4*N`。

### 周期时间语义

V1.1 `timestamp` = 对应 WMS `scan_start` 在 `sys_clk` 域被确认时的 local tick。

第 k 个 ADC 样点近似时间：

```text
t(k) = timestamp + round(k * TIME_CLK_HZ / sample_rate_hz)
```

---

# 4.4 `DILA_BLOCK` V2 fragment payload

DILA 每个 WMS 周期产生两条谐波曲线。正式数据不再作为单个超长消息独占总线，而是通过 `bulk_stream` 按 fragment 上传。

| Offset | 类型 | 字段 | 说明 |
|---:|---|---|---|
| 0 | u16 | schema_version | 固定 2 |
| 2 | u16 | format | 点格式 |
| 4 | u32 | output_rate_hz | 曲线点率 |
| 8 | u32 | total_point_count | 整周期总点数 |
| 12 | u16 | fragment_index | 0-based |
| 14 | u16 | fragment_count | 整周期总 fragment 数 |
| 16 | u32 | first_point_index | 本 fragment 首点 |
| 20 | u32 | fragment_point_count | 本 fragment 点数 |
| 24 | u32 | bytes_per_point | 每点字节数 |
| 28 | u32 | reserved | 0 |
| 32 | records | 结果 | 连续点数据 |

format：

- `0`：默认两条谐波曲线，每点 `int32 H1, int32 H2`，8 B/point；
- `1`：`int32 I1,Q1,I2,Q2`，16 B/point；
- `2`：I/Q + magnitude，24 B/point。

默认 `fragment_point_limit=256`，最后一个 fragment 可不足 256 点；同一周期所有 fragment 使用相同 `b_timestamp/b_cycle_id`。上位机按 `source_id + cycle_id + fragment_index` 重组完整曲线。

---

# 4.5 低速传感器统一 `SENSOR_TLV_RECORD`

所有低速传感器使用同一个外壳，字段采用 TLV，便于后续增加新测量量而不破坏解析器。

payload 开头：

| Offset | 类型 | 字段 |
|---:|---|---|
| 0 | u16 | schema_version = 1 |
| 2 | u16 | field_count |
| 4 | TLV[] | 字段 |

单个 TLV：

```text
uint16 tag
uint8  type
uint8  length_bytes
uint8  value[length_bytes]
pad to 4-byte boundary with 0
```

### TLV type

| type | 含义 |
|---:|---|
| 1 | U8 |
| 2 | U16 |
| 3 | U32 |
| 4 | U64 |
| 5 | I8 |
| 6 | I16 |
| 7 | I32 |
| 8 | I64 |
| 9 | IEEE754 F32 raw bits |
| 10 | IEEE754 F64 raw bits |
| 11 | BYTES |
| 12 | UTF8/ASCII |
| 13 | BOOL |

### 通用 tag

| tag | 含义 |
|---:|---|
| `0x0001` | device_status |
| `0x0002` | device_error |
| `0x0003` | raw_frame |
| `0x0004` | sample_counter |
| `0x0005` | device_time_raw |
| `0x0010` | temperature_mC（I32，0.001 °C） |
| `0x0011` | humidity_milli_pct（U32，0.001 %RH） |
| `0x0012` | pressure_mPa（I32，0.001 Pa） |
| `0x0013` | distance_mm（U32） |
| `0x0014` | target_temperature_uC（I32，0.000001 °C） |
| `0x0015` | actual_temperature_uC（I32，0.000001 °C） |
| `0x0100–0x7FFF` | 设备专用扩展 |

FPGA 如果不做物理量补偿/换算，可以只上传 vendor raw field + `raw_frame`，上位机仍可解析；但 driver 必须在 README 中说明哪些标准 tag 有效。

---

# 4.6 协议分层与总表

本项目同时存在“设备协议、FPGA 内部协议、USB 对外协议”三层，开发时必须区分：

| 层级 | 对象 | 物理/逻辑接口 | 协议 | 负责模块 | 是否允许其他模块直接使用 |
|---|---|---|---|---|---|
| 设备 PHY | AD5791 x2 | SPI-like serial | AD5791 device timing/frame | `dac_ad5791_if` | 否 |
| 设备 PHY | AD4630 | CNV/BUSY/SCK/SDO | AD4630 conversion/read timing | `adc_ad4630_if` | 否 |
| 设备 PHY | ADC3660 | SPI control + source-synchronous data | ADC3660 register/data-lane protocol | `adc_adc3660_if` | 否 |
| 设备 PHY | PTB210 | RS232 | ASCII command/response | `ptb210_rs232` | 否 |
| 设备 PHY | HMP | RS485 | Modbus RTU | `hmp_modbus_rs485` | 否 |
| 设备 PHY | EPSILON2 | RS422 + SYNC | FDILink + 1PPS/SYNC | `epsilon_rs422`/`time_sync_core` | 否 |
| 设备 PHY | BMP390 | I²C | Bosch register protocol | `bmp390_driver` | 否 |
| 设备 PHY | SHT45 | I²C | Sensirion command + per-word CRC | `sht45_driver` | 否 |
| 设备 PHY | TFA1500-L | TTL UART | vendor binary protocol | `tfa1500_uart` | 否 |
| 设备 PHY | RD105 | TTL UART | Modbus RTU（首选）/ASCII | `rd105_uart` | 否 |
| 设备 PHY | DM422 | PUL/DIR/ENA | pulse/direction timing | `stepper_ctrl` | 否 |
| 内部控制 | 所有 RTL | 32-bit synchronous | `cfg_bus` | `reg_ctrl_crossbar` | 是 |
| 内部高速数据 | ADC/DILA | valid/ready | `sample_stream` | ADC FIFO/DILA | 是 |
| 低速消息 | 传感器/状态/事件 | valid/ready + metadata | `msg_stream` | `sensor_hub/stream_arbiter` | 是 |
| 高速块数据 | DILA/RAW ADC | valid/ready + metadata + fragment header | `bulk_stream` | `stream_arbiter` | 是 |
| FPGA-FX3 | XCKU11P↔FX3 | 32-bit GPIF II | VLP-GPIF V1.0 | `usb_fx3_gpif_if` | 仅 USB 层 |
| FPGA-PC | FX3 USB Bulk | byte stream | VLP1 | `cmd_decoder`/`data_packetizer`/Qt | 对外接口 |

**封装原则：设备原生协议只存在于对应 driver 内。**例如 HMP 的 Modbus 地址、EPSILON 的 FDILink 帧头、TFA 的 0x55/0x5C 都不得泄漏到 DILA、USB packetizer 或其他传感器模块；这些上层模块只看标准寄存器和标准数据流。

---

# 5. VLP1：FPGA ↔ 上位机统一 USB 协议

# 5.1 固定帧结构

所有 USB 方向的数据都使用同一个 VLP1 frame：

```text
[40-byte fixed header] [payload: 0..N bytes] [CRC32: 4 bytes]
```

固定 40-byte header：

| Offset | 长度 | 字段 | 说明 |
|---:|---:|---|---|
| 0 | 4 | magic | bytes `56 4C 50 31` = `VLP1` |
| 4 | 1 | ver_major | 1 |
| 5 | 1 | ver_minor | 0 |
| 6 | 1 | frame_type | 见下表 |
| 7 | 1 | header_words | 10，单位 32-bit word |
| 8 | 4 | total_len | header + payload + CRC |
| 12 | 4 | sequence | 每个发送方向独立递增 |
| 16 | 2 | source_id | 目标或来源 |
| 18 | 2 | msg_id | 命令/数据类型 |
| 20 | 4 | flags | 通用状态 |
| 24 | 8 | timestamp | local tick，无效时填 0 |
| 32 | 4 | cycle_id | 无效时填 0 |
| 36 | 4 | payload_len | payload 字节数 |
| 40 | N | payload | 4-byte 对齐不是强制，packetizer 可补 padding 到 GPIF word，但 padding 不计入 `payload_len` |
| 40+N | 4 | crc32 | 对 header+payload 计算，不包括 CRC 自身 |

解析器必须以 `magic + total_len + CRC` 做重同步，因此**一个 VLP frame 不要求与一个 USB transfer 边界一致**。

# 5.2 `frame_type`

| 值 | 类型 | 方向 |
|---:|---|---|
| `0x01` | CMD | PC -> FPGA |
| `0x02` | RESP | FPGA -> PC |
| `0x10` | DATA | FPGA -> PC |
| `0x11` | EVENT | FPGA -> PC |
| `0x12` | STATUS | FPGA -> PC |
| `0x7F` | PROTOCOL_ERROR | FPGA -> PC |

# 5.3 `flags`

| bit | 含义 |
|---:|---|
| 0 | `TIMESTAMP_VALID` |
| 1 | `CYCLE_ID_VALID` |
| 2 | `TIME_SYNC_VALID` |
| 3 | `OVERFLOW_SINCE_LAST` |
| 4 | `DEVICE_ERROR` |
| 5 | `PARTIAL_DATA` |
| 6 | `CONFIG_CHANGED` |
| 7 | `RAW_VENDOR_PAYLOAD` |
| 8 | `URGENT_EVENT` |
| 31:9 | reserved |

# 5.4 命令 `msg_id`

| `msg_id` | 命令 |
|---:|---|
| `0x0001` | GET_CAPABILITIES |
| `0x0002` | READ_REG |
| `0x0003` | WRITE_REG |
| `0x0004` | WRITE_REG_MASKED |
| `0x0005` | COMMIT_CONFIG |
| `0x0006` | START_ACQ |
| `0x0007` | STOP_ACQ |
| `0x0008` | RESET_MODULE |
| `0x0009` | CLEAR_ERROR |
| `0x000A` | SET_STREAM_MASK |
| `0x000B` | SENSOR_ACTION |
| `0x000C` | MOTOR_ACTION |
| `0x000D` | TIME_ACTION |
| `0x00FE` | PING |

## READ_REG payload

```text
u32 addr
u16 count_words
u16 reserved
```

RESP payload：

```text
u32 status
u32 addr
u16 count_words
u16 reserved
u32 data[count_words]
```

## WRITE_REG payload

```text
u32 addr
u16 count_words
u16 flags        // bit0: auto_commit；默认 0
u32 data[count_words]
```

## WRITE_REG_MASKED payload

```text
u32 addr
u32 mask
u32 value
```

执行：`new = (old & ~mask) | (value & mask)`。

## COMMIT_CONFIG payload

```text
u64 module_mask
```

bit 位置由 `source_id & 0x3F` 映射；也允许 `source_id=0xFFFF` + mask=all 对所有 pending 模块提交。

## START_ACQ / STOP_ACQ

payload：

```text
u64 source_mask
u32 options
u32 reserved
```

`START_ACQ` 只改变运行状态，不隐式修改参数。

## SET_STREAM_MASK

```text
u64 enable_mask
u64 raw_enable_mask
```

允许只打开 DILA/传感器，诊断时再开启 raw ADC。

# 5.5 RESP 状态码

每个 RESP payload 第一个 `u32` 必须是 status：

| 值 | 名称 |
|---:|---|
| 0 | OK |
| 1 | ERR_UNKNOWN_CMD |
| 2 | ERR_BAD_LENGTH |
| 3 | ERR_BAD_CRC |
| 4 | ERR_BAD_SOURCE |
| 5 | ERR_BAD_ADDRESS |
| 6 | ERR_READ_ONLY |
| 7 | ERR_RANGE |
| 8 | ERR_BUSY |
| 9 | ERR_TIMEOUT |
| 10 | ERR_DEVICE_OFFLINE |
| 11 | ERR_NOT_READY |
| 12 | ERR_PROTOCOL |
| 13 | ERR_UNSUPPORTED |
| 14 | ERR_COMMIT_REJECTED |
| 15 | ERR_INTERNAL |

CMD 的 `sequence` 必须由 RESP 原样返回，Qt 以此匹配异步请求。

# 5.6 协议扩展规则

- `ver_major` 改变表示不兼容格式改变；`ver_minor` 表示向后兼容增加。
- 新增 `source_id`、`msg_id`、TLV tag、寄存器地址可以只升级 minor。
- 未识别 TLV 必须跳过，不得导致整个 frame 无法解析。
- 未识别 `msg_id` 返回 `ERR_UNKNOWN_CMD`。
- Header 大小通过 `header_words` 指示；未来 header 可增长，旧解析器至少能依据 `total_len` 跳过。
- 保留字段固定填 0。

---

# 6. USB/FX3/GPIF 开发约定

# 6.1 USB endpoint 约定

建议 FX3 firmware 固定：

| Endpoint | 方向 | 类型 | 用途 |
|---|---|---|---|
| `0x02` | Host -> FX3 | Bulk OUT | CMD |
| `0x86` | FX3 -> Host | Bulk IN | RESP + DATA + EVENT + STATUS |

SuperSpeed max packet 1024 B。VLP frame 可以跨多个 USB packet；Qt 必须用字节流 parser 重新组帧。

# 6.2 推荐 GPIF Slave-FIFO 语义

由于项目资料只冻结了 `DQ/CTL/PCLK` 物理网络，没有冻结 FX3 firmware 对 CTL 的语义，本指南规定一套 **VLP-GPIF V1.0** 逻辑映射。FX3 firmware 与 FPGA RTL 必须共同遵守：

| GPIF net | 逻辑意义 | 方向（相对 FPGA） |
|---|---|---|
| `DQ[31:0]` | 双向 32-bit 数据 | inout |
| `PCLK` | 100 MHz GPIF clock，建议 FPGA 输出给 FX3 | out |
| `CTL0` | `SLCS_N` | out |
| `CTL1` | `SLWR_N` | out |
| `CTL2` | `SLRD_N` | out |
| `CTL3` | `SLOE_N` | out |
| `CTL4` | `FLAG_TX_READY`：FX3 可接收 FPGA 数据 | in |
| `CTL5` | `FLAG_RX_VALID`：FX3 有 Host OUT 数据 | in |
| `CTL6` | `FIFO_ADDR0` | out |
| `CTL7` | `FIFO_ADDR1` | out |
| `CTL8` | `PKTEND_N` | out |
| `CTL9..12` | reserved / debug | 按 firmware |
| `INTN` | FX3 异常/中断，可选 | in |
| `CYUSB_RSTN` | FX3 reset | out |

> 如果现有 FX3 firmware 已采用另一种 CTL 分配，可以修改此表，但必须同步修改：FPGA RTL、FX3 firmware、Qt 联调文档，且在版本记录中注明。

# 6.3 GPIF 写时序逻辑要求

FPGA -> FX3：

- `FLAG_TX_READY=1` 才允许发送；
- FPGA 在 PCLK 上升沿前稳定 DQ；
- `SLWR_N=0` 的每个有效 PCLK 写入一个 32-bit word；
- `FLAG_TX_READY=0` 时立即停止推进 stream；
- 短包/需要立即 flush 时使用 `PKTEND_N`；
- `tx_stream_valid && tx_stream_ready` 与 GPIF 成功写一个 word 一一对应。

Host -> FPGA：

- `FLAG_RX_VALID=1` 表示有数据；
- 读取前 `SLOE_N=0`；
- `SLRD_N=0` 的有效 PCLK 取一个 word；
- 进入 `gpif_rx_fifo` 后再跨到 `sys_clk`。

# 6.4 `usb_fx3_gpif_if` RTL 端口

```verilog
input  wire        gpif_pclk_int;      // 若 FPGA 生成，则来自 MMCM
inout  wire [31:0] FPGA_GPIF_DQ;
inout  wire [12:0] FPGA_GPIF_CTL;
input  wire        FPGA_GPIF_INTN;
output wire        CYUSB_RSTN;

// sys_clk RX stream to cmd_decoder
output wire        rx_valid;
input  wire        rx_ready;
output wire [31:0] rx_data;

// sys_clk TX stream from packetizer
input  wire        tx_valid;
output wire        tx_ready;
input  wire [31:0] tx_data;
input  wire [3:0]  tx_keep;
input  wire        tx_last;
```

内部必须有异步 FIFO，GPIF PCLK 域不直接连接 `cmd_decoder`/`packetizer`。

---

# 7. 统一寄存器规范

# 7.1 地址空间

| Base | 模块 |
|---:|---|
| `0x0000` | SYSTEM |
| `0x0100` | CLOCK/RESET |
| `0x1000` | TIME_SYNC |
| `0x2000` | WMS0 |
| `0x2100` | WMS1 |
| `0x3000` | DAC0 AD5791 |
| `0x3100` | DAC1 AD5791 |
| `0x4000` | ADC0 AD4630 |
| `0x4100` | ADC1 ADC3660 |
| `0x5000` | DILA0 |
| `0x5100` | DILA1 |
| `0x6000` | PTB210 |
| `0x6100` | HMP |
| `0x6200` | EPSILON2 |
| `0x6300` | BMP390 |
| `0x6400` | SHT45 |
| `0x6500` | TFA1500-L |
| `0x6600` | RD105 |
| `0x6700` | STEPPER |
| `0x7000` | STREAM/BUFFER |
| `0x8000` | USB/GPIF |

每块 V1.1 分配 0x100 B；以后扩展可使用下一页或 32-bit 高地址。

# 7.2 所有模块统一首部寄存器

每个模块 block 的前 0x10 字节统一：

| offset | 名称 | R/W | 含义 |
|---:|---|---|---|
| `+0x00` | `ID_VERSION` | RO | `[31:16] module_id, [15:8] major, [7:0] minor` |
| `+0x04` | `CONTROL` | RW/W1P | bit0 enable；bit1 soft_reset(W1P)；bit2 commit(W1P)；bit3 clear_fifo(W1P)；其余模块定义 |
| `+0x08` | `STATUS` | RO | bit0 enabled；1 ready；2 cfg_pending；3 busy；4 online；5 fifo_almost_full；6 overflow；7 error；8 time_sync_valid |
| `+0x0C` | `ERROR` | RO/W1C | 写 1 清对应错误；各模块低 8 bit 使用统一错误定义 |

统一 ERROR：

| bit | 含义 |
|---:|---|
| 0 | TIMEOUT |
| 1 | PROTOCOL/CRC |
| 2 | FIFO_OVERFLOW |
| 3 | DEVICE_NOT_READY |
| 4 | CONFIG_RANGE |
| 5 | CDC/INTERNAL |
| 6 | DEVICE_REPORTED_ERROR |
| 7 | DATA_FORMAT |
| 31:8 | 模块专用 |

---

# 7.3 SYSTEM `0x0000`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x0000` | ID_VERSION | RO | `module_id=0x0001` |
| `0x0004` | CONTROL | RW | bit0 global_enable；bit1 global_soft_reset(W1P) |
| `0x0008` | STATUS | RO | 系统状态 |
| `0x000C` | ERROR | RO/W1C | system summary |
| `0x0010` | BUILD_DATE | RO | YYYYMMDD packed BCD/decimal |
| `0x0014` | BUILD_TIME | RO | HHMMSS |
| `0x0018` | GIT_HASH_LO | RO | 可填 0 |
| `0x001C` | GIT_HASH_HI | RO | 可填 0 |
| `0x0020` | CAPABILITIES0 | RO | bit map：DILA/ADC/各 sensor/stepper |
| `0x0024` | UPTIME_LO | RO | sys_clk tick |
| `0x0028` | UPTIME_HI | RO | sys_clk tick |
| `0x002C` | STREAM_MASK_LO | RW | source 0..31 |
| `0x0030` | STREAM_MASK_HI | RW | source 32..63 |
| `0x0034` | RAW_STREAM_MASK_LO | RW | raw stream 开关 |
| `0x0038` | IRQ_SUMMARY | RO/W1C | 模块事件汇总 |
| `0x003C` | RESET_REASON | RO/W1C | POR/watchdog/software |
| `0x0040` | WATCHDOG_TIMEOUT_MS | RW | 0=关闭 |
| `0x0044` | WATCHDOG_KICK | WO | 写任意值喂狗 |
| `0x0048` | PROTOCOL_RX_ERR_COUNT | RO | VLP parser error |
| `0x004C` | PROTOCOL_CRC_ERR_COUNT | RO | CRC 错误 |

# 7.4 CLOCK/RESET `0x0100`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x0100..0x010C` | common | - | 通用首部 |
| `0x0110` | SYS_CLK_HZ | RO | 100000000 |
| `0x0114` | TIME_CLK_HZ | RO | 100000000 |
| `0x0118` | GPIF_CLK_HZ | RO | 实际时钟 |
| `0x011C` | MMCM_STATUS | RO | locked 位 |
| `0x0120` | RESET_MASK | RW | 模块 reset mask |
| `0x0124` | CLK_FAULT_COUNT | RO | 失锁计数 |

# 7.5 TIME_SYNC `0x1000`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x1000..0x100C` | common | - | `module_id=0x0002` |
| `0x1010` | TICK_LO | RO | 当前 local tick |
| `0x1014` | TICK_HI | RO | 当前 local tick |
| `0x1018` | LAST_SYNC_TICK_LO | RO | 最近 SYNC_IN |
| `0x101C` | LAST_SYNC_TICK_HI | RO | 最近 SYNC_IN |
| `0x1020` | SYNC_SEQ | RO | 同步事件序号 |
| `0x1024` | SYNC_EDGE | RW | 0=rising, 1=falling |
| `0x1028` | SYNC_TIMEOUT_MS | RW | 失锁阈值，默认 2000 |
| `0x102C` | LAST_SYNC_INTERVAL | RO | tick |
| `0x1030` | SYNC_JITTER_MIN | RO | tick |
| `0x1034` | SYNC_JITTER_MAX | RO | tick |
| `0x1038` | GNSS_TIME_TAG_LO | RW/RO | epsilon parser 可写入最近 GNSS time tag |
| `0x103C` | GNSS_TIME_TAG_HI | RW/RO | 同上 |

# 7.6 WMS0/1 `0x2000/0x2100`

下面以 `BASE` 表示 0x2000 或 0x2100。

| offset | 名称 | R/W | 说明 |
|---:|---|---|---|
| `+0x10` | SAW_FREQ_MHZ | RW shadow | 单位 0.001 Hz |
| `+0x14` | SAW_AMPL_Q31 | RW shadow | 归一化幅值 Q1.31 |
| `+0x18` | SAW_OFFSET_Q31 | RW shadow | DC offset Q1.31 |
| `+0x1C` | SINE_FREQ_MHZ | RW shadow | 单位 0.001 Hz |
| `+0x20` | SINE_AMPL_Q31 | RW shadow | Q1.31 |
| `+0x24` | SINE_PHASE_U32 | RW shadow | 0..2^32 对应 0..2π |
| `+0x28` | DAC_UPDATE_HZ_REQ | RW shadow | 请求更新率 |
| `+0x2C` | DAC_UPDATE_HZ_ACT | RO | 实际更新率 |
| `+0x30` | CYCLE_ID | RO | 当前 cycle |
| `+0x34` | LAST_SCAN_TICK_LO | RO | 周期开始 tick |
| `+0x38` | LAST_SCAN_TICK_HI | RO | 周期开始 tick |
| `+0x3C` | SAT_COUNT | RO/W1C | 限幅次数 |
| `+0x40` | PHASE_MODE | RW | bit0 连续相位；bit1 commit 时重置 phase |

### WMS commit

- host 写 shadow；
- 写 `CONTROL.bit2=1`；
- `cfg_pending=1`；
- 新参数在下一个 `scan_start` 边界整体复制到 active；
- `cfg_pending` 清零；
- 产生 `CONFIG_CHANGED` event。

# 7.7 DAC0/1 AD5791 `0x3000/0x3100`

| offset | 名称 | R/W | 说明 |
|---:|---|---|---|
| `+0x10` | DEVICE_CTRL | RW shadow | AD5791 控制寄存器镜像 |
| `+0x14` | CLEAR_CODE | RW | clear code |
| `+0x18` | DAC_MIN_CODE | RW | 软件限幅下界 |
| `+0x1C` | DAC_MAX_CODE | RW | 软件限幅上界 |
| `+0x20` | LAST_CODE | RO | 最近写入 code |
| `+0x24` | SPI_CLK_HZ | RW | SPI 时钟目标 |
| `+0x28` | WRITE_COUNT | RO | 写样点数 |
| `+0x2C` | SPI_ERROR_COUNT | RO | 超时/读回错误 |
| `+0x30` | DEVICE_ID_RAW | RO | 若支持读回 |

SPI 最小时序严格按 AD5791 datasheet；RTL 不得把波形算法写进本模块。

# 7.8 ADC0 AD4630 `0x4000`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x4010` | SAMPLE_RATE_REQ_HZ | RW shadow | 请求采样率 |
| `0x4014` | SAMPLE_RATE_ACT_HZ | RO | 实际采样率 |
| `0x4018` | SAMPLE_FORMAT | RO | bit width/signed |
| `0x401C` | EXPECTED_PER_CYCLE | RW | 0=自动统计 |
| `0x4020` | FIFO_LEVEL | RO | capture FIFO |
| `0x4024` | DROP_COUNT | RO/W1C | 溢出样点数 |
| `0x4028` | SAMPLE_COUNT_LO | RO | 总采样数 |
| `0x402C` | SAMPLE_COUNT_HI | RO | 总采样数 |
| `0x4030` | CNV_HIGH_TICKS | RW | device-specific |
| `0x4034` | BUSY_TIMEOUT_TICKS | RW | 超时阈值 |
| `0x4038` | IF_MODE | RW | 串行 lane 配置 |
| `0x403C` | RAW_STREAM_ENABLE | RW | raw cycle 是否上传 |

# 7.9 ADC1 ADC3660 `0x4100`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x4110` | SAMPLE_RATE_REQ_HZ | RW shadow | 请求输出/采样率 |
| `0x4114` | SAMPLE_RATE_ACT_HZ | RO | 实际 |
| `0x4118` | SAMPLE_FORMAT | RO | 输出位宽/模式 |
| `0x411C` | EXPECTED_PER_CYCLE | RW | 0=自动 |
| `0x4120` | FIFO_LEVEL | RO | capture FIFO |
| `0x4124` | DROP_COUNT | RO/W1C | 溢出 |
| `0x4128` | SAMPLE_COUNT_LO | RO | 总样点 |
| `0x412C` | SAMPLE_COUNT_HI | RO | 总样点 |
| `0x4130` | LANE_MODE | RW | 与原理图/芯片配置一致 |
| `0x4134` | DCLK_STATUS | RO | clock detect |
| `0x4138` | SYNC_COUNT | RO | SYNC events |
| `0x413C` | RAW_STREAM_ENABLE | RW | raw cycle |
| `0x4140` | SPI_CLK_HZ | RW | control SPI |

# 7.10 DILA0/1 `0x5000/0x5100`

| offset | 名称 | R/W | 说明 |
|---:|---|---|---|
| `+0x10` | REF_FREQ_MHZ | RW shadow | 独立模式基频，0.001 Hz |
| `+0x14` | PHASE_1F_U32 | RW shadow | 1f 参考相位 |
| `+0x18` | PHASE_2F_CORR_U32 | RW shadow | 2f 额外修正 |
| `+0x1C` | OUTPUT_RATE_HZ | RW shadow | 解调输出采样率 |
| `+0x20` | MODE | RW shadow | bit0 phase_lock_to_wms；bit1 output_magnitude；bit2 bypass |
| `+0x24` | LPF_PROFILE | RO | V1.1 固定 Butterworth profile ID |
| `+0x28` | DATA_Q_FORMAT | RO | fixed-point 描述 |
| `+0x2C` | IN_SAT_COUNT | RO/W1C | 输入饱和 |
| `+0x30` | MIX_SAT_COUNT | RO/W1C | 乘法饱和 |
| `+0x34` | LPF_SAT_COUNT | RO/W1C | 滤波饱和 |
| `+0x38` | OUT_COUNT | RO | 输出点 |
| `+0x3C` | FIFO_LEVEL | RO | 输出 FIFO |

DILA 参数在对应 WMS 周期边界 commit；phase-lock 模式下基频来自 WMS 正弦 phase accumulator，避免长期相位漂移。

# 7.11 PTB210 `0x6000`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x6010` | BAUD | RW | 默认建议 9600；支持 1200..19200 |
| `0x6014` | UART_FORMAT | RW | factory 常见 E71；编码 data/parity/stop |
| `0x6018` | POLL_INTERVAL_MS | RW | `.P\r` 周期 |
| `0x601C` | MODE | RW | 0=single poll，1=continuous `.BP` |
| `0x6020` | LAST_PRESSURE_MPA | RO | 可解析时，0.001 Pa |
| `0x6024` | RX_FRAME_COUNT | RO | 成功读数 |
| `0x6028` | PARSE_ERROR_COUNT | RO | ASCII 解析错误 |
| `0x602C` | TIMEOUT_MS | RW | 命令超时 |
| `0x6030` | DEVICE_ID_HASH | RO | 可选 |

# 7.12 HMP `0x6100`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x6110` | BAUD | RW | 默认 19200 |
| `0x6114` | MODBUS_ADDR | RW | 默认 240 |
| `0x6118` | SERIAL_FORMAT | RO/RW | 8N2 默认 |
| `0x611C` | POLL_INTERVAL_MS | RW | 默认 1000，可调整 |
| `0x6120` | MEAS_MASK | RW | bit0 RH；bit1 T；bit2 dew point... |
| `0x6124` | LAST_RH_F32_BITS | RO | register 0x0000 的 IEEE754 bits |
| `0x6128` | LAST_TEMP_F32_BITS | RO | register 0x0002 |
| `0x612C` | MODBUS_CRC_ERR_COUNT | RO | CRC |
| `0x6130` | MODBUS_TIMEOUT_COUNT | RO | timeout |
| `0x6134` | PRESS_COMP_F32_BITS | RW | 对应设备 0x0300，可选 |

# 7.13 EPSILON2 `0x6200`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x6210` | BAUD | RW | 默认 921600 |
| `0x6214` | FDI_MSG_MASK_LO | RW | 选择需要转发/解析的 message |
| `0x6218` | FDI_MSG_MASK_HI | RW | 同上 |
| `0x621C` | RAW_FORWARD_ENABLE | RW | 默认 1 |
| `0x6220` | GOOD_FRAME_COUNT | RO | FDI 帧 |
| `0x6224` | CRC_ERR_COUNT | RO | checksum/CRC |
| `0x6228` | SYNC_EVENT_COUNT | RO | 1PPS/SYNC |
| `0x622C` | LAST_FDI_MSG_ID | RO | 最近 msg id |
| `0x6230` | LAST_GNSS_TIME_LO | RO | parser 提取，若支持 |
| `0x6234` | LAST_GNSS_TIME_HI | RO | parser 提取 |

# 7.14 BMP390 `0x6300`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x6310` | I2C_ADDR | RW | 0x76 或 0x77，按 SDO 硬件状态 |
| `0x6314` | POLL_INTERVAL_MS | RW | 采样周期 |
| `0x6318` | OSR_CFG | RW shadow | 映射芯片 0x1C |
| `0x631C` | ODR_CFG | RW shadow | 映射 0x1D |
| `0x6320` | IIR_CFG | RW shadow | 映射 0x1F |
| `0x6324` | PWR_CTRL | RW shadow | 映射 0x1B |
| `0x6328` | CHIP_ID | RO | 期望 0x60 |
| `0x632C` | RAW_PRESSURE | RO | 24-bit raw |
| `0x6330` | RAW_TEMPERATURE | RO | 24-bit raw |
| `0x6334` | I2C_ERR_COUNT | RO | NACK/timeout |
| `0x6338` | COMPENSATION_MODE | RW | 0=host compensate；1=FPGA fixed-point（可选） |

# 7.15 SHT45 `0x6400`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x6410` | I2C_ADDR | RO | 0x44 |
| `0x6414` | POLL_INTERVAL_MS | RW | 采样周期 |
| `0x6418` | REPEATABILITY | RW | low/medium/high |
| `0x641C` | HEATER_MODE | RW | 默认 0=off；只有明确需要才开启 |
| `0x6420` | RAW_TEMP | RO | 16-bit vendor raw |
| `0x6424` | RAW_RH | RO | 16-bit vendor raw |
| `0x6428` | CRC_ERR_COUNT | RO | SHT 每个 word CRC |
| `0x642C` | I2C_ERR_COUNT | RO | NACK/timeout |
| `0x6430` | SERIAL_LO | RO | 若读取 serial |
| `0x6434` | SERIAL_HI | RO | 若读取 serial |

# 7.16 TFA1500-L `0x6500`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x6510` | BAUD | RW | 高频默认 500000；低频 >=115200 |
| `0x6514` | RANGE_MODE | RW | 0=standby；1=low-freq；2=high-freq |
| `0x6518` | COMMAND | WO | single/continuous/self-test/version |
| `0x651C` | LAST_DISTANCE_MM | RO | 最近有效距离 |
| `0x6520` | DISTANCE_VALID | RO | 0/1 |
| `0x6524` | APD_TEMP_RAW | RO | 若低频帧提供 |
| `0x6528` | RX_FRAME_COUNT | RO | 有效帧 |
| `0x652C` | CHECKSUM_ERR_COUNT | RO | checksum |
| `0x6530` | HF_INVALID_COUNT | RO | 0x3FFFFF 等无效目标 |

# 7.17 RD105 `0x6600`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x6610` | BAUD | RW | TTL 默认 38400 |
| `0x6614` | DEVICE_ADDR | RW | 默认 1 |
| `0x6618` | PROTOCOL_MODE | RW | 0=Modbus RTU，1=ASCII；V1.1 推荐 Modbus |
| `0x661C` | CHANNEL | RW | 默认 1 |
| `0x6620` | TARGET_TEMP_UC | RW shadow | 设备寄存器 0x1000，25°C=25,000,000 |
| `0x6624` | ACTUAL_TEMP_UC | RO | 设备实际温度 |
| `0x6628` | ERRORCODE | RO | 设备 ERRORCODE |
| `0x662C` | POLL_INTERVAL_MS | RW | 温度/状态轮询 |
| `0x6630` | CRC_ERR_COUNT | RO | Modbus CRC |
| `0x6634` | TIMEOUT_COUNT | RO | timeout |

# 7.18 STEPPER `0x6700`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x6710` | TARGET_PULSES | RW | 有符号，正/负可映射 DIR |
| `0x6714` | PULSE_FREQ_HZ | RW | 1..200000，必须限幅 |
| `0x6718` | PULSE_HIGH_TICKS | RW | >=250（2.5 us @100 MHz） |
| `0x671C` | DIR_SETUP_TICKS | RW | >=500（5 us @100 MHz） |
| `0x6720` | ACCEL_PPS2 | RW | 0=无加减速；预留 |
| `0x6724` | CURRENT_POSITION | RO/RW | 软件可归零 |
| `0x6728` | REMAINING_PULSES | RO | 剩余 |
| `0x672C` | COMMAND | WO | 1=start；2=stop；3=home/zero |
| `0x6730` | IO_POLARITY | RW | PUL/DIR/ENA 逻辑极性 |
| `0x6734` | MOTION_ID | RO | 每次动作递增 |

# 7.19 STREAM/BUFFER `0x7000`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x7010` | ARB_MODE | RW | 0=RR；1=priority+RR+burst_cap（默认） |
| `0x7014` | TX_FIFO_LEVEL | RO | packetizer 后 FIFO |
| `0x7018` | TX_FIFO_HIGH_WATER | RW | almost full |
| `0x701C` | TOTAL_DROP_COUNT | RO/W1C | 数据丢失总数 |
| `0x7020` | ADC0_FIFO_LEVEL | RO | RAW path 诊断 |
| `0x7024` | ADC1_FIFO_LEVEL | RO | RAW path 诊断 |
| `0x7028` | DILA0_FIFO_LEVEL | RO | DILA0 bulk FIFO |
| `0x702C` | DILA1_FIFO_LEVEL | RO | DILA1 bulk FIFO |
| `0x7030` | SENSOR_FIFO_LEVEL | RO | sensor hub 汇总/最大 FIFO level |
| `0x7034` | MAX_HIGH_BURST | RW | 默认 4，防 starvation |
| `0x7038` | MSG_PENDING_MASK | RO | 低速消息 pending bitmap |
| `0x703C` | BULK_PENDING_MASK | RO | bulk source pending bitmap |
| `0x7040` | ARB_GRANT_COUNT_LO | RO | grant 统计低 32 bit |
| `0x7044` | ARB_GRANT_COUNT_HI | RO | grant 统计高 32 bit |

# 7.20 USB/GPIF `0x8000`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x8010` | GPIF_CLK_HZ | RO | PCLK |
| `0x8014` | LINK_STATUS | RO | FX3 reset/flags/ready |
| `0x8018` | TX_WORD_COUNT_LO | RO | FPGA->FX3 |
| `0x801C` | TX_WORD_COUNT_HI | RO | FPGA->FX3 |
| `0x8020` | RX_WORD_COUNT_LO | RO | FX3->FPGA |
| `0x8024` | RX_WORD_COUNT_HI | RO | FX3->FPGA |
| `0x8028` | RX_FIFO_LEVEL | RO | async fifo |
| `0x802C` | TX_FIFO_LEVEL | RO | async fifo |
| `0x8030` | FX3_RESET_MS | RW | reset pulse |
| `0x8034` | GPIF_STALL_COUNT | RO | backpressure |
| `0x8038` | LAST_PROTOCOL_SEQ_RX | RO | 最近命令 seq |
| `0x803C` | LAST_PROTOCOL_SEQ_TX | RO | 最近 TX seq |

---

# 8. 逐模块开发规范

# 8.1 `clk_rst_mgr`

### 功能

- 接收板载 200 MHz differential/25 MHz reference 中选定的主参考；
- MMCM/PLL 产生 `sys_clk=100 MHz`、`gpif_clk`；
- 生成异步置位、同步释放的 reset；
- 提供 clock locked 和 reset reason。

### 输入/输出

```verilog
input  wire ref_clk;
input  wire ext_reset_n;
input  wire sw_global_reset;
output wire sys_clk;
output wire gpif_clk;
output wire rst_sys_n;
output wire rst_gpif_n;
output wire clocks_locked;
```

### 时序要求

- reset 只有在时钟 locked 后连续至少 16 个对应 clock cycle 才释放；
- 时钟失锁立即重新拉 reset；
- 不允许组合逻辑直接生成时钟；所有分频/enable 优先使用 clock enable。

### 验收

- 仿真 reset sequence；
- Vivado `report_clocks` 正确；
- 所有时钟有约束；
- 无 unconstrained CDC。

---

# 8.2 `time_sync_core`

### 功能

- 64-bit 100 MHz 自由运行计数器；
- `SYNC_IN` 去亚稳 + 边沿检测；
- 捕获 `last_sync_tick`；
- 统计周期、超时、失锁；
- 产生 `TIME_SYNC_EVENT`。

### 端口

```verilog
input  wire        sys_clk;
input  wire        rst_sys_n;
input  wire        sync_in_async;
output wire [63:0] timestamp_now;
output wire        sync_valid;
output wire [31:0] sync_seq;
output wire        sync_event_pulse;
output wire [63:0] sync_event_tick;
```

### 时间要求

EPSILON2 手册指出高精度同步需要数据协议 + 1PPS。`SYNC_IN` 上升沿作为 V1.1 默认有效沿。边沿经同步器后捕获会引入固定 2~3 sys_clk cycle 延迟；该延迟稳定，可后续标定。不得软件修改 `timestamp_now` 以“对齐 UTC”。

---

# 8.3 `wms_wavegen`

### 功能

- 两个独立实例；
- DDS 锯齿相位累加器 + 正弦 DDS；
- `wave = offset + saw + sine`；
- 饱和 -> 归一化 DAC code；
- 每锯齿 phase wrap 产生 `scan_start`；
- 管理 `cycle_id`；
- shadow/active commit。

### 端口

```verilog
input  wire        sys_clk;
input  wire        rst_sys_n;
input  wire        enable;
input  wire [63:0] timestamp_now;

output wire [31:0] dac_sample;
output wire        dac_sample_valid;
input  wire        dac_sample_ready;

output wire        scan_start;
output wire [31:0] cycle_id;
output wire [31:0] sine_phase;
```

### 相位步进

建议 32-bit phase accumulator：

```text
phase_inc = round(freq_hz / update_hz * 2^32)
```

上位机写 `freq_mHz`，FPGA 在 commit 时通过 64-bit 整数除法/预计算模块生成 phase_inc；也可以由上位机同时写 phase_inc，但 `freq_mHz` 仍作为可读配置保存。

### 时序

- `scan_start` 在锯齿 phase wrap 的同一个样点周期产生 1 个 `sys_clk` pulse；
- `cycle_id` 在 scan_start 递增；
- 新 active 配置只在 scan_start 生效。

---

# 8.4 `dac_ad5791_if`

### 功能

- AD5791 上电 reset/初始化；
- 将 32-bit normalized sample 映射到器件 20-bit code；
- 按器件 SPI 帧产生 `SYNC_N/SCLK/SDIN`；
- 控制 `LDAC_N/CLR_N/RESET_N`；
- 可选 SDO 读回；
- 对上层提供 `sample_ready`。

### 端口

```verilog
input  wire        sys_clk;
input  wire        rst_sys_n;
input  wire [31:0] sample_data;
input  wire        sample_valid;
output wire        sample_ready;

output wire DAC_AD5791_x_SCLK;
output wire DAC_AD5791_x_SYNCN;
output wire DAC_AD5791_x_SDIN;
input  wire DAC_AD5791_x_SDO;
output wire DAC_AD5791_x_RSTN;
output wire DAC_AD5791_x_CLRN;
output wire DAC_AD5791_x_LDACN;
```

### 重要边界

- 只做 DAC transport，不产生 WMS；
- 如果 sample 产生速率超过 SPI 最大持续更新率，不能静默丢样；应 `sample_ready=0` 并让 WMS 报配置范围错误；
- WMS 频率选择必须满足实际 DAC update rate 和模拟 LPF 带宽。

---

# 8.5 `adc_ad4630_if`

### 功能

- 初始化/复位；
- 根据 `SAMPLE_RATE_REQ_HZ` 产生 CNV；
- BUSY 时序；
- SCK + 8 路 SDO 拼接；
- 统一为 32-bit sample；
- 写 capture FIFO；
- 统计超时/overflow。

### 物理端口见第 11 章。

### 输出

```verilog
output wire        adc_sample_valid; // 对 capture FIFO，不可背压
output wire [31:0] adc_sample_data;
output wire [7:0]  adc_sample_flags;
```

### 时序

- CNV 周期必须由整数/分数分频器稳定产生；
- BUSY 超时进入错误状态，但不使全系统复位；
- SDO 接收边沿按 AD4630 数据手册决定并在 XDC 定义 input delay；
- 必须提供仿真 ADC model，覆盖正常转换、BUSY timeout、断流。

---

# 8.6 `adc_adc3660_if`

### 功能

- SPI 配置 ADC3660；
- 使用 `DCLK/FCLK` 捕获 source-synchronous data；
- 根据板上实际 lane 模式使用 IDDR/ISERDES；
- 统一输出 32-bit sample；
- 写 capture async FIFO 到 `sys_clk`。

### 时序要求

- `ADC_ADC3660_DCLK`/`FCLK` 建立 generated/source clock；
- 使用 `set_input_delay` 而不是假设 sys_clk 同步；
- data lane 到 DCLK 的 skew 必须在实现后 `report_timing` 检查；
- 不允许直接在 sys_clk always block 采 `DA/DB`。

---

# 8.7 `stream_fanout_1to2`

### 目的

一份 ADC 样点同时喂给：

1. `adc_cycle_framer`；
2. `dila_core`。

推荐先分别写两个同步 FIFO，只有两个 FIFO 都可写时接收上游一个 sample。因为上游 capture FIFO 可吸收短时拥塞。

如果任一支路长期阻塞：

- RAW stream 可配置为允许 drop RAW 而保持 DILA；
- DILA 默认 critical，不允许静默 drop；
- 具体策略通过 `FANOUT_POLICY` compile parameter 固定。

---

# 8.8 `adc_cycle_framer`

### 输入

- ADC `sample_stream`；
- WMS `scan_start/cycle_id`；
- `timestamp_now`。

### 行为

1. 第一个 scan_start：开启 cycle，锁存 timestamp/cycle_id；
2. 后续样点累计 `sample_count`；
3. 下一个 scan_start：关闭上一周期，生成 `ADC_RAW_CYCLE`；
4. 立即开始新周期；
5. 若样点数异常则 flags 标 `PARTIAL_DATA`；
6. 如果 raw stream 关闭，可以只统计而不存 payload。

### 缓存

至少 ping-pong buffer：一个正在写 ADC，一个由 packetizer 读。若最大周期数据 > BRAM 预算，改用 FIFO/DDR 深缓存，但输出协议不变。

---

# 8.9 `dila_core`

### 功能

- 1f/2f 正交混频；
- 参考相位可锁到 WMS phase；
- 固定结构 Butterworth LPF；
- 输出抽取；
- 可选择 I/Q 或 I/Q+Magnitude；
- 参数 shadow/commit。

### 输入

```verilog
sample_valid/ready/data
wms_sine_phase[31:0]
wms_scan_start
wms_cycle_id
timestamp_now
```

### 输出

`bulk_stream`，`source_id=0x0030/0x0031`，`msg_id=DILA_BLOCK`；每个 WMS 周期可包含多个 fragment。

### 滤波器约束

V1.1 Butterworth 阶数/系数固定为 compile-time profile。寄存器只暴露 `LPF_PROFILE` 只读 ID，避免上位机误以为系数可任意修改。

---

# 8.10 `uart_rx` / `uart_tx`

通用 UART 模块必须参数化：

- baud divider；
- 7/8 data bits；
- parity none/even/odd；
- 1/2 stop bits。

RX 推荐 16x oversampling；必须有 framing/parity error。不同 sensor driver 不得重复造 UART 状态机。

---

# 8.11 `ptb210_rs232`

### 物理接口

PTB210 RS232：灰 RX、绿 TX、蓝 GND；接板载 RS232A。

### 原生协议

- ASCII 命令；结尾 `<CR>`；
- baud 可设 1200..19200；
- factory serial format 手册示例为 E71（7 data, even parity, 1 stop）；
- 单次读：`.P\r`；
- 连续输出：`.BP\r`；
- 设 baud：`.BAUD.9600\r` 后 `.RESET\r`；
- 可用 `.FORM.0\r` 取消单位，便于 FPGA 解析。

### 推荐 V1.1 初始化

1. 按已知当前 serial format 连接；
2. 发送 `.FORM.0\r`；
3. 选择 single-poll 模式；
4. 周期发送 `.P\r`；
5. 第一个响应字节到达时锁存 timestamp；
6. 解析十进制 pressure；
7. 输出 `SENSOR_TLV_RECORD`。

---

# 8.12 `modbus_rtu_master`

HMP/RD105 可以共享基础 Modbus master：

### 功能

- 生成 request；
- 接收长度判断；
- CRC16/Modbus（poly reflected 0xA001，init 0xFFFF）；
- timeout；
- RS485 DE/RE 控制可选。

### 接口

```verilog
cmd_valid/cmd_ready
slave_addr
function_code
reg_addr
reg_count
write_data...
resp_valid/resp_ready
resp_status
resp_data...
```

### RTU frame timeout

支持按当前 baud 计算 3.5 character silence，不能写死一个固定 cycle 数。

---

# 8.13 `hmp_modbus_rs485`

### 物理/串口

- RS485 half-duplex；
- 19200 baud；8N2；address 240 默认；
- 板载 DE/RE 控制。

### 首版必读数据

项目 Quick Guide 给出：

- RH：register 0x0000，32-bit float；
- Temperature：0x0002，32-bit float；
- 可扩展 dew point 等；
- pressure compensation：0x0300，32-bit float；
- Modbus address：0x0600。

driver 只需做字节交换/封装，不需要 FPGA 浮点运算。F32 原始 bit pattern 可以直接作为 TLV type=F32 上传。

### 时间戳

V1.1 定义为收到响应帧第一个有效字节时的 local tick。

---

# 8.14 `epsilon_rs422`

### 物理/通信

- RS422；默认 921600 bps；
- EPSILON2 使用 FDILink；
- 外部 SYNC/1PPS 同时进入 `time_sync_core`。

### driver 分层

1. `uart_rx` 接收字节；
2. FDILink framer 找帧头/帧尾、长度；
3. 校验；
4. 提取 message ID；
5. V1.1 默认**转发完整已校验 raw FDILink frame**；
6. 只对时间同步所需的 GNSS time tag 做最小解析；
7. 生成 `GNSS_FDILINK_RAW`。

这样避免在 FPGA 内重复实现完整导航数据结构，上位机可随 FDILink 协议升级解析更多字段。

### timestamp

每个 FDILink frame timestamp = 帧首字节接收时间；同时单独发送 `TIME_SYNC_EVENT`，把 1PPS local tick 与最近 GNSS time tag 关联。

---

# 8.15 `i2c_master`

BMP390 和 SHT45 共用一条 I²C。

### 端口

```verilog
inout wire i2c_scl;
inout wire i2c_sda;
```

必须使用 open-drain 行为：输出 0 或高阻，不能主动输出 1。

### 功能

- START/repeated START/STOP；
- 7-bit address；
- ACK/NACK；
- multi-byte read/write；
- clock divider；
- timeout/bus recovery（SCL 9 pulse + STOP）；
- 仲裁由 `sensor_hub` 保证，不需要 multi-master。

推荐初始 400 kHz；若硬件/线长不稳定降至 100 kHz。

---

# 8.16 `bmp390_driver`

### 已知器件关键信息

- I²C address 由 SDO 决定：0x76 或 0x77；
- `CHIP_ID` 0x00，期望 0x60；
- raw pressure `DATA_0...` 起始 0x04；
- `INT_STATUS` 0x11；
- `PWR_CTRL` 0x1B；
- `OSR` 0x1C；
- `ODR` 0x1D；
- `CONFIG` 0x1F；
- `CMD` 0x7E。

### V1.1 最低实现

1. init 读 CHIP_ID；
2. 读取并缓存 calibration coefficient block；
3. 配置 PWR/OSR/ODR；
4. 周期读 raw pressure/temp；
5. 时间戳在 data-ready/开始读取时锁存；
6. 输出 raw TLV；
7. 补偿可选：若不在 FPGA 算，首次 init 后把 calibration raw 作为设备扩展 TLV/event 上传一次。

---

# 8.17 `sht45_driver`

### 基线

- I²C address 0x44 固定；
- 每次测量返回温度 word + CRC、湿度 word + CRC；
- driver 必须校验每个 word 的 sensor CRC；
- heater 默认关闭。

### V1.1

- 选择 high repeatability 普通测量；
- 周期触发 -> 等待 datasheet 指定 conversion time -> read；
- timestamp 语义 = 测量触发时刻；
- 输出 raw T/RH；
- 可选固定点换算为 `temperature_mC`/`humidity_milli_pct`。

---

# 8.18 `tfa1500_uart`

### 物理模式

TFA1500-L 有高频和低频工作方式，项目分配：

- 高频数据 -> 板载 TTL UART RX；
- 控制 TX/RX 通过 TTL UART；
- 低频数据可用额外 GPIO RX。

### 高频模式

- 默认 500000 bps；8N1；
- start：`55 AA CB CC CC CC CC FB`；
- stop：`55 AA CC CC CC CC CC FC`；
- 数据 5 B：header `0x5C` + 3-byte little-endian distance(cm) + checksum；
- checksum = 对 3 个 distance byte 求和、按位取反的低 8 bit；
- distance=0x3FFFFF 为无效。

### 低频模式

- baud >=115200；
- frame header 0x55；
- command + length + data + XOR checksum；
- continuous ranging command：`55 02 02 20 00 75`。

### V1.1 driver

支持 high/low 两状态解析，并统一输出 `distance_mm`。模式切换时先停止当前模式、等待接收静默，再切 RX source，防止残留字节被误解析。

---

# 8.19 `rd105_uart`

### 物理/串口

V1.1 使用 GPIO 软件 TTL UART：38400, 8N1，device address 1。

### 协议选择

RD105 同时支持 ASCII 与 Modbus RTU。V1.1 推荐 **Modbus RTU**，因为 CRC 和寄存器访问更适合 FPGA。

- function 0x03：read register(s)；
- function 0x10：write register(s)；
- channel 1 地址 0x1000..0x1999；channel 2 +0x1000；
- target temperature `TG`：0x1000，int32，占 2 regs；25 °C = 25,000,000；
- TTL default baud 38400；
- device address default 1。

### V1.1 必须实现

- 读 target/actual temperature；
- 写 target temperature；
- 读 ERRORCODE；
- CRC error/timeout；
- 所有写操作必须收到设备确认后才更新 `STATUS` 中的 active value。

---

# 8.20 `stepper_ctrl`

### 物理限制

DM422：

- 控制输入为光隔离 PUL/DIR/ENA；
- 允许 +5..+24 V 驱动；
- FPGA 3.3 V GPIO **不能直接驱动**，必须使用外置 transistor/open-drain/line driver；
- 最大 pulse rate 200 kHz；
- 脉冲宽度至少 2.5 µs；
- DIR 必须至少提前 PUL 有效沿 5 µs 稳定。

### RTL 功能

- enable/disable；
- direction；
- 定频 pulse；
- 指定 pulse count；
- stop；
- position counter；
- 可选梯形加减速。

### 时序

100 MHz 下：

- 2.5 µs = 250 ticks；
- 5 µs = 500 ticks；
- 参数小于下限必须返回 `ERR_RANGE`，不能自动产生不满足 driver 时序的 pulse。

---

# 8.21 `sensor_hub`

### 功能

- 调度共享 I²C 等公共低速资源；
- 接收每个传感器各自独立的 msg FIFO；
- 对低速传感器执行 **message-locked round-robin**；
- sensor online/offline 状态汇总；
- 不解析 USB，不重新打时间戳。

规则：一旦选中某个传感器，从 `m_sof` 到 `m_last` 完整转发后才能切换；同时到达的其他传感器消息保留在自己的 FIFO 中。

---

# 8.22 `stream_arbiter`

系统级仲裁器同时接收系统短消息、`sensor_hub` 输出和各 bulk FIFO。正式优先级：

1. **P0**：RESP / ERROR / critical EVENT；
2. **P1**：TIME_SYNC / EPSILON2 / 关键 STATUS；
3. **P2**：普通 sensor/status；
4. **P3**：DILA0/1、RAW ADC0/1 bulk fragments。

规则：

- 同级 round-robin；
- message/fragment locked：选中后一直发送到 `last`；
- 禁止 beat-level interleave；
- Bulk 一次只授予 **1 个 fragment**；
- 防 starvation：若较低优先级持续 pending，较高优先级连续完成 `MAX_HIGH_BURST`（默认 4）个 frame 后，必须给较低 pending 类别至少一次服务机会；
- `ARB_MODE=priority+RR+burst_cap` 为正式默认模式。

---

# 8.23 `data_packetizer`

### 功能

- 读取 `stream_arbiter` 已经选定的统一 frame stream；
- packetizer **不负责多源冲突仲裁**；
- 生成 40 B VLP header；
- sequence++；
- payload byte count；
- CRC32；
- 32-bit word 对齐；
- 写 USB TX FIFO。

### 特别要求

- CRC 对实际 payload bytes 计算，不包括 GPIF alignment padding；
- `total_len=44+payload_len`；
- `header_words=10`；
- 若 TX FIFO backpressure，必须停在 word boundary 并保持数据稳定。

---

# 8.24 `cmd_decoder`

### 功能

- 对 GPIF RX 字节流重新组 VLP frame；
- magic/length/version/CRC 校验；
- dispatch CMD；
- 发起 `cfg_bus`；
- 生成 RESP；
- 超长/坏帧恢复同步。

### 防御性限制

建议 `MAX_CMD_FRAME = 4096 B`。`payload_len` 超过上限立即丢弃并返回/记录协议错误，防止错误长度使 parser 卡死。

---

# 8.25 `reg_ctrl_crossbar`

地址 decode 只看 block base；一次一个 transaction。未知 block 返回 `cfg_error`。

推荐 decode：

```verilog
case (cfg_addr[15:8])
  8'h00: system;
  8'h01: clock;
  8'h10: time;
  8'h20: wms0;
  ...
  8'h80: usb;
  default: error;
endcase
```

---

# 8.26 `timestamp_capture`

### 功能

为异步/非 `sys_clk` 事件提供可靠时间戳捕获服务。典型用途是 ADC source clock 域或需要记录精确 I/O 事件的模块。

### 建议接口

```verilog
input  wire        event_clk;
input  wire        event_rst_n;
input  wire        event_pulse;
output wire        event_busy;

input  wire        sys_clk;
input  wire        rst_sys_n;
input  wire [63:0] timestamp_now;
output wire        ts_valid;
input  wire        ts_ready;
output wire [63:0] ts_value;
```

实现采用 toggle request/ack；同一请求未完成前不得接受第二个事件。高速连续事件不应使用该模块，而应使用本地计数 + 周期基准推算。

---

# 8.27 `cdc_bit_sync` / `cdc_pulse_sync` / `cdc_bus_handshake`

- `cdc_bit_sync`：2~3 级 FF，仅用于慢变化单 bit level。
- `cdc_pulse_sync`：toggle 编码，确保目标域至少看到一个 pulse。
- `cdc_bus_handshake`：源域保持 bus 稳定，发送 request toggle，目标域捕获后 ack；用于配置/状态快照。
- 禁止把多 bit bus 每位各用一个 2FF 后直接组合使用。

模块必须带 `ASYNC_REG` attribute（适用 FF）并在 XDC/report_cdc 中可识别。

---

# 8.28 `sync_fifo` / `async_fifo_wrap` / `stream_fifo`

### `sync_fifo`

单时钟域 FIFO，端口统一：

```verilog
wr_valid, wr_ready, wr_data
rd_valid, rd_ready, rd_data
level, almost_full, overflow_count
```

### `async_fifo_wrap`

不同 clock 域之间数据通道。优先使用 Vivado XPM FIFO 或经过验证的 Gray-pointer async FIFO；不得自行用普通 RAM + 同步指针拼凑。

### `stream_fifo`

对 `msg_stream`/`bulk_stream` 保存 data/keep/last；SOF metadata 要么一起写入宽 FIFO，要么用 metadata FIFO 与 payload FIFO 严格一一对应。每个 source 使用独立 FIFO，禁止多个 producer 直接共用写口。

---

# 8.29 `crc16_modbus`

### 功能

供 HMP/RD105 Modbus RTU 使用。

- init = 0xFFFF；
- reflected polynomial = 0xA001；
- 每 byte LSB-first；
- Modbus frame 线上 CRC **低字节先发**。

建议 streaming 接口：`crc_init`, `data_valid`, `data_byte[7:0]`, `crc_value[15:0]`。

---

# 8.30 `crc32_ieee`

### 功能

VLP1 header+payload CRC。

- init = 0xFFFFFFFF；
- reflected poly = 0xEDB88320；
- final XOR = 0xFFFFFFFF；
- CRC 字段自身不参与运算。

模块必须支持最后一个 32-bit word 只有 1~3 个有效 byte，通过 `keep[3:0]` 控制实际参与 CRC 的字节数。

---

# 8.31 `rs485_halfduplex_ctrl`

### 功能

专门控制 HMP 的板载 RS485 transceiver DE/RE。

### 状态

`IDLE_RX -> TURN_TO_TX -> TX -> TX_DRAIN -> TURN_TO_RX -> IDLE_RX`。

- 发送第一个 start bit 前必须先使能 TX；
- 最后一个 stop bit 完整发送后才能撤销 DE；
- turnaround guard time 以 UART bit time 配置；
- 接收期间默认 DE=0。

driver 不得在 Modbus request 还没真正发完时提前切回 RX。

---

# 8.32 `sine_lut`

### 功能

把 32-bit phase 转为定点 sin/cos。WMS 可只需要 sin，DILA reference 推荐同时需要 sin/cos。

```verilog
input  wire [31:0] phase;
output wire signed [W-1:0] sin_value;
output wire signed [W-1:0] cos_value;
```

LUT 深度和输出位宽 compile-time 固定；必须给出最大幅度、Q 格式和量化误差。WMS 与 DILA 若使用不同 LUT，实现时必须证明相位定义完全一致。

---

# 8.33 `ref_dds` / `iq_mixer` / `butterworth_lpf` / `dila_output_framer`

### `ref_dds`

独立模式下产生 1f phase；2f 使用相位左移/倍频并叠加 `PHASE_2F_CORR`。phase-lock 模式直接消费 WMS phase。

### `iq_mixer`

ADC sample 与 sin/cos 相乘；乘积位宽必须保留 full precision 后再统一 round/saturate。必须输出 saturation counter。

### `butterworth_lpf`

固定系数 IIR/FIR-realization（按最终 DILA 设计）必须明确：阶数、section 数、系数 Q 格式、内部 accumulator 位宽、rounding 和 saturation。模块不得在运行中直接写系数。

### `dila_output_framer`

把 H1/H2（或可选 I/Q、magnitude）按照第 4.4 节组成 DILA V2 fragments，负责 total_point_count、fragment_index/count、first_point_index、cycle_id/timestamp 关联。

---

# 8.34 `status_manager`

### 功能

收集各模块 `ready/online/error/overflow/drop_count`，形成：

- SYSTEM.STATUS/ERROR；
- `MODULE_STATUS` 周期帧；
- error rising-edge `ERROR_EVENT`。

状态 manager 只聚合，不自动复位故障模块。critical fault policy 由 system control 决定。

建议每 1 s 上传一次系统状态；错误事件立即插队到 arbiter 高优先级。

---

# 8.35 `watchdog`

### 功能

host watchdog 只用于检测上位机/控制链失联，不应该因单个 sensor timeout 触发。

- `WATCHDOG_TIMEOUT_MS=0`：关闭；
- host 周期写 `WATCHDOG_KICK`；
- timeout 后安全动作建议：停止 WMS/DAC、停止 motor、保留 sensor/USB 通信；
- reset reason 记录 WATCHDOG。

---

# 8.36 `dac_ad3552_if`（预留替代模块）

该模块不属于 V1.1 必须交付，但接口必须与 `dac_ad5791_if` 上层 sample contract 兼容。若后续因 WMS 正弦频率/点数要求切换到 AD3552R：

```text
wms_wavegen -> same sample stream -> dac_ad3552_if
```

不得修改 WMS/USB/DILA 协议，只增加 DAC 物理适配和对应寄存器。

---

# 9. 时间同步与数据对齐规则

# 9.1 WMS/ADC/DILA

```text
WMS scan_start
  ├─ latch cycle_timestamp
  ├─ cycle_id++
  ├─ RAW cycle boundary
  └─ DILA block/cycle metadata boundary
```

同一测量系统的 WMS、ADC raw 和 DILA 必须共享同一个 `cycle_id`。

# 9.2 UART/RS485/RS422

默认 timestamp = **一帧第一个有效字节**到达时间，而不是解析完成时间。

# 9.3 I²C

主动触发类（SHT45）：timestamp = trigger command time。  
连续/读取类（BMP390）：优先 data-ready edge；没有 INT 时用读取开始时间。

# 9.4 GNSS 绝对时间

FPGA 不把 local counter 强行改成 UTC。上位机依据：

```text
TIME_SYNC_EVENT:
  local_tick_at_pps
  sync_seq
  nearest_gnss_time_tag
```

建立：

```text
UTC = UTC_at_sync + (local_tick - local_tick_at_sync) / 100000000
```

这样数据时间单调，GNSS 短时丢锁也不会使历史时间戳跳变。

---

# 10. 上电、初始化和系统运行状态机

```text
RESET
  -> CLOCK_WAIT
  -> FX3_RESET/WAIT
  -> ADC_DAC_INIT
  -> SENSOR_INIT
  -> IDLE
  -> RUNNING
  -> IDLE
```

## RUNNING 前的 critical 条件

- clock locked；
- GPIF RX/TX FIFO 可用；
- 至少对应需要启动的 DAC/ADC 初始化成功；
- DILA ready；
- WMS 参数合法。

低速 sensor offline 不阻止主测量系统运行，但必须在状态里报告。

## START 顺序

1. 清本次 acquisition FIFO/stat counters（不清 lifetime error counter 可选）；
2. enable ADC capture；
3. enable DILA；
4. enable WMS/DAC；
5. 从第一个完整 `scan_start` 开始上传周期数据；
6. low-speed sensors 独立按 polling scheduler 工作。

## STOP 顺序

1. 禁止产生新的 WMS cycle；
2. 完成当前已开始 cycle 或标记 partial；
3. drain DILA/RAW/message FIFO；
4. packetizer flush；
5. 回 IDLE。

---

# 11. 物理接口与 FPGA 引脚总表

# 11.1 设备分配

| 设备 | 板卡接口 | FPGA 模块 |
|---|---|---|
| 原位激光驱动器 | AD5791-0 -> CON7 SMA | WMS0 + DAC0 |
| 原位探测器 | CON15 -> AD4630 CH1 | ADC0 + DILA0 |
| 遥测激光驱动器 | AD5791-1 -> CON8 SMA | WMS1 + DAC1 |
| 遥测探测器 | CON17 -> ADC3660 CH1 | ADC1 + DILA1 |
| PTB210 | CON25 RS232A | `ptb210_rs232` |
| HMP | CON19 RS485 | `hmp_modbus_rs485` |
| EPSILON2 | CON24 RS422 + CON22 SYNC | `epsilon_rs422` + time |
| BMP390 | CON11 I²C | `bmp390_driver` |
| SHT45 | CON11 I²C | `sht45_driver` |
| TFA1500-L | CON21 TTL UART + CON11 pin4 LF RX | `tfa1500_uart` |
| RD105 | CON11 pin5/7 GPIO UART | `rd105_uart` |
| DM422 | CON11 pin9/10/11 + 外置驱动级 | `stepper_ctrl` |

# 11.1.1 外部连接器针脚明细

| 设备 | 设备端 | 板端连接 | 说明 |
|---|---|---|---|
| PTB210 | Grey RX | CON25 pin2 `RS232A_TXD` | FPGA/PHY -> PTB |
| PTB210 | Green TX | CON25 pin3 `RS232A_RXD` | PTB -> FPGA/PHY |
| PTB210 | Blue GND | CON25 pin5 GND | 共地 |
| HMP | pin4 RS485+ | CON19 pin5 `RS485_A` | A/+ |
| HMP | pin2 RS485- | CON19 pin1 `RS485_B` | B/- |
| HMP | pin3 common | CON19 pin3 GND | reference |
| EPSILON2 AUX | pin6 TX+ (Y) | CON24 pin2 `RS422_RXA` | device TX+ -> board RX+ |
| EPSILON2 AUX | pin7 TX- (Z) | CON24 pin3 `RS422_RXB` | device TX- -> board RX- |
| EPSILON2 AUX | pin9 RX+ (A) | CON24 pin7 `RS422_TXY` | board TX+ -> device RX+ |
| EPSILON2 AUX | pin8 RX- (B) | CON24 pin8 `RS422_TXZ` | board TX- -> device RX- |
| EPSILON2 AUX | pin1 GND | CON24 pin5 GND | 共地/参考 |
| EPSILON2 main | pin7 SYNC | CON22 SMA `SYNC_IN_5V0` | 板上转换后到 AP18 |
| BMP390 | SCL | CON11 pin1 | AH13 |
| BMP390 | SDA | CON11 pin3 | AJ13 |
| BMP390 | INT | CON11 pin2 | AN13，可选 |
| SHT45 | SCL | CON11 pin1 | 与 BMP 共 I²C |
| SHT45 | SDA | CON11 pin3 | 地址 0x44 |
| TFA1500-L | pin1 GND | CON21 pin4 | GND |
| TFA1500-L | pin3 HF TX | CON21 pin1 | -> FPGA UART RX |
| TFA1500-L | pin4 LF TX | CON11 pin4 | -> AP13 |
| TFA1500-L | pin5 RX | CON21 pin2 | <- FPGA UART TX |
| TFA1500-L | pin6 Power_EN | CON21 pin3 | FPGA UART EN |
| RD105 | TTL RX | CON11 pin5 | <- AM12；设备侧 pin 号待线束确认 |
| RD105 | TTL TX | CON11 pin7 | -> AN12；设备侧 pin 号待线束确认 |
| DM422 | PUL drive | CON11 pin9 -> 外置驱动级 | AM11，不直接接光耦输入 |
| DM422 | ENA drive | CON11 pin10 -> 外置驱动级 | AK12 |
| DM422 | DIR drive | CON11 pin11 -> 外置驱动级 | AN11 |

PTB/HMP/EPSILON/TFA 的设备供电按各自手册/现有线束提供，**不得从普通 FPGA I/O 引脚供电**。

# 11.2 固定串口/SYNC FPGA pins

| net | ball | 用途 |
|---|---:|---|
| `FPGA_RS232A_TXD` | AM14 | PTB RX |
| `FPGA_RS232A_RXD` | AL14 | PTB TX |
| `FPGA_RS232B_TXD` | AP16 | 预留 |
| `FPGA_RS232B_RXD` | AP19 | 预留 |
| `FPGA_RS422_TXD_L` | AN18 | EPSILON2 RX |
| `FPGA_RS422_RXD_L` | AM15 | EPSILON2 TX |
| `FPGA_RS485_TXD_L` | AN16 | HMP |
| `FPGA_RS485_RXD_L` | AM17 | HMP |
| `FPGA_RS485_DERE_L` | AN19 | HMP DE/RE |
| `FPGA_UART_TXD_L` | AP14 | TFA control TX |
| `FPGA_UART_RXD_L` | AN14 | TFA HF RX |
| `FPGA_UART_EN_L` | AK16 | TTL UART enable |
| `SYNC_IN` | AP18 | GNSS sync/1PPS |

# 11.3 Bank88 / CON11

| CON11 | UCF net | ball | 分配 |
|---:|---|---:|---|
| 1 | `GPIO_BANK88_LP1` | AH13 | I²C SCL |
| 2 | `GPIO_BANK88_LP2` | AN13 | BMP390 INT（可选） |
| 3 | `GPIO_BANK88_LN1` | AJ13 | I²C SDA |
| 4 | `GPIO_BANK88_LN2` | AP13 | TFA LF RX |
| 5 | `GPIO_BANK88_LP3` | AM12 | RD105 TX |
| 7 | `GPIO_BANK88_LN3` | AN12 | RD105 RX |
| 9 | `GPIO_BANK88_LP5` | AM11 | MOTOR_PUL |
| 10 | `GPIO_BANK88_LP6` | AK12 | MOTOR_ENA |
| 11 | `GPIO_BANK88_LN5` | AN11 | MOTOR_DIR |
| 6/8/12..24 | - | - | 预留 |

Bank88 原理图标注 3.3 V level。I²C 必须有正确 pull-up；RD105 设备侧 TTL 电平若不是 3.3 V 兼容，必须加电平转换，禁止直接把 5 V 接 FPGA。

# 11.4 AD5791-0

| net | ball |
|---|---:|
| `DAC_AD5791_0_SCLK` | K21 |
| `DAC_AD5791_0_RSTN` | M21 |
| `DAC_AD5791_0_SYNCN` | K25 |
| `DAC_AD5791_0_SDIN` | L24 |
| `DAC_AD5791_0_SDO` | L27 |
| `DAC_AD5791_0_CLRN` | H24 |
| `DAC_AD5791_0_LDACN` | H27 |

# 11.5 AD5791-1

| net | ball |
|---|---:|
| `DAC_AD5791_1_SCLK` | R22 |
| `DAC_AD5791_1_RSTN` | G26 |
| `DAC_AD5791_1_SYNCN` | J26 |
| `DAC_AD5791_1_SDIN` | G27 |
| `DAC_AD5791_1_SDO` | H26 |
| `DAC_AD5791_1_CLRN` | J24 |
| `DAC_AD5791_1_LDACN` | H23 |

# 11.6 AD4630

| net | ball |
|---|---:|
| `ADC_AD4630_SDI` | K20 |
| `ADC_AD4630_RSTN` | R21 |
| `ADC_AD4630_CNV` | P21 |
| `ADC_AD4630_BUSY` | P20 |
| `ADC_AD4630_CSN` | L22 |
| `ADC_AD4630_SCK` | N23 |
| `ADC_AD4630_SDO0` | R25 |
| `ADC_AD4630_SDO1` | R26 |
| `ADC_AD4630_SDO2` | T24 |
| `ADC_AD4630_SDO3` | R23 |
| `ADC_AD4630_SDO4` | N21 |
| `ADC_AD4630_SDO5` | L20 |
| `ADC_AD4630_SDO6` | M20 |
| `ADC_AD4630_SDO7` | K22 |

# 11.7 ADC3660

| net | ball |
|---|---:|
| `ADC_ADC3660_DB6` | M22 |
| `ADC_ADC3660_DB5` | N22 |
| `ADC_ADC3660_DA5` | P23 |
| `ADC_ADC3660_SCLK` | P24 |
| `ADC_ADC3660_DCLKIN` | P26 |
| `ADC_ADC3660_DCLK` | N24 |
| `ADC_ADC3660_CLKN` | M26 |
| `ADC_ADC3660_CLKP` | M25 |
| `ADC_ADC3660_SEN` | K23 |
| `ADC_ADC3660_DA6` | L23 |
| `ADC_ADC3660_FCLK` | M27 |
| `ADC_ADC3660_SDIO` | J23 |
| `ADC_ADC3660_RST` | J25 |
| `ADC_ADC3660_SYNC` | G25 |

> 这些 net 反映原理图实际连接。数据 lane 的确切逻辑位、DDR packing 和输出模式必须结合 ADC3660 配置寄存器和原理图确认后冻结在 driver README。

# 11.8 GPIF DQ pins

| bit | ball | bit | ball | bit | ball | bit | ball |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 0 | C13 | 8 | J13 | 16 | K8 | 24 | D11 |
| 1 | F13 | 9 | H13 | 17 | E8 | 25 | A9 |
| 2 | B10 | 10 | H12 | 18 | D9 | 26 | A10 |
| 3 | E13 | 11 | D13 | 19 | C8 | 27 | B11 |
| 4 | C9 | 12 | G12 | 20 | A12 | 28 | E10 |
| 5 | E11 | 13 | L8 | 21 | D8 | 29 | A13 |
| 6 | C12 | 14 | J11 | 22 | B9 | 30 | D10 |
| 7 | H11 | 15 | F12 | 23 | B12 | 31 | C11 |

# 11.9 GPIF control pins

| net | ball |
|---|---:|
| CTL0 | L13 |
| CTL1 | K12 |
| CTL2 | K11 |
| CTL3 | J10 |
| CTL4 | F9 |
| CTL5 | H8 |
| CTL6 | J8 |
| CTL7 | K13 |
| CTL8 | F8 |
| CTL9 | G9 |
| CTL10 | K10 |
| CTL11 | J9 |
| CTL12 | H9 |
| `FPGA_GPIF_INTN` | L12 |
| `FPGA_GPIF_PCLK` | G10 |
| `CYUSB_RSTN` | G11 |

---

# 12. 模块之间的完整信号连接

```text
                         +--------------------+
EPSILON SYNC ----------->| time_sync_core     |---- timestamp_now ----+
                         +--------------------+                       |
                                                                    |
PC CMD -> FX3 -> GPIF -> usb_fx3_gpif_if -> cmd_decoder -> reg_ctrl_crossbar
                                                        |           | | | | |
                                                        |           | | | | +--> sensors
                                                        |           | | | +----> DILA
                                                        |           | | +------> ADC
                                                        |           | +--------> DAC
                                                        |           +----------> WMS
                                                        v
                                                    RESP stream

WMS0 -> DAC0 -> laser0                 detector0 -> ADC0 capture FIFO
  | scan_start/cycle_id                                |
  |                                                   +--> fanout --> DILA0
  +--------------------------------------------------->+             |
                                                      +--> RAW framer|
                                                                   |
WMS1 -> DAC1 -> laser1                 detector1 -> ADC1 capture FIFO|
  |                                                   +--> DILA1 ----+
  +--------------------------------------------------->+--> RAW ------+
                                                                   |
PTB/HMP/EPS/BMP/SHT/TFA/RD -> per-source msg FIFO -> sensor_hub ---+
Stepper/status/time event -----------------------------------------+
                                                                   v
                                                           stream_arbiter
                                                                   v
                                                           data_packetizer
                                                                   v
                                                           USB TX FIFO
                                                                   v
                                                           GPIF -> FX3 -> PC
```

---

# 13. 上位机最小实现指南

Qt/C++ 上位机至少实现四个组件。

## 13.1 USB transport

- 打开 FX3 VID/PID；
- Bulk OUT endpoint 0x02；
- Bulk IN endpoint 0x86；
- 多个异步 IN transfer 保持 pipe 满载；
- 不假设一次 read == 一帧。

## 13.2 VLP parser

字节 ring buffer：

1. 搜索 `56 4C 50 31`；
2. 缓存至少 40 B；
3. 检查 `header_words`、`total_len`、`payload_len`；
4. `total_len == 44 + payload_len`；
5. 等待完整 frame；
6. CRC32；
7. CRC 错误丢掉当前 magic 的第 1 byte 后重新搜索，而不是清空全部 buffer；
8. 根据 frame_type/source/msg 分发。

## 13.3 Command manager

- sequence 单调递增；
- map `sequence -> pending request`；
- 超时重试只能用于幂等命令（READ/PING）；
- WRITE/MOTOR 等默认不自动重发，除非先查询状态确认。

## 13.4 Register/config model

上位机 UI 参数修改流程：

```text
user edits parameters
 -> WRITE_REG shadow values
 -> check RESP OK
 -> COMMIT_CONFIG
 -> wait CONFIG_CHANGED EVENT / cfg_pending clears
 -> update UI active state
```

不要每改一个 textbox 就直接改变 active FPGA 参数。

---

# 14. Vivado 与 Verilog 工程规范

## 14.1 语言规范

- `default_nettype none` 推荐在 RTL 顶部启用，并在文件末尾恢复；
- 禁止隐式宽度截断；
- signed arithmetic 明确 `$signed()`；
- 状态机有 default recovery；
- counter/timeout 使用参数和 `$clog2` 若当前 Vivado Verilog 支持，否则显式 localparam；
- 不能用仿真 delay `#` 实现硬件时序；
- 外部双向线（I²C/GPIF）只在顶层/PHY wrapper 使用 tri-state。

## 14.2 约束

正式 XDC 至少包含：

- PACKAGE_PIN；
- IOSTANDARD；
- reference clocks `create_clock`；
- generated clocks；
- ADC source-synchronous input delays；
- GPIF output/input delays；
- async clock groups；
- 合理 CDC false path 只由统一 CDC primitive/module 管理。

不得用“大范围 false_path”掩盖 timing error。

## 14.3 仿真要求

每个模块必须有 self-checking testbench，至少覆盖：

- reset；
- 正常 transaction；
- 边界值；
- timeout；
- backpressure；
- CRC/校验错误；
- FIFO full/empty；
- soft reset 后恢复；
- 非法配置返回 error。

## 14.4 综合/实现门槛

交付前至少：

- Synthesis PASS；
- Implementation/Timing 至少对应模块/集成阶段无未解释 critical warning；
- `report_cdc` 主要跨域已解释；
- 无 inferred latch；
- 无 multiple driver；
- 无 unconstrained primary clock。

---

# 15. 模块交付标准

每个成员交付文件夹：

```text
<module_name>/
├── rtl/
│   └── *.v
├── sim/
│   ├── tb_*.v
│   └── vectors/
├── constraints/          # 若模块含专用时序约束
│   └── *.xdc
├── docs/
│   ├── README.md
│   ├── register_map.md
│   └── test_report.md
└── scripts/              # 可选 Tcl
    └── run_sim.tcl
```

README 必须写：

- 功能；
- clock/reset；
- RTL 端口表；
- 使用的统一接口；
- 物理引脚；
- 寄存器；
- 原生设备协议；
- 时序；
- 异常处理；
- 测试结果；
- 已知限制。

---

# 16. 分阶段集成与验收

## Stage 1：纯 RTL 接口

- 所有 module testbench PASS；
- cfg bus read/write；
- msg stream backpressure；
- source_id/msg_id 正确。

## Stage 2：控制平面

PC/模拟 host -> VLP CMD -> cmd_decoder -> reg -> RESP，全链路仿真。

必须测试：

- READ_REG；
- WRITE_REG；
- bad CRC；
- bad address；
- commit；
- duplicate/unknown command。

## Stage 3：WMS + ADC + DILA

- 两套链路独立；
- sample rate/frequency 独立；
- cycle_id 连续；
- raw frame 每周期只有一个 timestamp；
- DILA 相位锁定稳定；
- USB backpressure 不影响物理 ADC 捕获直到 FIFO 预算耗尽。

## Stage 4：传感器

逐设备模拟/实物测试：

- PTB；
- HMP；
- EPSILON + 1PPS；
- BMP/SHT 共总线；
- TFA high/low；
- RD105；
- motor。

## Stage 5：FX3 + Qt

- endpoint 枚举；
- 10^6+ frame parser 稳定；
- 人为分割 USB reads 仍能重组；
- CRC 错误可恢复；
- 长时间吞吐无 sequence gap；
- 拔插/FX3 reset 后软件能重连。

## Stage 6：系统压力测试

- ADC raw 两路开启；
- DILA 两路开启；
- 所有 sensor 开启；
- motor movement；
- 故意暂停 PC read 产生 backpressure；
- 检查 overflow/drop/status 是否完全可观测。

---

# 17. 关键错误处理策略

| 故障 | 本模块行为 | 系统行为 |
|---|---|---|
| BMP/SHT offline | retry + error bit | 主测量继续 |
| HMP/PTB timeout | 记录 timeout | 主测量继续 |
| GNSS 数据丢失 | sync_valid 超时清零 | local tick 继续 |
| GNSS 1PPS 丢失 | TIME error/event | 不修改历史 tick |
| ADC capture overflow | error + drop_count | 对应通道数据不可信；可继续另一通道 |
| DAC device fail | 对应 WMS 停止 | 对应测量链 critical fault |
| DILA overflow | 标记并报警 | RAW 可继续，DILA 数据不可信 |
| USB backpressure | FIFO absorb | 超预算后显式 drop/error |
| bad host CMD CRC | 丢帧+计数 | 不执行任何寄存器写 |
| motor command out of range | reject | 不输出脉冲 |

---

# 18. 当前必须保留为“待硬件/固件确认”的项目

以下内容不能凭空假定，联调前必须闭环：

1. **FX3 firmware 当前是否已有固定 GPIF CTL mapping**。若已有，优先与本指南 6.2 对比并统一。
2. **FX3 VID/PID、endpoint address** 是否已经由现有 firmware 固定；本指南建议 0x02/0x86。
3. ADC3660 在本板上的**具体输出 lane mode / bit packing**，需结合 ADC 寄存器初始化和原理图最终确认。
4. AD4630 实际采用的串行输出 lane 配置与目标采样率。
5. 两路 WMS 最终最高正弦频率与期望每周期 DAC 点数，以判断 AD5791 + 板上约 257 kHz LPF 是否完全满足；若不足，启用 AD3552R 预留路径。
6. RD105 TTL 电平是否与 Bank88 3.3 V 直接兼容；不兼容时使用外置 level shifter。
7. TFA1500-L 设备侧连接器 pinout 与高/低频物理输出脚，FPGA 侧分配已冻结，但线束必须按设备实物说明确认。
8. EPSILON2 使用哪个 COMM 口输出 FDILink，以及该口实际配置是否为 921600/Main 或 NAV。

这些事项不会改变内部统一协议和寄存器架构，只影响 PHY/driver 层，因此可以并行开发其余模块。

---

# 19. V1.1 推荐的最小可运行闭环

为了尽快让上下位机打通，第一版系统不必等待所有 sensor 完成。建议按以下最小闭环验证：

```text
Qt
 -> USB Bulk OUT CMD
 -> FX3
 -> GPIF
 -> cmd_decoder
 -> SYSTEM/WMS0 register
 -> RESP
 -> FX3
 -> Qt

同时：
WMS0 synthetic/debug source
 -> msg_stream / bulk_stream
 -> per-source FIFO / stream_arbiter
 -> packetizer
 -> FX3
 -> Qt parser
```

该闭环成功后再逐一接入 ADC/DILA/sensor。这样 USB、协议、寄存器、数据流的系统骨架先冻结，设备模块只需按规范插入。

---

# 20. 开发完成判据

当以下条件全部满足，可以认为 V1.1 下位机具备完整开发闭环：

- 两路 WMS 独立可配、可启动/停止；
- 两路 DAC 可靠输出；
- 两路 ADC 独立采集并统一输出；
- 每 WMS 周期 raw ADC 仅一个 timestamp + cycle_id；
- DILA 输出 1f/2f 且参数可通过寄存器配置；
- PTB/HMP/EPS/BMP/SHT/TFA/RD105/stepper 全部接入标准接口；
- GNSS 1PPS 与 local tick 有同步 event；
- VLP1 CMD/RESP/DATA/EVENT/STATUS 全部可解析；
- Qt 可读写任意合法寄存器；
- Qt 可按 source 独立开关数据流；
- CRC、sequence、error、drop_count 可诊断；
- USB backpressure 和 sensor offline 不导致系统无提示死锁；
- Vivado 综合、实现、CDC、timing 达到项目验收要求。

---

# Appendix A：推荐顶层骨架

```verilog
module vapor_lidar_top (
    input  wire        CLK_SYSCLK_200M_P,
    input  wire        CLK_SYSCLK_200M_N,

    // GPIF
    inout  wire [31:0] FPGA_GPIF_DQ,
    inout  wire [12:0] FPGA_GPIF_CTL,
    input  wire        FPGA_GPIF_INTN,
    output wire        FPGA_GPIF_PCLK,
    output wire        CYUSB_RSTN,

    // Serial PHY
    output wire FPGA_RS232A_TXD,
    input  wire FPGA_RS232A_RXD,
    output wire FPGA_RS422_TXD_L,
    input  wire FPGA_RS422_RXD_L,
    output wire FPGA_RS485_TXD_L,
    input  wire FPGA_RS485_RXD_L,
    output wire FPGA_RS485_DERE_L,
    output wire FPGA_UART_TXD_L,
    input  wire FPGA_UART_RXD_L,
    output wire FPGA_UART_EN_L,
    input  wire SYNC_IN,

    // GPIO
    inout wire [12:1] GPIO_BANK88_LP,
    inout wire [12:1] GPIO_BANK88_LN,

    // AD5791 x2
    output wire DAC_AD5791_0_SCLK,
    output wire DAC_AD5791_0_RSTN,
    output wire DAC_AD5791_0_SYNCN,
    output wire DAC_AD5791_0_SDIN,
    input  wire DAC_AD5791_0_SDO,
    output wire DAC_AD5791_0_CLRN,
    output wire DAC_AD5791_0_LDACN,

    output wire DAC_AD5791_1_SCLK,
    output wire DAC_AD5791_1_RSTN,
    output wire DAC_AD5791_1_SYNCN,
    output wire DAC_AD5791_1_SDIN,
    input  wire DAC_AD5791_1_SDO,
    output wire DAC_AD5791_1_CLRN,
    output wire DAC_AD5791_1_LDACN,

    // ADCs ... keep original schematic net names
    ...
);
```

---

# Appendix B：推荐模块寄存器 RTL 写法

```verilog
always @(posedge sys_clk) begin
    if (!rst_sys_n) begin
        shadow_freq <= DEFAULT_FREQ;
        active_freq <= DEFAULT_FREQ;
        cfg_pending <= 1'b0;
    end else begin
        if (cfg_valid && cfg_ready && cfg_write && cfg_addr == REG_FREQ)
            shadow_freq <= cfg_wdata;

        if (cfg_valid && cfg_ready && cfg_write &&
            cfg_addr == REG_CONTROL && cfg_wdata[2])
            cfg_pending <= 1'b1;

        if (cfg_pending && safe_commit_boundary) begin
            active_freq <= shadow_freq;
            cfg_pending <= 1'b0;
        end
    end
end
```

---

# Appendix C：协议 parser 必测案例

1. 一个 CMD 恰好一个 USB transfer；
2. 一个 CMD 被拆成 3 次 USB read；
3. 3 个 CMD 拼在一次 USB transfer；
4. magic 前有随机垃圾字节；
5. payload_len 错；
6. CRC 错；
7. 未知 source；
8. 未知 msg；
9. WRITE 到 RO register；
10. 最大 4096 B CMD；
11. DATA frame 大于 1024 B 并跨多个 USB packet；
12. 在连续 DATA 中插入 RESP/EVENT；
13. PC 暂停读取 100 ms 后恢复；
14. sequence wrap；
15. FX3 reset 后重新同步 magic。

---

# Appendix D：资料依据

本指南基于项目包中的：

- `Docs/下位机需求分析.md`；
- `Docs/电路板资料/LIDAR_WATER_VAPOR_DETECTION_SCH_0908(1).pdf`；
- `Docs/电路板资料/XCKU11P-2FFVA1156I(1).ucf`；
- PTB210 数字气压计说明书；
- HMP Series Quick Guide；
- BMP390 资料；
- SHT45/SHT4x 资料；
- TFA1500-L 测距雷达资料；
- RD105 通讯协议 v1.3.0；
- DM422 驱动器说明书；
- EPSILON/EPSILON2 使用手册；
- 已形成的 `FPGA下位机详细架构与接口分配方案.md`。

