# 成员2 FPGA 开发任务书——双 AD5791 DAC、双 WMS、PTB210 与 TFA1500-L

> 文档版本：V1.1  
> 开发环境：Xilinx Vivado  
> RTL：Verilog-2001  
> FPGA：Xilinx XCKU11P-2FFVA1156I  
> 任务性质：两套测量系统的激光调制输出链负责人，并完成两个较轻串口传感器 driver。  
> 公共 UART 由项目负责人提供。

## 1. 任务目标与责任边界

你必须完成：

1. `wms_wavegen.v` —— 可实例化两次的 WMS 波形核；
2. `sine_lut.v` —— WMS 正弦发生；
3. `dac_ad5791_if.v` —— 可实例化两次，分别驱动 DAC0/DAC1；
4. `ptb210_rs232.v`；
5. `tfa1500_uart.v`；
6. WMS→DAC 端到端 testbench；
7. 所有对应文档、XDC fragment 和 Vivado batch 脚本。

### 不属于你的任务

- AD4630/ADC3660；
- 通用 UART；
- DILA；
- ADC 周期切帧；
- 全局时间同步；
- USB/VLP1 packetizer；
- 项目顶层。

你的核心交付必须使负责人可以直接得到两条链：

```text
WMS0 sample_stream -> DAC0 AD5791 -> 原位激光驱动器
WMS1 sample_stream -> DAC1 AD5791 -> 遥测激光驱动器
```

同时将 `scan_start/cycle_id/sine_phase` 输出给负责人做 ADC 周期同步和 DILA。

## 2. 必须阅读的资料

1. `FPGA下位机Verilog开发指南_V1.0.md`；
2. `FPGA下位机详细架构与接口分配方案.md`；
3. `Docs/下位机需求分析.md`；
4. 板卡原理图 `LIDAR_WATER_VAPOR_DETECTION_SCH_0908(1).pdf`；
5. `XCKU11P-2FFVA1156I(1).ucf`；
6. Analog Devices AD5791 官方 datasheet；
7. `Docs/FPGA设备接入手册/1-数字气压计.pdf`（PTB210）；
8. `Docs/FPGA设备接入手册/5-测距雷达.pdf`（TFA1500-L）。

**两路最终 WMS 最高正弦频率、锯齿频率和期望 DAC 点数若尚未完全冻结，不得自行假定。实现必须参数化，并在 README 写出当前 AD5791 + SPI 时钟可支持的更新率范围。**

## 公共接口冻结（所有成员必须遵守）

### 1. 时钟与复位

除器件源同步采样时钟外，控制平面统一使用：

```verilog
input wire sys_clk;      // 100 MHz
input wire rst_sys_n;    // 低有效，同步释放
```

任何成员不得自行再建立第二套系统时间基准或全局复位树。

### 2. `cfg_bus`

所有正式设备模块均实现：

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

- `cfg_valid && cfg_ready` 完成一次访问；
- `cfg_error` 与 `cfg_ready` 同拍有效；
- 单 outstanding transaction；
- 仅响应自己的 0x100 B 地址页；其他地址不得拉高 `cfg_ready`；
- 非法参数、越界值和不支持写操作必须返回 `cfg_error`，不得静默接受。

### 2.1 所有寄存器块统一首部

每个 0x100 B 模块地址页的前 0x10 B 固定为：

| offset | 名称 | 访问 | 含义 |
|---:|---|---|---|
| `+0x00` | `ID_VERSION` | RO | `[31:16] module_id, [15:8] major, [7:0] minor` |
| `+0x04` | `CONTROL` | RW/W1P | bit0 enable；bit1 soft_reset；bit2 commit；bit3 clear_fifo |
| `+0x08` | `STATUS` | RO | bit0 enabled；1 ready；2 cfg_pending；3 busy；4 online；5 fifo_almost_full；6 overflow；7 error；8 time_sync_valid |
| `+0x0C` | `ERROR` | RO/W1C | bit0 timeout；1 protocol/CRC；2 FIFO overflow；3 device not ready；4 config range；5 CDC/internal；6 device error；7 data format |

不得改变这些 bit 定义；模块专用寄存器从 `+0x10` 开始。

### 3. ADC `sample_stream`

```verilog
output wire        s_valid;
input  wire        s_ready;
output wire [31:0] s_data;
output wire [7:0]  s_flags;
```

- `s_valid && s_ready` 表示一个样点完成传输；
- `s_valid=1 && s_ready=0` 时 `s_data/s_flags` 必须保持；
- 物理 ADC 不能被 `s_ready` 反压停采；必须先进入本地 FIFO；
- FIFO 满必须置 overflow、累计 `DROP_COUNT`，不得静默覆盖。

### 4. 低速设备 `msg_stream`

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

`m_valid=1 && m_ready=0` 时上述所有输出保持稳定。

### 5. 时间输入

```verilog
input wire [63:0] timestamp_now;
input wire        time_sync_valid;
input wire [31:0] time_sync_seq;
```

成员模块只能消费该时间服务，不得自行维护全局 timestamp。


## 项目负责人提供的公共 UART 核——调用合同

通用串口 RTL **不属于任何成员任务**，由项目负责人统一实现并提供：

- `uart_rx.v`
- `uart_tx.v`

成员不得复制、修改或另写私有 UART。所有 RS232、RS422、TTL UART 和 Modbus 设备均使用下列 byte-stream 接口。

### `uart_rx`

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

### `uart_tx`

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

如果项目负责人公共 UART 尚未进入成员分支，成员可在 `sim/stubs/` 放置**仅用于仿真的同端口 stub**；stub 禁止进入正式 `rtl/` 和最终交付综合源文件。


# 子任务 A：WMS0/WMS1 波形生成

## A.1 正式 RTL

必须交付：

- `wms_wavegen.v`：**单通道、可参数化** WMS 核；项目顶层实例化两次形成 WMS0/WMS1；
- `sine_lut.v`：正弦查表/等效确定性正弦发生模块；
- 可选 `wms_dac_channel.v`：仅作为 WMS+AD5791 集成 wrapper，不能替代项目顶层；
- 所有 arithmetic helper 必须是本成员局部模块并列入 README。

不得把两个通道写成互相硬耦合状态机。WMS0/WMS1 必须可以独立 enable、独立配置、独立停止。

## A.2 波形定义

每个 DAC update 生成一个 Q1.31 有符号归一化样点：

```text
wave = offset + saw_ampl * saw(phase_saw)
              + sine_ampl * sin(phase_sine + phase0)
```

冻结定义：

- `phase_saw`：U32 相位，`0 ... 2^32-1` 对应一个完整锯齿周期；
- `saw_q31 = signed(phase_saw - 0x80000000)`，因此从约 -1 线性增加到约 +1，wrap 后回到 -1；
- `sine_lut` 输出 Q1.31；
- `SAW_AMPL_Q31`、`SAW_OFFSET_Q31`、`SINE_AMPL_Q31` 均按 Q1.31；
- 乘法使用至少 64-bit 中间结果，右移 31 bit 回到 Q1.31；
- 三项相加必须使用扩展位宽；
- 最终超过 Q1.31 范围时饱和，不得 wrap；每次饱和累计 `SAT_COUNT`。

## A.3 更新节拍与 DDS

建议 32-bit phase accumulator：

```text
phase_inc = round(freq_hz / update_hz * 2^32)
```

`DAC_UPDATE_HZ_ACT` 产生 DAC sample tick。每个 tick 最多产生一个 `dac_sample`。

必须满足：

- `dac_sample_valid && dac_sample_ready` 后样点才算被 DAC 接受；
- 若下一 update tick 到达而上一样点仍未被接受，必须置 `update_overrun/error`，不能静默丢样；
- 对明显高于 AD5791 持续更新能力的配置应在 commit 时拒绝或报告配置范围错误；
- README 中必须给出在当前 `SPI_CLK_HZ` 下验证过的最大持续 DAC update rate。

## A.4 scan/cycle/phase 输出合同

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

要求：

- `scan_start` 在锯齿 phase wrap 对应的样点边界产生 **1 个 sys_clk pulse**；
- `cycle_id` 每个 `scan_start` 增加 1；reset 后从 0 开始，第一次有效周期行为必须在 README 固定；
- `sine_phase` 是当前输出样点对应的基频相位，供负责人 DILA 锁相使用；
- 不得在成员模块内产生另一套 measurement cycle 定义。

## A.5 shadow / active commit

WMS0 base=`0x2000`；WMS1 base=`0x2100`。每个实例实现 common header，并实现：

| offset | 名称 | 访问 | 含义 |
|---:|---|---|---|
| `+0x10` | `SAW_FREQ_MHZ` | RW shadow | 0.001 Hz |
| `+0x14` | `SAW_AMPL_Q31` | RW shadow | Q1.31 |
| `+0x18` | `SAW_OFFSET_Q31` | RW shadow | Q1.31 |
| `+0x1C` | `SINE_FREQ_MHZ` | RW shadow | 0.001 Hz |
| `+0x20` | `SINE_AMPL_Q31` | RW shadow | Q1.31 |
| `+0x24` | `SINE_PHASE_U32` | RW shadow | 0..2^32 → 0..2π |
| `+0x28` | `DAC_UPDATE_HZ_REQ` | RW shadow | 请求更新率 |
| `+0x2C` | `DAC_UPDATE_HZ_ACT` | RO | 实际更新率 |
| `+0x30` | `CYCLE_ID` | RO | 当前周期 |
| `+0x34` | `LAST_SCAN_TICK_LO` | RO | 最近 scan_start tick |
| `+0x38` | `LAST_SCAN_TICK_HI` | RO | 同上 |
| `+0x3C` | `SAT_COUNT` | RO/W1C | 饱和次数 |
| `+0x40` | `PHASE_MODE` | RW shadow | bit0 连续相位；bit1 commit 时重置 phase |
| `+0x44` | `OVERRUN_COUNT` | RO/W1C | DAC 未及时接受样点次数 |

配置流程：host 写 shadow → `CONTROL.commit` → `cfg_pending=1` → **只在下一个 scan boundary 整体切换 active 参数** → 清 pending。

若当前尚未 enable、没有 scan boundary，可在 enable 前安全应用 pending 配置；具体行为必须在 README 固定并由 testbench 覆盖。

## A.6 数值与频率测试

至少验证：

- saw only；
- sine only；
- saw+sine+offset；
- 正/负幅值边界；
- saturation；
- phase continuity；
- phase reset mode；
- commit 恰好发生在周期中间时不能立刻改 active；
- 两个 WMS 使用不同频率、更新率并行运行；
- 长时间频率误差统计；
- `scan_start/cycle_id/sine_phase` 一致性；
- DAC backpressure / overrun 注入。


# 子任务 B：双 AD5791 DAC

## B.1 使用方式

只写**一个参数化模块**，在顶层实例化两次：

- DAC0：原位 WMS，base `0x3000`，模拟输出 CON7；
- DAC1：遥测 WMS，base `0x3100`，模拟输出 CON8。

禁止复制出 `dac0.v/dac1.v` 两套逻辑。

## B.2 上层样点接口

```verilog
input  wire [31:0] sample_data;   // signed Q1.31 normalized
input  wire        sample_valid;
output wire        sample_ready;
```

`sample_data` 的统一定义：signed Q1.31。模块将 `[-1,1)` 线性映射至 `[DAC_MIN_CODE,DAC_MAX_CODE]`。超范围必须饱和并增加计数/置 error，不允许二补码回绕。

本模块**不产生 WMS**。

## B.3 物理端口

```verilog
output wire DAC_AD5791_x_SCLK;
output wire DAC_AD5791_x_SYNCN;
output wire DAC_AD5791_x_SDIN;
input  wire DAC_AD5791_x_SDO;
output wire DAC_AD5791_x_RSTN;
output wire DAC_AD5791_x_CLRN;
output wire DAC_AD5791_x_LDACN;
```

### DAC0 pins

| net | ball |
|---|---:|
| SCLK | K21 |
| RSTN | M21 |
| SYNCN | K25 |
| SDIN | L24 |
| SDO | L27 |
| CLRN | H24 |
| LDACN | H27 |

### DAC1 pins

| net | ball |
|---|---:|
| SCLK | R22 |
| RSTN | G26 |
| SYNCN | J26 |
| SDIN | G27 |
| SDO | H26 |
| CLRN | J24 |
| LDACN | H23 |

## B.4 寄存器

模块参数 `BASE_ADDR` 分别为 0x3000/0x3100，必须实现：

- common header；
- `+0x10 DEVICE_CTRL` shadow；
- `+0x14 CLEAR_CODE`；
- `+0x18 DAC_MIN_CODE`；
- `+0x1C DAC_MAX_CODE`；
- `+0x20 LAST_CODE`；
- `+0x24 SPI_CLK_HZ`；
- `+0x28 WRITE_COUNT`；
- `+0x2C SPI_ERROR_COUNT`；
- `+0x30 DEVICE_ID_RAW`（若器件读回不可用可返回 0，并在 README 说明）。

## B.5 上电和写样点要求

- reset 后先保持 DAC 在安全状态；
- 严格按 AD5791 datasheet 执行 RESET/控制寄存器初始化；
- `sample_ready` 仅在模块能接受并最终发送一个完整 DAC update 时拉高；
- SPI transaction 中间不得接受第二个样点，除非实现有明确定义的输入 FIFO；
- 若 `sample_valid` 速率超过可持续更新率，通过 `sample_ready=0` 反压上层；不得静默 drop；
- 提供 `actual_spi_clk_hz`/README 说明时钟误差；
- SYNC/SCLK/LDAC 的建立保持时间按 datasheet。

## B.6 testbench

行为 model 必须解析串行 frame，并检查写入 code。

至少覆盖：

- reset/init；
- 0、正满量程、负满量程、中间值；
- MIN/MAX software clamp；
- 连续样点；
- `sample_valid` 保持直到 ready；
- SPI clock 不同配置；
- soft reset；
- clear；
- 两个实例参数化 elaboration；
- SDO/readback 若实现。

---

## B.7 双 DAC 额外要求

- `dac_ad5791_if.v` 必须是单设备可参数化模块，由项目顶层实例化两次；
- DAC0 与 DAC1 不能共享会造成互锁的状态机；
- 两个实例必须可使用不同 `SPI_CLK_HZ`/enable；
- 两个 DAC 的 `sample_ready` 独立；
- 必须增加 `tb_dual_ad5791_parallel.v`，同时向两路输入不同数据序列，确认无串扰；
- 必须增加 `tb_wms_ad5791_e2e.v`，至少跑两个完整 WMS cycle，并逐点检查发送给 AD5791 的 20-bit code 是否与 golden model 一致。

# 子任务 C：PTB210

## C.1 物理连接

| 信号 | 板端 | FPGA ball | 方向 |
|---|---|---:|---|
| `FPGA_RS232A_TXD` | CON25 pin2 | AM14 | FPGA -> PTB RX（灰线） |
| `FPGA_RS232A_RXD` | CON25 pin3 | AL14 | PTB TX（绿线） -> FPGA |
| GND | CON25 pin5 | - | 共地（蓝线） |

RS232 电平转换由板载 PHY 完成，FPGA 看到的是逻辑电平，禁止在 RTL 中处理 ±RS232 电压。

## C.2 原生协议

- ASCII 命令，以 `<CR>` 结束；
- 支持 1200..19200 baud；
- 工厂格式可能为 7E1，实际设备配置必须可通过寄存器设置；
- 单次读取：`.P\r`；
- 连续读取：`.BP\r`；
- V1.0 推荐 single-poll；
- 初始化可发送 `.FORM.0\r` 去除单位，便于数值解析。

## C.3 模块端口

除 `cfg_bus`、时间服务和 `msg_stream` 外：

```verilog
output wire ptb_txd;
input  wire ptb_rxd;
```

内部必须实例化公共 `uart_rx/uart_tx`，不得复制 UART FSM。

## C.4 寄存器：固定基地址 `0x6000`

必须实现开发指南中 PTB210 寄存器：

- `0x6000..0x600C` common header；
- `0x6010 BAUD`；
- `0x6014 UART_FORMAT`；
- `0x6018 POLL_INTERVAL_MS`；
- `0x601C MODE`；
- `0x6020 LAST_PRESSURE_MPA`；
- `0x6024 RX_FRAME_COUNT`；
- `0x6028 PARSE_ERROR_COUNT`；
- `0x602C TIMEOUT_MS`；
- `0x6030 DEVICE_ID_HASH`（允许返回 0）。

### UART_FORMAT 编码在本任务中冻结为

- bits `[3:0]` data bits：7 或 8；
- bits `[5:4]` parity：0 none，1 even，2 odd；
- bits `[7:6]` stop：1 或 2；
- 其他位写 0、读 0。

## C.5 时间戳

一次 `.P\r` 响应的 timestamp = **响应第一个有效字节的 `byte_start_pulse` 对应的 `timestamp_now`**。收到完整数字后不得重新取时间。

## C.6 输出数据

`source_id=16'h0040`，`msg_id=16'h1100`。

最低要求输出 `SENSOR_TLV_RECORD`：

- tag `0x0012 pressure_mPa`，type=I32；
- 可选 tag `0x0003 raw_frame`，type=BYTES；
- 错误情况下不得输出伪造有效压力。

注意：若 PTB 返回单位不是 Pa，必须按设备配置进行明确换算；换算关系写入 README 和 test vector。

## C.7 状态机要求

至少包含：`DISABLED -> INIT -> IDLE -> SEND_QUERY -> WAIT_RESPONSE -> PARSE -> PUBLISH -> IDLE`，以及独立 error/timeout 处理。

## C.8 必测项

- 正常 `.P` 响应；
- 正/负数（若设备允许）；
- 小数位变化；
- 带/不带空格；
- 非法字符；
- 半帧超时；
- UART parity/framing error；
- `m_ready` 长时间拉低；
- sensor offline 后恢复；
- poll interval 修改；
- `CONTROL.enable` 关闭/开启。

---

# 子任务 D：TFA1500-L

## D.1 物理连接

| 信号 | 板端 | FPGA ball |
|---|---|---:|
| TFA HF TX -> FPGA RX | CON21 pin1 | AN14 (`FPGA_UART_RXD_L`) |
| FPGA TX -> TFA RX | CON21 pin2 | AP14 (`FPGA_UART_TXD_L`) |
| Power_EN | CON21 pin3 | AK16 (`FPGA_UART_EN_L`) |
| GND | CON21 pin4 | - |
| TFA LF TX -> FPGA | CON11 pin4 | AP13 |

## D.2 模块物理端口

```verilog
output wire tfa_txd;
input  wire tfa_hf_rxd;
input  wire tfa_lf_rxd;
output wire tfa_power_en;
```

内部实例化公共 UART。

## D.3 高频模式

按当前资料：

- 默认 500000 bps，8N1；
- start command：`55 AA CB CC CC CC CC FB`；
- stop command：`55 AA CC CC CC CC CC FC`；
- data frame：5 B；header `0x5C`；3-byte little-endian distance(cm)；checksum；
- checksum = 3 个 distance byte 求和后按位取反低 8 bit；
- `0x3FFFFF` = invalid。

## D.4 低频模式

- baud >=115200；具体值由 BAUD 寄存器；
- frame header `0x55`；
- command + length + data + XOR checksum；
- continuous ranging command `55 02 02 20 00 75`。

## D.5 模式切换硬规则

`RANGE_MODE`：

- 0 standby；
- 1 low-frequency；
- 2 high-frequency。

切换流程必须：

1. 停止旧模式；
2. 等待 TX 完成；
3. 等待至少一个可配置/固定的 UART quiet interval；
4. 清 RX parser partial state；
5. 选择新的 RX 输入；
6. 配置 baud；
7. 发送新模式 start/continuous command；
8. 进入 RUN。

禁止直接切 mux 导致旧模式残留字节进入新 parser。

## D.6 timestamp

距离数据 timestamp = 对应有效设备 frame 的**首字节接收时刻**。

## D.7 输出

- `source_id=16'h0045`；
- `msg_id=16'h1100`；
- 标准 TLV 必须包含 `tag=0x0013 distance_mm`，type=U32；
- invalid distance 不能发布为有效 `distance_mm`，应增加 `HF_INVALID_COUNT`，可发状态/error event 由上层处理。

高频数据的 cm -> mm 换算使用整数乘 10，必须有溢出保护。

## D.8 寄存器：base `0x6500`

- common header；
- `0x6510 BAUD`；
- `0x6514 RANGE_MODE`；
- `0x6518 COMMAND`；
- `0x651C LAST_DISTANCE_MM`；
- `0x6520 DISTANCE_VALID`；
- `0x6524 APD_TEMP_RAW`；
- `0x6528 RX_FRAME_COUNT`；
- `0x652C CHECKSUM_ERR_COUNT`；
- `0x6530 HF_INVALID_COUNT`。

## D.9 必测项

- HF start/stop；
- HF 连续 500000 baud 数据；
- checksum 正误；
- invalid distance；
- LF continuous command；
- LF frame XOR 正误；
- LF↔HF 模式切换；
- quiet interval；
- `m_ready` backpressure；
- power enable disable；
- UART error recovery。

---

# 7. WMS→DAC 数值映射冻结

`wms_wavegen` 输出 `dac_sample` 定义为 signed Q1.31，范围 `0x80000000 (-1.0)` 到 `0x7fffffff (~+1.0)`。

`dac_ad5791_if` 必须把该归一化值线性映射到 `[DAC_MIN_CODE, DAC_MAX_CODE]`：

```text
u32 = sample_q31 + 2^31
code = DAC_MIN_CODE + ((u32 * (DAC_MAX_CODE-DAC_MIN_CODE)) >> 32)
```

- 最终 code 限制为 AD5791 有效 20 bit；
- 不允许 WMS 直接知道 AD5791 的 SPI frame；
- 不允许 DAC driver 重新生成 sine/saw；
- 数值映射 golden model 必须放在 testbench 或 `sim/vectors/` 中。

# 8. XDC 交付要求

至少：

```text
constraints/
├── ad5791_0_pins.xdc
├── ad5791_1_pins.xdc
├── ptb210_rs232_pins.xdc
└── tfa1500_pins.xdc
```

WMS 本身无板级 pin。DAC pin 必须逐项与原理图核对；PTB/TFA 只提交本设备实际使用 pin 的 fragment。

# 9. 最终交付目录

```text
member2_wms_dual_dac_ptb_tfa/
├── rtl/
│   ├── wms_wavegen.v
│   ├── sine_lut.v
│   ├── dac_ad5791_if.v
│   ├── ptb210_rs232.v
│   ├── tfa1500_uart.v
│   └── <必要 arithmetic/helper>.v
├── sim/
│   ├── tb_wms_wavegen.v
│   ├── tb_dac_ad5791_if.v
│   ├── tb_dual_ad5791_parallel.v
│   ├── tb_wms_ad5791_e2e.v
│   ├── tb_ptb210_rs232.v
│   ├── tb_tfa1500_uart.v
│   ├── models/
│   ├── vectors/
│   └── stubs/
├── constraints/
│   ├── ad5791_0_pins.xdc
│   ├── ad5791_1_pins.xdc
│   ├── ptb210_rs232_pins.xdc
│   └── tfa1500_pins.xdc
├── docs/
│   ├── README.md
│   ├── register_map.md
│   ├── interface_contract.md
│   ├── hardware_wiring.md
│   ├── wms_numeric_definition.md
│   ├── dac_update_rate_budget.md
│   ├── test_report.md
│   └── known_issues.md
├── scripts/
│   ├── run_sim.tcl
│   └── run_synth_check.tcl
└── DELIVERY_CHECKLIST.md
```

# 10. 验收标准

- WMS0/WMS1 可独立配置和运行；
- WMS 数值格式、相位、scan boundary 有明确 golden test；
- 双 AD5791 并行工作无串扰；
- WMS→DAC 端到端 code 全部匹配 golden model；
- 超过 DAC 能力的更新条件不会静默丢样；
- PTB/TFA 合法帧、错误帧、timeout、backpressure 均验证；
- 所有 UART 均实例化负责人公共 UART，不存在私有 UART；
- 综合 Error=0、Critical Warning=0；
- 项目负责人可直接复制 RTL/XDC 并分别实例化两路 WMS/DAC。
