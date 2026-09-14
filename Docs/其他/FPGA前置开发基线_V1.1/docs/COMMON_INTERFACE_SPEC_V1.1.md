# FPGA 下位机公共接口冻结规范 V1.1

> 状态：**FROZEN / 成员开工基线**  
> 日期：2026-09-14  
> FPGA：Xilinx XCKU11P-2FFVA1156I  
> 工具：Vivado  
> RTL：Verilog-2001  
> 适用人员：成员1（双 ADC + DILA）、成员2（WMS + 双 DAC）、成员3（UART + 全部非 ADC 传感器）、项目负责人  
> 本版本取代 `COMMON_INTERFACE_SPEC_V1.0`。V1.1 的核心变化是：**低速消息与高速块数据分流、每源独立 FIFO、消息级仲裁、DILA 分片传输、防 starvation 仲裁机制**。

---

## 1. 数据平面总原则

系统内部正式区分三种数据接口：

| 接口 | 用途 | 典型数据源 | 是否进入系统总仲裁 |
|---|---|---|---|
| `sample_stream` | ADC 样点级内部流 | AD4630、ADC3660 | 否，先进入 RAW/DILA 处理 |
| `msg_stream` | 低速、短记录/事件 | PTB、HMP、EPSILON2、BMP390、SHT45、TFA、RD105、状态/事件 | 是 |
| `bulk_stream` | 高速、大块、可分片数据 | DILA 曲线、RAW ADC 周期数据 | 是 |

正式数据路径：

```text
ADC pins
  -> ADC capture FIFO
  -> sample_stream
       ├─> DILA -> fragmenter -> DILA bulk FIFO -> bulk_stream
       └─> RAW cycle framer -> RAW bulk FIFO -> bulk_stream

Sensor driver -> per-source msg FIFO -> msg_stream

system/event/response FIFO ----┐
sensor_hub output -------------┼-> stream_arbiter -> selected frame stream -> packetizer -> GPIF -> FX3 -> USB3.1
DILA0/1 bulk FIFO -------------┤
RAW ADC0/1 bulk FIFO ----------┘
```

**禁止**多个生产者直接电气并联到同一 `valid/data` 总线上。每个独立生产者必须拥有自己的输出 FIFO 或等效完整帧缓冲。

---

## 2. 统一时钟与复位

### 2.1 系统时钟

- 主控制/配置/统一数据平面：`sys_clk = 100 MHz`。
- 周期：10 ns。
- ADC 的 DCLK/FCLK/CNV 等专用时钟允许存在于 PHY 内部，但进入统一数据平面前必须完成 CDC。
- 普通控制逻辑用 clock-enable，不建议逻辑分频生成新的系统级时钟。

统一端口：

```verilog
input wire sys_clk;
input wire rst_sys_n;
```

`rst_sys_n` 低有效、同步释放。成员不得改变极性。

---

## 3. 统一时间基准

```verilog
input wire [63:0] timestamp_now;
input wire        time_sync_valid;
input wire [31:0] time_sync_seq;
```

- `timestamp_now`：64-bit tick；1 tick = 10 ns。
- 低速传感器：完整有效测量记录形成时锁存时间戳。
- WMS/RAW ADC：每个 `scan_start` 锁存一次周期时间戳。
- DILA：同一 WMS 周期内的所有 fragment 使用同一个周期时间戳和 `cycle_id`。
- `time_sync_valid=0` 时仍允许上传本地时间，但必须通过状态/flags 标识尚未外部同步。

---

## 4. `cfg_bus`：统一寄存器总线

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

规则：

1. `cfg_valid && cfg_ready` 完成一次访问；
2. 等待期间 master 保持请求字段不变；
3. `cfg_error` 仅与 `cfg_ready` 同拍有效；
4. 单 outstanding；
5. 实时参数采用 `shadow -> commit -> safe boundary -> active`；
6. WMS/DILA 默认安全边界为下一个 `scan_start`。

---

## 5. `sample_stream`：ADC 样点级内部数据流

```verilog
output wire        s_valid;
input  wire        s_ready;
output wire [31:0] s_data;
output wire [7:0]  s_flags;
```

### 5.1 握手

- `s_valid && s_ready`：一个样点传输完成；
- `s_valid=1 && s_ready=0`：`s_data/s_flags` 必须保持；
- `s_ready` **不得反向停止物理 ADC**。

### 5.2 ADC 不可背压

```text
ADC pins
  -> PHY / capture
  -> capture FIFO
  -> sample_stream
```

FIFO 满必须置 overflow、累计 drop count；不得静默覆盖。

---

## 6. `msg_stream`：低速消息/记录流

`msg_stream` 只用于低速、短记录、状态和事件，不再承载正式 DILA 曲线或 RAW ADC 大块数据。

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

规则：

1. 一个 beat = 32 bit；
2. `m_sof` 仅第一拍有效；`m_last` 仅最后一拍有效；
3. 非最后一拍 `m_keep=4'b1111`；
4. backpressure 时全部输出保持；
5. 一条消息从 SOF 到 LAST 期间，`source_id/msg_id/timestamp/cycle_id/flags` **必须保持不变**；
6. 与 WMS 无关的传感器使用 `cycle_id=32'hFFFF_FFFF`；
7. payload 多字节字段 little-endian；
8. V1.1 推荐单条低速消息 payload ≤ 1024 B；超过该值应评估改为 `bulk_stream`。

### 6.1 每源 FIFO 要求

PTB/HMP/EPSILON2/BMP390/SHT45/TFA/RD105 等每个独立生产者都必须先进入独立 FIFO，再交给 `sensor_hub`。

- 默认建议每源 FIFO 有效容量 ≥ 1 KiB；
- 至少必须容纳 1 条最大合法标准记录并留出余量；
- FIFO full 时不能覆盖旧记录；必须置错误和 drop count；
- 多个传感器可以同拍产生消息，不会因为共享总线而直接冲突。

---

## 7. `bulk_stream`：高速大块/分片数据流

用于 DILA 曲线、RAW ADC 周期数据等大吞吐量数据。

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

电气/握手规则与 `msg_stream` 一致，但语义不同：

- 一个 `b_sof ... b_last` 表示一个**独立可仲裁 fragment**；
- 同一逻辑 WMS 周期可对应多个 fragment；
- arbiter 只能在 `b_last` 后切换源；
- V1.1 `BULK_FRAGMENT_MAX_BYTES = 8192`；
- DILA 默认每 fragment 最多 256 个输出点；
- RAW ADC 的 fragment 大小由项目负责人 framer 决定，但不得超过 8192 B payload 上限。

### 7.1 Bulk FIFO

- DILA0、DILA1 必须各有独立 bulk FIFO / ping-pong buffer；
- 每个 DILA 通道至少能缓冲 **2 个完整最大 fragment**；
- RAW ADC0/1 也必须拥有彼此独立的深缓存；
- bulk FIFO full 必须显式报告，不得静默丢弃。

---

## 8. DILA 曲线与 fragment 格式

### 8.1 基本语义

一个 WMS 周期产生两条谐波曲线，例如：

```text
H1[0], H1[1], ... H1[N-1]
H2[0], H2[1], ... H2[N-1]
```

逻辑上它们属于同一个 `cycle_id`。如果曲线较长，则拆为多个 `DILA_BLOCK` fragment 依次上传。

### 8.2 `DILA_BLOCK` V2 payload

`msg_id = 0x1001`，`schema_version = 2`。

| Offset | 类型 | 字段 | 含义 |
|---:|---|---|---|
| 0 | u16 | schema_version | 固定 2 |
| 2 | u16 | format | 数据点格式 |
| 4 | u32 | output_rate_hz | 曲线点输出率 |
| 8 | u32 | total_point_count | 整个 WMS 周期总点数 N |
| 12 | u16 | fragment_index | 0-based |
| 14 | u16 | fragment_count | 本周期 fragment 总数 |
| 16 | u32 | first_point_index | 本 fragment 首点索引 |
| 20 | u32 | fragment_point_count | 本 fragment 点数 |
| 24 | u32 | bytes_per_point | 每点字节数 |
| 28 | u32 | reserved | 0 |
| 32 | records | payload | 连续点数据 |

`b_timestamp` 和 `b_cycle_id` 在同一周期所有 fragment 中保持相同。

### 8.3 format 定义

- `format=0`：**默认两条谐波曲线**，每点 8 B：`int32 H1, int32 H2`；
- `format=1`：I/Q 原始解调量，每点 16 B：`int32 I1,Q1,I2,Q2`；
- `format=2`：I/Q + magnitude，每点 24 B：`int32 I1,Q1,I2,Q2; uint32 MAG1,MAG2`。

V1.1 默认正式上送建议使用 `format=0`；保留 1/2 用于调试、算法验证和后续扩展。

### 8.4 Fragment 规则

- 默认 `fragment_point_limit = 256`；
- 最后一个 fragment 可以少于 256 点；
- `fragment_count = ceil(total_point_count / fragment_point_limit)`；
- 上位机按 `source_id + cycle_id + fragment_index` 重组完整曲线；
- fragment 不得在内部被其他源 beat 级穿插；只有 fragment 完成后才允许切换源。

---

## 9. RAW ADC bulk 数据

RAW ADC 周期数据同样走 `bulk_stream`，由项目负责人 `adc_cycle_framer` 完成周期组织和必要分片。

保留 `msg_id = 0x1000 ADC_RAW_CYCLE`。若一周期数据超过 8192 B，必须拆分，payload header 中包含 fragment index/count/first sample/sample count；具体 schema 由项目负责人在 RAW framer 开发前冻结，不影响成员1的 ADC `sample_stream` 接口。

---

## 10. 多源并发与两级仲裁

### 10.1 第一级：`sensor_hub`

```text
PTB FIFO ----┐
HMP FIFO ----┤
EPS FIFO ----┤
BMP FIFO ----┤
SHT FIFO ----┤-> sensor_hub -> one sensor msg_stream
TFA FIFO ----┤
RD FIFO -----┘
```

规则：

- message-locked round-robin；
- 一旦选中某源，从 `m_sof` 到 `m_last` 完整发送后才能换源；
- 禁止 beat-level interleave；
- 某源空则跳过；
- 同时到达的数据保存在各自 FIFO 中等待服务。

### 10.2 第二级：`stream_arbiter`

系统级输入分为 4 类：

| 优先级 | 类别 | 典型来源 |
|---|---|---|
| P0 | 系统控制/关键事件 | RESP、ERROR、critical EVENT |
| P1 | 时间/导航/重要状态 | TIME_SYNC、EPSILON2、关键 STATUS |
| P2 | 普通低速消息 | sensor_hub、一般 STATUS |
| P3 | Bulk | DILA0/1、RAW ADC0/1 |

仲裁规则：

1. 同级采用 round-robin；
2. 一旦选择一条 message 或一个 bulk fragment，必须锁定到 `last`；
3. 默认允许高优先级先服务；
4. **防 starvation：若低优先级持续 pending，高优先级连续完成 4 个 frame/fragment 后，必须给至少一个较低 pending 类别一次服务机会**；
5. Bulk 的仲裁量子固定为“一个 fragment”，不是完整 WMS 周期；
6. 不允许不同源 beat 级交错。

默认参数：

```text
ARB_MODE = PRIORITY_RR_WITH_BURST_CAP
MAX_HIGH_BURST = 4
BULK_QUANTUM = 1 fragment
```

这些参数由项目负责人实现，并在 `STREAM/BUFFER` 寄存器页可查询/配置。

---

## 11. Packetizer 输入约束

`stream_arbiter` 输出一个已经选择好的统一 frame stream 给 packetizer。packetizer 不负责多源冲突解决，只负责：

- 锁存 SOF metadata；
- 生成 VLP header；
- payload 长度统计；
- CRC32；
- GPIF/USB 对齐。

因此：**冲突必须在 packetizer 之前解决。**

---

## 12. WMS -> DILA 冻结接口

每个 WMS 通道提供：

```verilog
output wire        scan_start;
output wire [31:0] cycle_id;
output wire [31:0] sine_phase;
output wire        phase_valid;
output wire        wms_running;
```

`sine_phase` 为 U0.32 turn phase：

```text
0x00000000 = 0
0x40000000 = π/2
0x80000000 = π
0xC0000000 = 3π/2
2^32       = 2π（自然回绕）
```

成员1必须在样点进入统一处理域时把样点与当拍 phase 对齐后共同经过可变延迟缓存，不能用未来“当前相位”处理旧样点。

---

## 13. `source_id` 冻结表

| ID | 数据源 |
|---:|---|
| `0x0001` | SYSTEM |
| `0x0002` | TIME |
| `0x0010` | WMS0 |
| `0x0011` | WMS1 |
| `0x0020` | ADC0 / AD4630 |
| `0x0021` | ADC1 / ADC3660 |
| `0x0030` | DILA0 |
| `0x0031` | DILA1 |
| `0x0040` | PTB210 |
| `0x0041` | HMP |
| `0x0042` | EPSILON2 |
| `0x0043` | BMP390 |
| `0x0044` | SHT45 |
| `0x0045` | TFA1500-L |
| `0x0046` | RD105 |
| `0x0047` | STEPPER |
| `0x0050` | DIAGNOSTICS |
| `0xFFFF` | broadcast / no-specific-source command |

---

## 14. `msg_id` 冻结表

| ID | 含义 | 通路 |
|---:|---|---|
| `0x1000` | ADC_RAW_CYCLE / fragment | bulk |
| `0x1001` | DILA_BLOCK V2 / fragment | bulk |
| `0x1100` | SENSOR_TLV_RECORD | msg |
| `0x1200` | GNSS_FDILINK_RAW | msg |
| `0x1201` | TIME_SYNC_EVENT | msg |
| `0x1300` | MOTOR_STATUS | msg |
| `0x1400` | SYSTEM_STATUS | msg |
| `0x1401` | MODULE_STATUS | msg |
| `0x1402` | ERROR_EVENT | msg |

---

## 15. 成员开发边界 V1.1

### 成员1：双 ADC + DILA

必须输出：

- ADC：`sample_stream`；
- DILA0/1：**独立 `bulk_stream`**；
- DILA 每通道独立 bulk FIFO / fragment buffer；
- DILA 默认按 256 点分片。

不再把 DILA 正式数据输出定义为 `msg_stream`。

### 成员2：WMS + 双 DAC

接口不变：提供 WMS phase/cycle reference 和 DAC 物理链。

### 成员3：UART + 全部非 ADC 传感器

每个传感器 driver 输出独立 `msg_stream`，并具备独立输出 FIFO。成员3不实现项目级 `sensor_hub/stream_arbiter`。

### 项目负责人

负责：

- `sensor_hub`；
- 系统 `stream_arbiter`；
- RAW ADC cycle framer/bulk FIFO；
- packetizer；
- USB/FX3；
- 防 starvation 与整体缓存策略。

---

## 16. 版本与变更规则

- 本文取代 V1.0；成员开工以 V1.1 为唯一数据流接口基线。
- V1.1 的 `bulk_stream`、DILA fragment schema、仲裁规则属于冻结内容。
- 改变已有端口/位宽/ID/fragment header/仲裁基本语义属于 breaking change，必须发布新版本。
