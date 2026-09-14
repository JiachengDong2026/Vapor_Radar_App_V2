# 成员3 FPGA 开发任务书——公共 UART + 全部非ADC传感器接口与协议

> 文档版本：V1.3  
> 开发环境：Xilinx Vivado  
> RTL：Verilog-2001  
> FPGA：Xilinx XCKU11P-2FFVA1156I  
> 任务定位：统一负责公共串口基础模块，以及 PTB210、HMP、EPSILON2、BMP390、SHT45、TFA1500-L、RD105 全部非ADC传感器的 FPGA 接口、协议解析和标准消息输出。

---

# 1. 最终任务范围

## 1.1 公共基础模块

必须交付：

1. `uart_rx.v`；
2. `uart_tx.v`；
3. `crc16_modbus.v`；
4. `modbus_rtu_master.v`；
5. `rs485_halfduplex_ctrl.v`；
6. `i2c_master.v`。

## 1.2 设备 driver

7. `ptb210_rs232.v`；
8. `hmp_modbus_rs485.v`；
9. `epsilon_rs422.v`；
10. `bmp390_driver.v`；
11. `sht45_driver.v`；
12. `tfa1500_uart.v`；
13. `rd105_uart.v`。

你还负责这些模块的：

- testbench；
- 协议 vectors；
- 外设 model；
- XDC fragment；
- 寄存器实现；
- 每个设备独立 `msg_stream` 输出 + 独立输出 FIFO；
- 错误计数器；
- 文档和 Vivado 脚本。

---

# 2. 不属于你的任务

- ADC；
- DILA；
- WMS；
- DAC；
- 项目级 `time_sync_core`；
- 项目级 `sensor_hub`；
- stepper；
- USB；
- packetizer；
- 项目总顶层/XDC。

EPSILON2 的 `SYNC/1PPS` 外部脉冲最终进入项目负责人的 `time_sync_core`；你只负责：

- 串口/FDILink；
- GNSS 时间字段最小解析；
- 把可关联的 GNSS time tag/事件信息输出给负责人。

---

# 3. 必须阅读资料

1. `FPGA下位机Verilog开发指南_V1.1.md`；
2. `FPGA下位机详细架构与接口分配方案_V1.1.md`；
3. `Docs/下位机需求分析.md`；
4. 板卡原理图；
5. XCKU11P UCF；
6. PTB210 使用说明/通信手册；
7. HMP Series Quick Guide/Modbus 文档；
8. EPSILON/EPSILON2 使用手册与 FDILink 文档；
9. Bosch BMP390 datasheet；
10. Sensirion SHT45 datasheet；
11. TFA1500-L 通信协议资料；
12. RD105 通信协议 V1.3.0。

若设备手册与实际线束/设备默认配置冲突，应在 `KNOWN_ISSUES.md` 明确，并向负责人提交需要实机确认的最小问题列表，不允许默默假设。

---

# 4. 公共 UART——你负责全项目唯一实现

## 4.1 `uart_rx.v`

冻结接口：

```verilog
module uart_rx #(
    parameter integer SYS_CLK_HZ = 100_000_000
)(
    input  wire        sys_clk,
    input  wire        rst_sys_n,
    input  wire        enable,
    input  wire [31:0] baud_hz,
    input  wire [3:0]  data_bits,
    input  wire [1:0]  parity_mode,    // 0 none, 1 even, 2 odd
    input  wire [1:0]  stop_bits,
    input  wire        rxd,
    output wire        byte_valid,
    input  wire        byte_ready,
    output wire [7:0]  byte_data,
    output wire        byte_start_pulse,
    output wire        framing_error_pulse,
    output wire        parity_error_pulse,
    output wire        busy
);
```

要求：

- 支持 7/8 data bits；
- none/even/odd parity；
- 1/2 stop bits；
- 推荐 16x oversampling；
- start bit 抗毛刺；
- framing/parity error；
- byte valid/ready 背压；
- `byte_start_pulse` 用于传感器帧首时间戳；
- RX 输入异步，必须正确同步/采样。

## 4.2 `uart_tx.v`

```verilog
module uart_tx #(
    parameter integer SYS_CLK_HZ = 100_000_000
)(
    input  wire        sys_clk,
    input  wire        rst_sys_n,
    input  wire        enable,
    input  wire [31:0] baud_hz,
    input  wire [3:0]  data_bits,
    input  wire [1:0]  parity_mode,
    input  wire [1:0]  stop_bits,
    input  wire        byte_valid,
    output wire        byte_ready,
    input  wire [7:0]  byte_data,
    output wire        txd,
    output wire        busy,
    output wire        frame_done_pulse
);
```

`frame_done_pulse` 必须代表最后一个 stop bit 已真正发送完成，不能等同于 TX FIFO 空。

## 4.3 UART 必测格式

至少：

- 8N1；
- 8N2；
- 7E1；
- 8E1；
- 8O1；
- 9600；
- 19200；
- 38400；
- 115200；
- 500000；
- 921600（只要 100 MHz divider 方案允许，应验证误差）。

需给出每种典型 baud 的实际 baud 和 ppm/% error。

---

# 5. 统一传感器 `msg_stream` 与每源独立 FIFO

所有设备 driver 最终输出：

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

- `m_valid && m_ready` 完成一个 32-bit beat；
- backpressure 时所有字段保持；
- 与 WMS 无关的低速传感器固定 `m_cycle_id=32'hFFFF_FFFF`；
- 数据 payload 使用主指南定义的 `SENSOR_TLV_RECORD`；
- driver 内部原始协议不得泄漏到上层。

source_id 固定：

| 设备 | source_id |
|---|---:|
| PTB210 | `0x0040` |
| HMP | `0x0041` |
| EPSILON2 | `0x0042` |
| BMP390 | `0x0043` |
| SHT45 | `0x0044` |
| TFA1500-L | `0x0045` |
| RD105 | `0x0046` |

低速统一 `msg_id=0x1100 SENSOR_TLV_RECORD`；EPSILON raw FDILink 如主指南另有固定 msg_id，应严格使用主指南值。

## 5.1 并发与 FIFO 冻结要求

七个设备必须被视为七个独立 producer：

```text
PTB -> FIFO_PTB -> msg_stream_PTB
HMP -> FIFO_HMP -> msg_stream_HMP
EPS -> FIFO_EPS -> msg_stream_EPS
BMP -> FIFO_BMP -> msg_stream_BMP
SHT -> FIFO_SHT -> msg_stream_SHT
TFA -> FIFO_TFA -> msg_stream_TFA
RD  -> FIFO_RD  -> msg_stream_RD
```

要求：

- 不允许七个 driver 直接共用一套 `m_valid/m_data` 输出；
- 每 source 默认建议有效 FIFO 容量 >=1 KiB，至少容纳一条最大标准记录；
- FIFO full 必须 `DROP_COUNT++` 并置 ERROR；
- 成员3只交付各 source 的独立 stream/FIFO，不实现项目级 `sensor_hub`；
- 项目负责人后续用 message-locked RR 仲裁，即选中某消息后发送到 `m_last` 再换 source；
- 因此多个传感器同拍产生数据不会互相覆盖。


---

# 6. 统一 `cfg_bus`

所有设备 driver 通过：

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

首部：

- `+0x00 ID_VERSION`；
- `+0x04 CONTROL`；
- `+0x08 STATUS`；
- `+0x0C ERROR`。

设备 page：

- PTB `0x6000`；
- HMP `0x6100`；
- EPSILON `0x6200`；
- BMP390 `0x6300`；
- SHT45 `0x6400`；
- TFA `0x6500`；
- RD105 `0x6600`。

---

# 7. `crc16_modbus.v`

要求：

- poly reflected `0xA001`；
- init `0xFFFF`；
- byte-wise update；
- wire order low byte first；
- 至少 10 个 known vectors；
- 连续两帧 clear/restart 测试。

建议接口：

```verilog
input  wire        sys_clk;
input  wire        rst_sys_n;
input  wire        clear;
input  wire        data_valid;
input  wire [7:0]  data_byte;
output wire [15:0] crc_value;
```

---

# 8. `modbus_rtu_master.v`

## 必须支持

- 0x03 read holding registers；
- 0x10 write multiple registers；
- 可选 0x06；
- address/function/length/CRC 校验；
- exception；
- timeout；
- 3.5 character gap，按 baud/data/parity/stop 动态计算。

与 UART 之间只使用 byte stream，不绑定任何具体 sensor。

建议 command 接口：

```verilog
input  wire        cmd_valid;
output wire        cmd_ready;
input  wire [7:0]  cmd_slave_addr;
input  wire [7:0]  cmd_function;
input  wire [15:0] cmd_reg_addr;
input  wire [15:0] cmd_reg_count;
input  wire [31:0] cmd_write_data;
input  wire [31:0] cmd_baud_hz;

output wire        resp_valid;
input  wire        resp_ready;
output wire [7:0]  resp_status;
output wire [15:0] resp_word_count;
output wire [31:0] resp_data0;
output wire [31:0] resp_data1;
```

---

# 9. `rs485_halfduplex_ctrl.v`

用于 HMP 板载 RS485 PHY。

状态至少：

```text
RX_IDLE
 -> TX_ENABLE_GUARD
 -> TX_ACTIVE
 -> TX_DRAIN
 -> TURNAROUND
 -> RX_IDLE
```

要求：

- DE 在 start bit 前稳定；
- 最后 stop bit 完成后再撤 DE；
- turnaround 按 baud time；
- 与 `uart_tx.frame_done_pulse` 正确联动。

物理：

| 信号 | FPGA ball | 说明 |
|---|---:|---|
| RS485 TX | AN16 | FPGA→PHY |
| RS485 RX | AM17 | PHY→FPGA |
| DE/RE | AN19 | 半双工控制 |

HMP：RS485+→CON19 pin5；RS485-→CON19 pin1；GND→pin3。

---

# 10. `i2c_master.v`

BMP390/SHT45 共用一条 I²C。

物理：

| 信号 | CON11 | FPGA |
|---|---:|---:|
| SCL | pin1 | AH13 |
| SDA | pin3 | AJ13 |
| BMP INT（可选） | pin2 | AN13 |

必须：

- open-drain，只输出 0/Z；
- START/reSTART/STOP；
- 7-bit addr；
- ACK/NACK；
- multi-byte read/write；
- programmable SCL；
- timeout；
- bus recovery：9 pulse + STOP；
- 400 kHz 基线，可降 100 kHz。

可把 `i2c_master` 设计成 request/response master，BMP/SHT driver 轮流调用；项目负责人 `sensor_hub` 不负责 I²C 细节。

---

# 11. PTB210 `ptb210_rs232.v`

## 物理

- PTB grey RX ← CON25 pin2 `RS232A_TXD`；
- PTB green TX → CON25 pin3 `RS232A_RXD`；
- blue GND → pin5；
- FPGA balls：TX AM14，RX AL14。

## 协议

ASCII + CR；支持 factory 常见 7E1。

V1.3 推荐：

1. `.FORM.0\r`；
2. single-poll；
3. 周期 `.P\r`；
4. 首响应字节锁 timestamp；
5. 解析十进制 pressure；
6. 输出 TLV。

寄存器 `0x6000` 严格按主指南：BAUD/UART_FORMAT/POLL/MODE/LAST_PRESSURE/COUNTERS/TIMEOUT。

必须测试 ASCII 正常、负号/小数、非法字符、超长帧、timeout。

---

# 12. HMP `hmp_modbus_rs485.v`

基线：

- 19200；
- 8N2；
- addr 240；
- RH reg 0x0000 F32；
- T reg 0x0002 F32；
- pressure compensation 0x0300 可选。

要求：

- 周期读取 RH/T；
- F32 只做 endian/repack，不做 FPGA 浮点计算；
- response first byte timestamp；
- CRC/timeout counters；
- 输出统一 TLV。

寄存器 base `0x6100` 严格遵守主指南。

---

# 13. EPSILON2 `epsilon_rs422.v`

## 物理

RS422：

- FPGA TX ball AN18；
- FPGA RX ball AM15；
- CON24 对应差分收发器；
- SYNC/1PPS 通过 CON22，最终由项目负责人 `time_sync_core` 使用。

## 串口

默认 921600，具体 serial format 依据设备实际配置。

## driver 分层

1. 公共 UART RX；
2. FDILink framing；
3. length；
4. checksum/CRC；
5. message id；
6. 转发已校验 raw frame；
7. 只最小解析 GNSS time tag；
8. 输出给项目负责人用于与 SYNC event 关联。

不要求在 FPGA 内完整解析姿态/位置的全部 FDILink payload。

每帧 timestamp = 帧首 byte 时间。

寄存器 base `0x6200` 实现 BAUD/MSG_MASK/RAW_FORWARD/GOOD/CRC/SYNC/LAST_MSG/GNSS_TIME。

---

# 14. BMP390 `bmp390_driver.v`

- I²C addr 0x76/0x77；
- CHIP_ID 0x00，期望 0x60；
- raw data 起始 0x04；
- PWR 0x1B；
- OSR 0x1C；
- ODR 0x1D；
- CONFIG 0x1F；
- CMD 0x7E。

最低实现：

1. 读 CHIP_ID；
2. 读/缓存 calibration raw；
3. 配置 PWR/OSR/ODR/IIR；
4. 周期读取 raw pressure/temp；
5. timestamp = data-ready 或读事务开始；
6. raw TLV；
7. compensation 默认由 host 完成，FPGA fixed-point 补偿为可选扩展。

base `0x6300`。

---

# 15. SHT45 `sht45_driver.v`

- addr 0x44；
- high-repeatability baseline；
- heater 默认 off；
- 触发测量；
- 等待 datasheet conversion time；
- 读 T word + CRC，RH word + CRC；
- 每个 word CRC 必须校验；
- timestamp = measurement trigger time；
- 输出 raw 或验证后的 fixed-point。

base `0x6400`。

必须测试 CRC good/bad、NACK、conversion not ready、bus recovery。

---

# 16. TFA1500-L `tfa1500_uart.v`

## 物理

- CON21 TTL UART；
- FPGA control TX AP14；
- HF RX AN14；
- LF RX 可用 CON11 pin4 / AP13。

## 高频模式

- 500000 8N1；
- start `55 AA CB CC CC CC CC FB`；
- stop `55 AA CC CC CC CC CC FC`；
- data：`0x5C + 3-byte little-endian distance(cm) + checksum`；
- `0x3FFFFF` invalid。

## 低频模式

- >=115200；
- header 0x55；
- cmd/len/data/XOR checksum；
- continuous command `55 02 02 20 00 75`。

要求：

- high/low 两种 parser；
- 模式切换前停止旧模式并等待 silence；
- 统一输出 `distance_mm`；
- checksum/error counters。

base `0x6500`。

---

# 17. RD105 `rd105_uart.v`

## 物理

V1.3：Bank88 3.3 V GPIO UART：

- FPGA TX AM12 → CON11 pin5 → RD105 RX；
- FPGA RX AN12 ← CON11 pin7 ← RD105 TX。

设备侧 TTL 若不是 3.3 V compatible，必须使用 level shifter；不得直接接 5 V 到 FPGA。

## 协议

- 38400 8N1；
- Modbus RTU；
- addr 1；
- 0x03 read；
- 0x10 write；
- channel1 0x1000...；
- TG target 0x1000，int32，两 regs，25°C=25,000,000。

必须：

- read target；
- read actual；
- write target；
- read ERRORCODE；
- 设备确认后才更新 active target；
- CRC/timeout。

base `0x6600`。

---

# 18. 时间戳规则

你的 driver 使用负责人提供：

```verilog
input wire [63:0] timestamp_now;
input wire        time_sync_valid;
input wire [31:0] time_sync_seq;
```

规则：

- PTB/HMP/RD105：响应首字节时间；
- EPSILON：frame 首字节；
- TFA：有效 frame 首字节；
- SHT45：trigger command 时间；
- BMP390：data-ready（若用 INT），否则读取开始时间。

不得自行建立第二个自由运行 timestamp counter。

---

# 19. 设备寄存器

你必须完整实现主指南第 7.11~7.17：

- PTB `0x6000`；
- HMP `0x6100`；
- EPSILON `0x6200`；
- BMP `0x6300`；
- SHT `0x6400`；
- TFA `0x6500`；
- RD105 `0x6600`。

设备协议参数（baud/address/mode/poll interval）不得硬编码到只有改 RTL 才能调整；除明确只读的器件固有值外，应通过寄存器配置。

---

# 20. 必须完成的 UART/协议回归

## UART

- 7E1/8N1/8N2；
- parity error；
- stop error；
- baud mismatch 小范围；
- continuous bytes；
- backpressure。

## Modbus

- 0x03；
- 0x10；
- CRC error；
- exception；
- timeout；
- wrong slave；
- wrong function；
- inter-frame gap。

## I²C

- ACK/NACK；
- repeated start；
- clock divider；
- SDA stuck low recovery；
- timeout。

## 每个 sensor

必须有至少：

- 1 个正常完整事务；
- 1 个 checksum/CRC/parse error；
- 1 个 timeout/offline；
- `msg_stream` backpressure；
- reset/re-enable。

---

# 21. XDC fragment

提交：

`constraints/member3_uart_sensors.xdc`

包含且只包含：

- RS232A pins；
- RS422 logic pins；
- RS485 TX/RX/DE；
- TFA TTL UART；
- BMP/SHT I²C；
- RD105 GPIO UART；
- EPSILON serial pins。

SYNC_IN/CON22 的最终 time-sync constraint 由项目负责人整合；你可在文档中注明信号来源，但不要重复定义最终 time_sync clocking。

---

# 22. 最终交付目录

```text
member3_uart_sensors/
├── README.md
├── rtl/
│   ├── uart_rx.v
│   ├── uart_tx.v
│   ├── crc16_modbus.v
│   ├── modbus_rtu_master.v
│   ├── rs485_halfduplex_ctrl.v
│   ├── i2c_master.v
│   ├── ptb210_rs232.v
│   ├── hmp_modbus_rs485.v
│   ├── epsilon_rs422.v
│   ├── bmp390_driver.v
│   ├── sht45_driver.v
│   ├── tfa1500_uart.v
│   └── rd105_uart.v
├── sim/
│   ├── tb/
│   ├── models/
│   └── vectors/
├── constraints/member3_uart_sensors.xdc
├── scripts/run_sim.tcl
├── scripts/run_synth_check.tcl
├── reports/SIM_REPORT.md
├── reports/SYNTH_REPORT.md
├── reports/TIMING_CDC_NOTES.md
└── docs/
    ├── INTERFACE.md
    ├── REGISTER_MAP.md
    ├── HARDWARE_MAPPING.md
    ├── UART_BAUD_ACCURACY.md
    ├── SENSOR_PROTOCOL_MATRIX.md
    └── KNOWN_ISSUES.md
```

---

# 23. `SENSOR_PROTOCOL_MATRIX.md` 必须包含

| Device | Physical | FPGA pins | Baud/Clock | Format | Protocol | Timestamp rule | Source ID | Register base |
|---|---|---|---|---|---|---|---|---|

七个设备必须全部填写，不能写“见手册”代替关键参数。

---

# 24. 最终验收标准

- [ ] 公共 UART 7E1/8N1/8N2 PASS；
- [ ] UART 最高项目目标 baud PASS；
- [ ] Modbus CRC/gap/timeout PASS；
- [ ] RS485 DE/RE 时序 PASS；
- [ ] I²C START/reSTART/STOP/recovery PASS；
- [ ] PTB210 driver PASS；
- [ ] HMP driver PASS；
- [ ] EPSILON FDILink framing/check PASS；
- [ ] BMP390 driver PASS；
- [ ] SHT45 CRC PASS；
- [ ] TFA high/low mode PASS；
- [ ] RD105 read/write PASS；
- [ ] 七个设备独立 `msg_stream` + FIFO 背压/并发 PASS；
- [ ] 所有设备 timeout/offline 可观测；
- [ ] Vivado synthesis PASS；
- [ ] 项目负责人无需修改成员内部 RTL 即可实例化。
