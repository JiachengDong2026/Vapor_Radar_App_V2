# 成员1 FPGA 开发任务书——双 ADC（AD4630 + ADC3660）与 EPSILON2

> 文档版本：V1.1  
> 开发环境：Xilinx Vivado  
> RTL：Verilog-2001  
> FPGA：Xilinx XCKU11P-2FFVA1156I  
> 任务性质：高速采集链路负责人；完成两个 ADC 的全部 FPGA 接口及 EPSILON2 协议驱动。  
> 公共 UART 由项目负责人提供。

## 1. 任务目标与责任边界

你必须交付以下正式 RTL：

1. `adc_ad4630_if.v` —— 原位测量系统 ADC；
2. `adc_adc3660_if.v` —— 遥测系统 ADC；
3. `epsilon_rs422.v` —— EPSILON2 RS422/FDILink 驱动；
4. 与上述模块直接相关的 FIFO/CDC 辅助 RTL（若需要，文件名必须在 README 列清）；
5. 对应 testbench、器件行为模型、XDC fragment、Vivado batch 脚本和全部文档。

### 不属于你的任务

- WMS、正弦/锯齿生成；
- AD5791 DAC；
- 通用 `uart_rx/uart_tx`；
- DILA/1f/2f；
- ADC 周期切帧/周期 timestamp；
- USB/VLP1；
- `time_sync_core`；
- 项目顶层和总 XDC。

**关键边界：你的两个 ADC 只输出连续统一 `sample_stream`；项目负责人用 WMS 的 `scan_start/cycle_id` 对样点进行周期切分。**

## 2. 必须阅读的资料

1. `FPGA下位机Verilog开发指南_V1.0.md`；
2. `FPGA下位机详细架构与接口分配方案.md`；
3. `Docs/下位机需求分析.md`；
4. `Docs/电路板资料/LIDAR_WATER_VAPOR_DETECTION_SCH_0908(1).pdf`；
5. `Docs/电路板资料/XCKU11P-2FFVA1156I(1).ucf`；
6. Analog Devices AD4630 官方 datasheet；
7. Texas Instruments ADC3660 官方 datasheet；
8. `Docs/FPGA设备接入手册/8-1-组合导航EPSILON使用手册...pdf`；
9. `Docs/FPGA设备接入手册/8-2-组合导航EPSILON2彩页...pdf`。

若 datasheet、原理图、旧 UCF 之间存在冲突：**原理图决定物理连线，器件官方 datasheet 决定器件时序；不能自行猜 lane/位序。**

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

### B. 低速设备 `msg_stream`

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

### C. 时间输入

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


# 子任务 A：AD4630

## A.1 物理用途

原位光电探测器：`CON15 -> AD4630 CH1 -> FPGA`。

## A.2 FPGA pins

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

## A.3 功能

必须完成：

- 上电/软复位；
- 器件配置（如项目实际工作模式需要）；
- 按 `SAMPLE_RATE_REQ_HZ` 产生稳定 CNV；
- BUSY 监测和 timeout；
- SCK 读取；
- 8 路 SDO 正确拼接；
- 器件原始位宽转换为 32-bit sample；
- 采样率 active/report；
- overflow/drop/error 统计；
- 向系统提供标准 `sample_stream`。

## A.4 标准输出边界

最终交给项目负责人的模块输出必须是 `sys_clk` 域标准：

```verilog
output wire        s_valid;
input  wire        s_ready;
output wire [31:0] s_data;
output wire [7:0]  s_flags;
```

物理 ADC 采样不可背压，因此模块内部必须有 capture buffer/FIFO。允许实例化项目约定的 FIFO wrapper；若主工程 FIFO 尚未提供，可在 `sim/stubs/` 使用接口兼容模型。正式交付 README 必须明确 FIFO 深度需求和最坏情况。

## A.5 寄存器：base `0x4000`

必须实现：

- common header；
- `0x4010 SAMPLE_RATE_REQ_HZ` shadow；
- `0x4014 SAMPLE_RATE_ACT_HZ`；
- `0x4018 SAMPLE_FORMAT`；
- `0x401C EXPECTED_PER_CYCLE`；
- `0x4020 FIFO_LEVEL`；
- `0x4024 DROP_COUNT`；
- `0x4028/0x402C SAMPLE_COUNT_LO/HI`；
- `0x4030 CNV_HIGH_TICKS`；
- `0x4034 BUSY_TIMEOUT_TICKS`；
- `0x4038 IF_MODE`；
- `0x403C RAW_STREAM_ENABLE`。

采样率等会影响实时链路的配置采用 shadow+commit。commit 必须在当前 conversion 不处于读取中时生效。

`SAMPLE_RATE_REQ_HZ` 不是“无条件保证任意频率”。必须根据 AD4630 时序和板级时钟能力检查范围；不支持的值返回 `cfg_error`、置 `ERROR.CONFIG_RANGE`，并保持原 active 配置。`SAMPLE_RATE_ACT_HZ` 始终报告真实生效值。

## A.6 数据格式

`SAMPLE_FORMAT` 中至少固定并文档化：

- bit `[7:0]` ADC effective bits；
- bit8 signed(1)/unsigned(0)；
- bits `[15:9]` reserved；
- bits `[23:16]` lane count；
- 其余保留。

`s_data` 必须把有效 ADC 数据符号扩展/零扩展到 32 bit，禁止把 8 lane 原始拼接格式直接泄漏给 DILA。

## A.7 时序/XDC

必须交：

- 相关 PACKAGE_PIN 片段；
- 与 SCK/数据采样有关的时序约束；
- 如果 SCK 由 FPGA 产生，写出 generated clock 或合理 timing exception；
- 根据 datasheet 说明采样边沿；
- 不得通过“false path 全部屏蔽”掩盖真实接口时序。

## A.8 必测项

- 正常连续转换至少 10000 samples；
- 多种 sample rate；
- BUSY 正常；
- BUSY 永不返回；
- SDO 一路错误/全 0/全 1；
- FIFO backpressure；
- FIFO overflow，确认 `DROP_COUNT` 与 `ERROR[2]`；
- soft reset；
- commit 在 busy 期间到达；
- 数据 lane 拼接 pattern test（0xAA/0x55/计数序列）。

---

# 子任务 B：ADC3660

这是本任务中优先级最高、时序要求最高的模块。

## B.1 物理用途

遥测光电探测器：`CON17 -> ADC3660 CH1 -> FPGA`。

## B.2 FPGA 物理引脚

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

## B.3 第一项必须完成的设计确认

在正式写数据捕获 FSM 前，先在 `docs/adc3660_lane_map.md` 冻结：

1. ADC3660 实际配置的数据输出模式；
2. DA5/DA6/DB5/DB6 分别承载的逻辑 lane；
3. SDR/DDR；
4. 每个 DCLK edge 对应哪一部分 sample；
5. FCLK 的 frame boundary 定义；
6. 当前只使用 CH1 时另一通道如何处理；
7. 每个最终 sample 的有效 bit 数、signed/unsigned；
8. DCLK/FCLK 频率关系；
9. 初始化 SPI 寄存器序列。

这个文件是验收件。资料不足的项明确标为 `REQUIRES_BOARD_CONFIRMATION`，但不得自行猜位序。

## B.4 功能要求

- ADC reset/init；
- SPI register read/write；
- source-synchronous data capture；
- DCLK/FCLK 对齐；
- 必要时使用 IDDR/ISERDES/Xilinx I/O primitive；
- 数据 lane 拼接成一个标准 32-bit sample；
- 从 ADC 时钟域 CDC 至 `sys_clk`；
- capture FIFO；
- FIFO overflow/drop 统计；
- DCLK missing/clock detect；
- SYNC 计数；
- 标准 `sample_stream` 输出。

## B.5 最终输出

```verilog
output wire        s_valid;
input  wire        s_ready;
output wire [31:0] s_data;
output wire [7:0]  s_flags;
```

上层不得看到 DA/DB lane packing。

## B.6 寄存器：base `0x4100`

实现：

- common header；
- `0x4110 SAMPLE_RATE_REQ_HZ` shadow；
- `0x4114 SAMPLE_RATE_ACT_HZ`；
- `0x4118 SAMPLE_FORMAT`；
- `0x411C EXPECTED_PER_CYCLE`；
- `0x4120 FIFO_LEVEL`；
- `0x4124 DROP_COUNT`；
- `0x4128/0x412C SAMPLE_COUNT`；
- `0x4130 LANE_MODE`；
- `0x4134 DCLK_STATUS`；
- `0x4138 SYNC_COUNT`；
- `0x413C RAW_STREAM_ENABLE`；
- `0x4140 SPI_CLK_HZ`。

`LANE_MODE` 的编码由你在 `register_map.md` 明确，至少应能唯一标识当前最终冻结模式。

`SAMPLE_RATE_REQ_HZ` 必须服从板上 ADC clock tree 和 ADC3660 可配置范围。若硬件实际上只有固定采样时钟，不允许伪装成可任意调采样率：此时该寄存器只能接受支持的离散值/数字抽取值；其他请求返回 `cfg_error` + `ERROR.CONFIG_RANGE`，`SAMPLE_RATE_ACT_HZ` 报告真实有效值。

## B.7 时序要求

必须按 ADC3660 source-synchronous 接口处理：

- DCLK/FCLK 建立真实 clock；
- data pin 使用 `set_input_delay`；
- 不能直接用 `sys_clk` always block 采 DA/DB；
- CDC 必须经 async FIFO/握手；
- 不允许把 DCLK/data 全部设 false path 来规避 timing；
- `report_timing` 中必须检查 data-to-DCLK；
- 在 `test_report.md` 中给出关键时序路径和 slack 摘要。

## B.8 测试

行为 model 至少产生：

- 计数递增 sample；
- `0xAAAA/0x5555` pattern；
- frame boundary；
- DCLK 短暂停顿；
- FCLK 故障；
- lane bit error；
- FIFO 长时间 backpressure；
- overflow；
- reset/re-init；
- SPI readback。

连续测试不少于 10000 个 sample，逐点 scoreboard 比较。

---

# 子任务 C：EPSILON2

## C.1 物理连接

EPSILON2 AUX：

| 设备端 | 板端 | FPGA |
|---|---|---|
| pin6 TX+ | CON24 pin2 `RS422_RXA` | 板载 RS422 PHY -> AM15 RX logic |
| pin7 TX- | CON24 pin3 `RS422_RXB` | 同上 |
| pin9 RX+ | CON24 pin7 `RS422_TXY` | AN18 TX logic -> PHY |
| pin8 RX- | CON24 pin8 `RS422_TXZ` | 同上 |
| pin1 GND | CON24 pin5 | GND |

逻辑 pins：

- `FPGA_RS422_TXD_L` = AN18；
- `FPGA_RS422_RXD_L` = AM15。

GNSS `SYNC_IN`/1PPS 使用 CON22、AP18，但 **SYNC 输入捕获和 `time_sync_core` 由项目负责人实现**。你的模块只负责解析 GNSS time tag，并通过明确接口提供给负责人。

## C.2 串口

- RS422；
- 默认 921600 bps；
- FDILink；
- UART 使用公共 `uart_rx/tx`，典型 8N1，最终以手册为准。

## C.3 功能边界

必须实现：

1. UART byte reception；
2. FDILink frame synchronization；
3. length 检查；
4. checksum/CRC 检查（严格按手册）；
5. message ID 提取；
6. raw validated frame 缓存；
7. `FDI_MSG_MASK` 过滤；
8. `RAW_FORWARD_ENABLE`；
9. 对“项目时间同步需要的 GNSS time tag”做最小解析；
10. 输出 raw frame `msg_stream`。

**不要**在 FPGA 中完整解算姿态/位置/导航结果。上位机可解析 raw FDILink。

## C.4 timestamp

每个 FDILink frame 的 `m_timestamp` = **帧首字节开始接收时刻**。必须在识别到候选帧首字节时锁存，不得等整帧 CRC 通过后再取时间。

若 CRC 最终失败，丢弃该帧并增加错误计数。

## C.5 输出

- `source_id=16'h0042`；
- raw frame：`msg_id=16'h1200`；
- `m_cycle_id=0`。

raw payload 至少包含完整、已校验通过的 FDILink 原始字节，禁止去掉后续上位机可能需要的字段。

GNSS time tag 不通过 VLP1 自定义私有帧输出；建议提供给顶层：

```verilog
output wire        gnss_time_valid;
input  wire        gnss_time_ready;
output wire [63:0] gnss_time_tag;
output wire [15:0] gnss_time_msg_id;
```

项目负责人连接到 `time_sync_core`/寄存器。

## C.6 寄存器：base `0x6200`

必须实现：

- common header；
- `0x6210 BAUD`；
- `0x6214 FDI_MSG_MASK_LO`；
- `0x6218 FDI_MSG_MASK_HI`；
- `0x621C RAW_FORWARD_ENABLE`；
- `0x6220 GOOD_FRAME_COUNT`；
- `0x6224 CRC_ERR_COUNT`；
- `0x6228 SYNC_EVENT_COUNT`：此项由顶层可选回写/连接；若模块无 SYNC 输入则保持只读外部计数输入；
- `0x622C LAST_FDI_MSG_ID`；
- `0x6230/0x6234 LAST_GNSS_TIME_LO/HI`。

## C.7 必测项

- 多种合法 FDILink message；
- 连续无间隙帧；
- 前导垃圾字节后恢复同步；
- 截断帧；
- 长度错误；
- CRC/checksum error；
- msg filter；
- raw forwarding disable；
- 921600 连续高吞吐；
- `m_ready` backpressure；
- frame timestamp 保持为首字节时刻。

---

# 6. 双 ADC 统一接口与实现要求

1. 两个 ADC 对上层必须使用完全相同的 `sample_stream` 语义；
2. `s_data` 中有效位位置必须在 `interface_contract.md` 写清；
3. ADC 物理采样不可被 `s_ready` 反压；
4. 两个 ADC 均必须有 capture FIFO、overflow 标志、drop counter、sample counter；
5. 所有 ADC device clock → `sys_clk` 跨域必须采用明确 CDC 结构；
6. 禁止用组合逻辑跨域传多位 sample；
7. ADC3660 必须提交 `docs/adc3660_lane_map.md`；
8. AD4630 若存在多 lane/不同输出模式，必须提交 `docs/ad4630_if_mode.md`；
9. 上层不得感知 ADC 原始 lane packing。

# 7. XDC 交付要求

至少提交：

```text
constraints/
├── adc_ad4630_pins.xdc
├── adc_ad4630_timing.xdc
├── adc_adc3660_pins.xdc
├── adc_adc3660_timing.xdc
└── epsilon_rs422_pins.xdc
```

要求：

- pin 必须来自本项目原理图/UCF；
- ADC source-synchronous clocks 必须 `create_clock`；
- 输入 data 必须有合理 `set_input_delay`；
- CDC 约束必须与 RTL 实现一致；
- 不得粗暴把 ADC data-to-DCLK 全部 `set_false_path`；
- EPSILON2 只约束本模块实际使用的 RS422 logic pin；GNSS `SYNC_IN` 由负责人约束。

# 8. 必须完成的联合仿真

除各子模块单测外，必须增加：

### `tb_dual_adc_parallel.v`

同时运行 AD4630 + ADC3660 行为模型：

- 两路不同 sample rate；
- 两路同时持续输出；
- 对两路分别施加 `s_ready` backpressure；
- 确认一条链的 backpressure 不影响另一条物理采集；
- overflow 只在对应链路统计；
- 连续不少于 10000 sample/ADC scoreboard PASS。

### `tb_epsilon_stream.v`

验证连续 FDILink frame、错误帧恢复、UART backpressure、GNSS time-tag 输出。

# 9. 最终交付目录

```text
member1_dual_adc_epsilon/
├── rtl/
│   ├── adc_ad4630_if.v
│   ├── adc_adc3660_if.v
│   ├── epsilon_rs422.v
│   └── <必要的本地 FIFO/CDC 辅助模块>.v
├── sim/
│   ├── tb_adc_ad4630_if.v
│   ├── tb_adc_adc3660_if.v
│   ├── tb_dual_adc_parallel.v
│   ├── tb_epsilon_rs422.v
│   ├── models/
│   ├── vectors/
│   └── stubs/
├── constraints/
│   ├── adc_ad4630_pins.xdc
│   ├── adc_ad4630_timing.xdc
│   ├── adc_adc3660_pins.xdc
│   ├── adc_adc3660_timing.xdc
│   └── epsilon_rs422_pins.xdc
├── docs/
│   ├── README.md
│   ├── register_map.md
│   ├── interface_contract.md
│   ├── hardware_wiring.md
│   ├── adc3660_lane_map.md
│   ├── ad4630_if_mode.md
│   ├── test_report.md
│   └── known_issues.md
├── scripts/
│   ├── run_sim.tcl
│   └── run_synth_check.tcl
└── DELIVERY_CHECKLIST.md
```

# 10. 验收标准

- 两个 ADC 独立工作、独立 FIFO、独立错误统计；
- AD4630/ADC3660 采样数据逐点 scoreboard 正确；
- ADC3660 lane mapping 有明确证据；
- ADC 时钟约束真实存在且 timing report 已检查；
- EPSILON2 合法帧/CRC 错误/失步恢复均验证；
- 所有 test PASS；
- 综合 Error=0、Critical Warning=0；
- 未私自实现 UART、WMS、DILA 或 USB；
- 项目负责人将 `rtl/`、XDC fragment 复制到主工程即可实例化使用。
