# FPGA 下位机公共接口冻结规范 V1.0

> 状态：**FROZEN / 成员开工基线**  
> 日期：2026-09-14  
> FPGA：Xilinx XCKU11P-2FFVA1156I  
> 工具：Vivado  
> RTL：Verilog-2001  
> 适用人员：成员1（双 ADC + DILA）、成员2（WMS + 双 DAC）、成员3（UART + 全部非 ADC 传感器）、项目负责人  
> 上位规范：`FPGA下位机Verilog开发指南_V1.0.md`、`三成员任务书_V1.2`  
> 本文目的：冻结所有成员开工前必须统一的接口契约。除项目负责人发布新版本外，成员不得改变本文定义。

---

## 1. 统一时钟与复位

### 1.1 系统时钟

- 主控制/配置/统一数据平面时钟：`sys_clk = 100 MHz`。
- 周期：10 ns。
- ADC 的 DCLK/FCLK/CNV 等器件专用时钟允许存在于 ADC PHY 内部，但进入统一数据平面前必须完成 CDC。
- 成员模块不得自行生成第二套“系统时钟”。需要局部低速节拍时使用 clock-enable，不建议逻辑分频生成新时钟。

### 1.2 系统复位

统一端口：

```verilog
input wire sys_clk;
input wire rst_sys_n;
```

规则：

1. `rst_sys_n` 低有效；
2. 成员收到的 `rst_sys_n` 视为已经在 `sys_clk` 域同步释放；
3. 普通 `sys_clk` 域模块使用同步复位写法；
4. ADC 专用 I/O 时钟域的复位同步由对应 ADC 接口模块自行完成；
5. 成员不得改变复位极性。

---

## 2. 统一时间基准

### 2.1 时间格式

```verilog
input wire [63:0] timestamp_now;
input wire        time_sync_valid;
input wire [31:0] time_sync_seq;
```

- `timestamp_now`：64 bit 无符号 tick；1 tick = 10 ns。
- 上电/复位后从 0 开始单调递增。
- 64 bit 回绕时间远大于项目寿命，业务逻辑不得自行处理短周期回绕。
- `time_sync_valid=0` 时仍允许使用本地 tick，只是在上送状态中标记“未外部同步”。
- `time_sync_seq` 每次外部时间同步事件递增，用于诊断；成员模块不得用它替代时间戳。

### 2.2 时间戳采样规则

- 低速传感器：一条完整有效测量记录形成时锁存一次 `timestamp_now`。
- WMS/RAW ADC：每个 `scan_start` 锁存一次周期时间戳；ADC 原始样点不逐点附带 64 bit 时间戳。
- DILA：输出块的 `timestamp` 采用该块对应 WMS 周期的周期时间戳。

---

## 3. `cfg_bus`：统一寄存器总线

所有可配置模块必须使用以下接口：

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

### 3.1 握手语义

- 所有信号位于 `sys_clk` 域。
- Master 拉高 `cfg_valid` 后，必须保持 `cfg_write/cfg_addr/cfg_wdata/cfg_wstrb` 稳定，直到 `cfg_ready=1`。
- `cfg_valid && cfg_ready` 的上升沿完成且仅完成一次访问。
- `cfg_error` 只在 `cfg_ready=1` 的同一拍有效。
- V1.0 只允许一个 outstanding transaction。
- Slave 只响应自身地址页；地址不属于自身时保持 `cfg_ready=0`，由项目级 crossbar 负责路由。
- 地址属于自身但 offset 非法、写只读寄存器、参数越界时：`cfg_ready=1, cfg_error=1`。
- 简单寄存器推荐 1 cycle 响应；跨时钟访问允许等待。

### 3.2 字节写使能

`cfg_wstrb[0]` 对应 `cfg_wdata[7:0]`，依次类推。模块必须正确支持 byte strobe，或对不支持的部分写返回 `cfg_error=1`；不得静默错误写入。

### 3.3 shadow + commit

以下实时参数采用 `shadow -> commit -> active`：WMS、ADC 采样配置、DILA、需要原子更新的 DAC/传感器配置。

统一要求：

1. Host 写 shadow 寄存器不立即影响实时链路；
2. 写 `CONTROL.bit2=1` 产生 commit 请求；
3. `STATUS.bit2=cfg_pending` 置 1；
4. 模块在安全边界原子复制到 active；
5. 完成后清 `cfg_pending`；
6. 参数非法则不进入 active，并置 `ERROR.CONFIG_RANGE`。

WMS/DILA 的默认安全边界为下一个 `scan_start`。

---

## 4. `sample_stream`：统一 ADC 样点流

```verilog
output wire        s_valid;
input  wire        s_ready;
output wire [31:0] s_data;
output wire [7:0]  s_flags;
```

### 4.1 握手

- `s_valid && s_ready`：完成一个样点传输。
- `s_valid=1 && s_ready=0`：producer 必须保持 `s_data/s_flags` 不变。
- `s_ready` **不得反向停止物理 ADC**。

### 4.2 样点格式

- 有符号 ADC：二补码符号扩展到 32 bit。
- 无符号 ADC：零扩展到 32 bit。
- `s_flags[0]`：overrange。
- `s_flags[1]`：ADC/device error。
- `s_flags[7:2]`：V1.0 保留，输出 0。

### 4.3 ADC 不可背压规则

正式链路必须满足：

```text
ADC pins
  -> device PHY/capture
  -> capture FIFO
  -> fanout / downstream FIFO
       -> RAW path
       -> DILA path
```

capture FIFO 满时允许丢样，但必须：

- 置 `ERROR.FIFO_OVERFLOW`；
- 累加 `DROP_COUNT`；
- 不允许静默覆盖旧数据；
- 不允许通过 `s_ready=0` 停止 ADC 器件采样。

---

## 5. `msg_stream`：统一记录/消息流

所有 DILA 结果和非 ADC 传感器记录统一输出：

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

1. `m_valid && m_ready` 完成一个 32-bit beat；
2. `m_valid=1 && m_ready=0` 时，所有输出必须保持不变；
3. `m_sof` 只在消息第一拍置 1；
4. `m_last` 只在消息最后一拍置 1；
5. 非最后一拍 `m_keep=4'b1111`；最后一拍按有效字节置位；
6. `m_source_id/m_msg_id/m_timestamp/m_cycle_id/m_flags` 至少在 `m_sof && m_valid` 时有效，推荐整个消息保持不变；
7. `cycle_id` 与 WMS 无关的传感器填 `32'hFFFF_FFFF`；
8. 多字节字段进入消息 payload 后统一 little-endian。

---

## 6. WMS -> DILA 冻结接口

这是成员2和成员1之间唯一必须直接耦合的实时接口。每个 WMS 通道提供：

```verilog
output wire        scan_start;
output wire [31:0] cycle_id;
output wire [31:0] sine_phase;
output wire        phase_valid;
output wire        wms_running;
```

全部位于 `sys_clk` 域。

### 6.1 `scan_start`

- 新锯齿扫描周期开始时产生；
- 恰好 1 个 `sys_clk` 周期；
- 同一拍 `cycle_id` 已更新为新周期 ID；
- WMS 停止期间不得产生伪 `scan_start`。

### 6.2 `cycle_id`

- 32 bit 无符号；
- WMS 从 disabled -> enabled 后，第一个有效周期可从 0 开始；
- 每个有效 `scan_start` 加 1；
- 只有 WMS soft reset/global reset 才允许重置；
- 项目负责人、DILA、RAW cycle framer 均使用这一 ID 对齐数据。

### 6.3 `sine_phase`

冻结为 U0.32“turn phase”：

```text
0x00000000 = 0
0x40000000 = π/2
0x80000000 = π
0xC0000000 = 3π/2
2^32       = 2π（自然回绕为 0）
```

数学关系：`phase_rad = sine_phase / 2^32 * 2π`。

要求：

- `wms_running=1 && phase_valid=1` 时，`sine_phase` 是当前 1f 调制参考相位；
- phase accumulator 必须与实际生成 DAC 正弦使用同一参考状态，不允许另起一个近似 DDS；
- 相位自然模 `2^32` 回绕；
- DILA 2f 参考由成员1从 `2*sine_phase` 生成，可叠加 DILA 自身相位修正寄存器。

### 6.4 `phase_valid`

- `phase_valid=1` 表示 `sine_phase` 可作为锁相参考；
- 正常运行时建议持续为 1，而不是只做单拍 strobe；
- WMS disabled、复位、配置尚未生效或参考无效时必须为 0。

### 6.5 ADC/DILA 对相位的使用约束

为了避免 FIFO 延迟导致相位错配，成员1在 phase-lock 模式下应在**ADC 样点被正式接收/捕获到统一处理域的事件处**同步锁存当拍 WMS `sine_phase`，再与样点一起进入可能产生可变延迟的内部缓冲；不得在若干拍以后仅用“当前相位”去混频旧样点。

---

## 7. `source_id` 冻结表

| ID | 数据源 |
|---:|---|
| `0x0001` | SYSTEM |
| `0x0002` | TIME |
| `0x0010` | WMS0 原位 |
| `0x0011` | WMS1 遥测 |
| `0x0020` | ADC0 / AD4630 |
| `0x0021` | ADC1 / ADC3660 |
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
| `0x8000-0xFFFE` | 后续扩展/实验模块 |
| `0xFFFF` | broadcast / no-specific-source command |

已发布 ID 不得改变含义。

---

## 8. `msg_id` 冻结表

| ID | 含义 |
|---:|---|
| `0x1000` | ADC_RAW_CYCLE |
| `0x1001` | DILA_BLOCK |
| `0x1100` | SENSOR_TLV_RECORD |
| `0x1200` | GNSS_FDILINK_RAW |
| `0x1201` | TIME_SYNC_EVENT |
| `0x1300` | MOTOR_STATUS |
| `0x1400` | SYSTEM_STATUS |
| `0x1401` | MODULE_STATUS |
| `0x1402` | ERROR_EVENT |
| `0x7F00-0x7FFF` | debug data |

---

## 9. 通用模块首部寄存器

每个模块占 0x100 byte 页。页首统一：

| Offset | 名称 | 属性 | 语义 |
|---:|---|---|---|
| `+0x00` | ID_VERSION | RO | `[31:16]=module_id, [15:8]=major, [7:0]=minor` |
| `+0x04` | CONTROL | RW/W1P | bit0 enable；bit1 soft_reset；bit2 commit；bit3 clear_fifo |
| `+0x08` | STATUS | RO | bit0 enabled；1 ready；2 cfg_pending；3 busy；4 online；5 fifo_almost_full；6 overflow；7 error；8 time_sync_valid |
| `+0x0C` | ERROR | RO/W1C | 统一错误位 + 模块专用位 |

统一 ERROR bit：

| Bit | 含义 |
|---:|---|
| 0 | TIMEOUT |
| 1 | PROTOCOL_OR_CRC |
| 2 | FIFO_OVERFLOW |
| 3 | DEVICE_NOT_READY |
| 4 | CONFIG_RANGE |
| 5 | CDC_OR_INTERNAL |
| 6 | DEVICE_REPORTED_ERROR |
| 7 | DATA_FORMAT |
| 31:8 | 模块专用 |

---

## 10. 成员开发边界

### 成员1：双 ADC + DILA

必须消费：`sys_clk/rst_sys_n`、`cfg_bus`、`timestamp_now`、成员2 WMS reference。  
必须输出：ADC `sample_stream`、DILA `msg_stream`。  
不得实现：WMS、DAC、USB packetizer、项目级 crossbar。

### 成员2：WMS + 双 DAC

必须消费：`sys_clk/rst_sys_n`、`cfg_bus`。  
必须输出：冻结 WMS reference + AD5791 物理链。  
不得实现：DILA、ADC、传感器、USB。

### 成员3：UART + 全部非 ADC 传感器

必须消费：`sys_clk/rst_sys_n`、`cfg_bus`、`timestamp_now`。  
必须输出：标准 `msg_stream`。  
负责 UART/RS232/RS422/RS485/Modbus/I²C 及全部传感器原生协议。  
不得实现：USB packetizer、项目级 crossbar。

---

## 11. 版本与变更规则

- 本文版本为 `COMMON_INTERFACE_SPEC V1.0`。
- 不改变现有语义的新增 `source_id/msg_id/register offset` 可升级 minor。
- 改变端口、位宽、握手、既有 ID 含义、寄存器既有语义属于 breaking change，必须升级 major。
- 成员若认为接口存在问题，只能提出变更请求；在负责人发布新版前不得私自修改。
