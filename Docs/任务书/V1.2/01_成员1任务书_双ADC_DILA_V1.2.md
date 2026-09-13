# 成员1 FPGA 开发任务书——双 ADC（AD4630 + ADC3660）与双路 DILA

> 文档版本：V1.2  
> 开发环境：Xilinx Vivado  
> RTL：Verilog-2001  
> FPGA：Xilinx XCKU11P-2FFVA1156I  
> 任务定位：负责完整“探测器数字采集 → ADC接口 → 缓冲/CDC → DILA 1f/2f 解调 → 标准DILA数据输出”链路。

---

# 1. 最终任务范围

你正式负责：

1. `adc_ad4630_if.v` —— 原位 ADC 接口；
2. `adc_adc3660_if.v` —— 遥测 ADC 接口；
3. 两路 ADC 的 capture FIFO / CDC / overflow 监测；
4. `dila_core.v` —— 单通道可参数化 DILA 核，顶层实例化两次；
5. DILA 所需参考发生、正交混频、低通滤波、抽取、block framing 等子模块；
6. ADC→DILA 端到端仿真；
7. 对应 XDC fragment、行为模型、testbench、脚本和文档。

建议正式 RTL 文件：

```text
rtl/
├── adc_ad4630_if.v
├── adc_adc3660_if.v
├── adc_capture_fifo.v          # 若采用自研同步/异步FIFO wrapper
├── adc_stream_fanout.v         # ADC RAW + DILA 分流；可参数化
├── dila_core.v
├── dila_ref_gen.v
├── dila_mixer.v
├── dila_lpf.v
├── dila_decimator.v
├── dila_block_framer.v
└── fixed_point_helpers.v       # 如确有需要，可拆分
```

如果使用 Vivado FIFO IP，必须提交：

- `.xci`；
- 生成方式说明；
- 参数截图/文本；
- 仿真与综合脚本中可重新生成；

不得只提交某台电脑上已生成的缓存目录。

---

# 2. 不属于你的任务

以下不由你开发：

- WMS 波形产生；
- AD5791 DAC；
- UART/传感器；
- 项目级 `adc_cycle_framer` RAW周期封装；
- 项目级 `time_sync_core`；
- USB/VLP1；
- packetizer/stream arbiter；
- 项目总顶层；
- 最终总 XDC。

你必须消费成员2提供的冻结 WMS 参考接口，不得依赖其内部实现。

---

# 3. 必须阅读资料

1. `FPGA下位机Verilog开发指南_V1.0.md`；
2. `FPGA下位机详细架构与接口分配方案.md`；
3. `Docs/下位机需求分析.md`；
4. 板卡原理图 `LIDAR_WATER_VAPOR_DETECTION_SCH_0908(1).pdf`；
5. `XCKU11P-2FFVA1156I(1).ucf`；
6. AD4630 官方 datasheet；
7. ADC3660 官方 datasheet；
8. 若项目资料中存在 ADC 配置表/寄存器初始化说明，也必须纳入 `docs/HARDWARE_MAPPING.md`。

冲突处理：

- **原理图决定板级物理连接**；
- **器件官方 datasheet 决定器件时序和数据协议**；
- 主开发指南决定项目内部标准接口；
- 无法确认的 lane/位序/模式不得猜测，必须在 `KNOWN_ISSUES.md` 标出。

---

## 3.1 本任务冻结 FPGA 物理引脚

### AD4630

| net | FPGA ball |
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

原位探测器模拟输入由板卡 `CON15` 进入 AD4630；FPGA 只处理 ADC 数字侧。

### ADC3660

| net | FPGA ball |
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

遥测探测器模拟输入由板卡 `CON17` 进入 ADC3660。上述 net 是板级事实；**lane 的逻辑位序、DDR packing 和最终输出模式必须结合 ADC3660 实际寄存器配置确认，不能仅凭 DA/DB 网络名推断。**

# 4. 公共 `cfg_bus`

ADC0 base `0x4000`；ADC1 base `0x4100`；DILA0 base `0x5000`；DILA1 base `0x5100`。

每个模块均实现：

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

必须遵守统一页首部：

| offset | 名称 | 访问 | 说明 |
|---:|---|---|---|
| `+0x00` | `ID_VERSION` | RO | module ID/version |
| `+0x04` | `CONTROL` | RW/W1P | enable/soft reset/commit/clear FIFO |
| `+0x08` | `STATUS` | RO | ready/busy/overflow/error 等 |
| `+0x0C` | `ERROR` | RO/W1C | timeout/overflow/config/CDC/device/data format |

---

# 5. ADC 统一输出合同

AD4630 和 ADC3660 在完成器件物理采集后，都必须输出相同 `sample_stream`：

```verilog
output wire        s_valid;
input  wire        s_ready;
output wire [31:0] s_data;
output wire [7:0]  s_flags;
```

语义：

- 一个 handshake = 一个有效 ADC 样点；
- signed ADC 按二补码符号扩展到 32 bit；
- unsigned ADC 零扩展；
- `s_flags[0]` = overrange；
- `s_flags[1]` = ADC device error；
- 其余保留为 0；
- `s_valid=1 && s_ready=0` 时数据必须保持稳定。

**物理 ADC 不允许被 `s_ready` 停采。**

正确结构：

```text
ADC pins
   ↓
source synchronous / conversion capture
   ↓
local capture FIFO / CDC
   ↓
unified sample_stream
   ├── RAW path -> 项目负责人 adc_cycle_framer
   └── DILA path -> dila_core
```

FIFO 满必须：

1. `ERROR.OVERFLOW=1`；
2. `DROP_COUNT++`；
3. 不允许覆盖旧样点而无状态记录。

---

# 6. 子任务 A：AD4630 接口

## 6.1 目标

实现原位测量 ADC 的初始化/采样/数据捕获/统一输出。

必须根据实际板卡配置确认：

- 使用的 AD4630 工作模式；
- BUSY/CNV 时序；
- 串行数据 lane 数；
- SCLK/data edge；
- 输出编码；
- 最大/实际采样率。

## 6.2 最低功能

- enable/disable；
- 正确启动转换；
- BUSY/ready 处理；
- 正确采集一个完整 sample word；
- sample counter；
- BUSY timeout；
- FIFO overflow；
- soft reset；
- 可读当前采样率/状态。

## 6.3 必测

- 正常连续采样；
- 最小/最大目标采样率；
- BUSY 延迟变化；
- BUSY 永不释放；
- 下游长时间 backpressure；
- FIFO almost full/full；
- reset during idle；
- reset during conversion；
- 码值 0、满量程、符号边界、随机码。

必须提供 `ad4630_model.v` 或等效行为模型。

---

# 7. 子任务 B：ADC3660 接口

## 7.1 目标

完成遥测 ADC 的配置与 source-synchronous 数据接收。

ADC3660 是本任务时序风险最高部分。正式写数据拼接逻辑前，必须先提交：

`docs/adc3660_lane_map.md`

至少包含：

- FPGA ball ↔ schematic net ↔ ADC pin；
- DA/DB lane；
- DCLK/FCLK；
- DDR/SDR；
- 每 edge bit 定义；
- 一个 sample 的位拼接顺序；
- 数据编码；
- 当前器件 register mode；
- 依据的 datasheet 页码/表格。

**禁止根据网络名直接猜 lane 位序。**

## 7.2 时钟要求

- DCLK/FCLK 使用 FPGA I/O clocking 资源；
- 建立正确 input/generated clock；
- 数据捕获后通过异步 FIFO/明确 CDC 进入 `sys_clk`；
- 不允许把多 bit source-synchronous bus 直接逐 bit 双触发同步。

## 7.3 最低功能

- SPI/控制初始化（若项目硬件要求）；
- DCLK/FCLK 对齐；
- sample word 重组；
- frame/lane alignment error；
- capture FIFO；
- overflow/drop count；
- status counters；
- test-pattern 模式支持（如果 ADC3660 提供且项目配置允许，建议用于实机验收）。

## 7.4 必测

- 固定 pattern；
- walking-one/known ramp（若器件支持）；
- DDR 两边沿；
- frame slip/错位注入；
- DCLK stop/restart；
- backpressure/overflow；
- CDC reset；
- 目标采样率长期连续运行。

---

# 8. ADC 寄存器要求

## 8.1 ADC0 AD4630 `0x4000`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x4010` | `SAMPLE_RATE_REQ_HZ` | RW shadow | 请求采样率 |
| `0x4014` | `SAMPLE_RATE_ACT_HZ` | RO | 实际采样率 |
| `0x4018` | `SAMPLE_FORMAT` | RO | bit width/signed |
| `0x401C` | `EXPECTED_PER_CYCLE` | RW | 0=自动统计 |
| `0x4020` | `FIFO_LEVEL` | RO | capture FIFO |
| `0x4024` | `DROP_COUNT` | RO/W1C | 溢出样点数 |
| `0x4028` | `SAMPLE_COUNT_LO` | RO | 总采样数低32位 |
| `0x402C` | `SAMPLE_COUNT_HI` | RO | 总采样数高32位 |
| `0x4030` | `CNV_HIGH_TICKS` | RW | 转换脉冲相关 |
| `0x4034` | `BUSY_TIMEOUT_TICKS` | RW | BUSY超时阈值 |
| `0x4038` | `IF_MODE` | RW | 串行 lane 配置 |
| `0x403C` | `RAW_STREAM_ENABLE` | RW | raw 是否送项目级周期封装 |

## 8.2 ADC1 ADC3660 `0x4100`

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x4110` | `SAMPLE_RATE_REQ_HZ` | RW shadow | 请求输出/采样率 |
| `0x4114` | `SAMPLE_RATE_ACT_HZ` | RO | 实际采样率 |
| `0x4118` | `SAMPLE_FORMAT` | RO | 输出位宽/模式 |
| `0x411C` | `EXPECTED_PER_CYCLE` | RW | 0=自动 |
| `0x4120` | `FIFO_LEVEL` | RO | capture FIFO |
| `0x4124` | `DROP_COUNT` | RO/W1C | 溢出 |
| `0x4128` | `SAMPLE_COUNT_LO` | RO | 总样点低32位 |
| `0x412C` | `SAMPLE_COUNT_HI` | RO | 总样点高32位 |
| `0x4130` | `LANE_MODE` | RW | 与原理图/芯片配置一致 |
| `0x4134` | `DCLK_STATUS` | RO | clock detect |
| `0x4138` | `SYNC_COUNT` | RO | SYNC events |
| `0x413C` | `RAW_STREAM_ENABLE` | RW | raw stream |
| `0x4140` | `SPI_CLK_HZ` | RW | control SPI |

如需要 alignment/frame-error 计数，可从该页空闲 offset 扩展，但必须在 `REGISTER_MAP.md` 记录。

---

# 9. 子任务 C：DILA0/DILA1

## 9.1 总体目标

DILA 输入 ADC 样点，对 WMS 信号执行数字锁相/正交解调，得到 1f/2f I/Q，并经过固定结构低通滤波和抽取后形成标准 `DILA_BLOCK`。

要求使用一个参数化 `dila_core`，项目中实例化两次：

- DILA0：原位通道，`source_id=0x0030`；
- DILA1：遥测通道，`source_id=0x0031`。

## 9.2 DILA 输入接口

```verilog
input  wire        sys_clk;
input  wire        rst_sys_n;

input  wire        sample_valid;
output wire        sample_ready;
input  wire [31:0] sample_data;
input  wire [7:0]  sample_flags;

input  wire        wms_scan_start;
input  wire [31:0] wms_cycle_id;
input  wire [31:0] wms_sine_phase;
input  wire        wms_phase_valid;

input  wire [63:0] timestamp_now;
input  wire        time_sync_valid;
```

### WMS 相位定义

`wms_sine_phase` 使用 U32 phase：

- `0x00000000` = 0；
- `0x40000000` = π/2；
- `0x80000000` = π；
- `0xC0000000` = 3π/2；
- wrap = 2π。

成员1不得自定义不同相位方向/零点。

## 9.3 phase-lock 与 independent 模式

`MODE.bit0=1`：phase-lock-to-WMS，DILA 参考以 `wms_sine_phase` 为主参考；2f 为 2×phase + correction。

`MODE.bit0=0`：DILA 根据 `REF_FREQ_MHZ` 自己生成参考相位，用于测试/诊断。

两模式必须使用相同 Q 格式和 sin/cos 定义。

---

# 10. DILA 数学处理要求

## 10.1 参考生成 `dila_ref_gen`

至少输出：

- `sin_1f`；
- `cos_1f`；
- `sin_2f`；
- `cos_2f`。

Q 格式必须在 `docs/DILA_NUMERIC_FORMAT.md` 明确。推荐对称定点，例如 Q1.15/Q1.17/Q1.31，最终选择需结合 DSP 资源与误差分析。

必须说明：

- LUT/算法深度；
- 最大误差；
- 四象限处理；
- phase doubling wrap；
- `PHASE_1F_U32` 和 `PHASE_2F_CORR_U32` 的作用。

## 10.2 正交混频 `dila_mixer`

每个 ADC sample 计算：

```text
I1_raw = x * cos(1f)
Q1_raw = x * sin(1f)
I2_raw = x * cos(2f)
Q2_raw = x * sin(2f)
```

要求：

- 乘法保留 full precision；
- rounding/saturation 明确定义；
- 不允许无说明截断高位；
- 每类 saturation 可计数；
- 仿真需与 Python/MATLAB golden model 对比。

## 10.3 低通滤波 `dila_lpf`

V1.2 延续主指南：

- Butterworth；
- 阶数/结构/系数为 compile-time profile；
- `LPF_PROFILE` 只读；
- V1.2 不要求上位机在线写任意滤波系数。

必须在文档中冻结：

- 阶数；
- section 数；
- 系数值；
- 系数 Q 格式；
- accumulator 位宽；
- rounding；
- saturation；
- 输入采样率；
- 截止频率；
- 输出率。

## 10.4 抽取

根据 `OUTPUT_RATE_HZ` 产生 DILA 输出点。若 requested rate 与可实现整数抽取不完全一致：

- 必须暴露 ACTUAL rate 或在 README 说明换算规则；
- 不得静默使用完全不同的输出率。

---

# 11. DILA 周期和 timestamp 语义

DILA 必须以 WMS 周期为测量组织单位。

当 `wms_scan_start` 到来：

1. 结束上一 cycle 的 block；
2. 新 cycle 锁存 `wms_cycle_id`；
3. 锁存该周期 `timestamp_now`；
4. 后续 DILA 输出点属于该 cycle；
5. 若 cycle 内样点/输出点数量异常，flags 标记 `PARTIAL_DATA`。

同一通道：

```text
WMS cycle_id == RAW ADC cycle_id == DILA cycle_id
```

项目负责人负责 RAW `adc_cycle_framer`，你负责 DILA block 内 cycle/timestamp 关联。

---

# 12. DILA 输出 `msg_stream`

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

固定：

- DILA0 source `0x0030`；
- DILA1 source `0x0031`；
- `m_msg_id = 0x1001 (DILA_BLOCK)`。

`m_valid=1 && m_ready=0` 时全部字段保持。

`DILA_BLOCK` payload 格式严格遵守主开发指南第 4.4 节，不得私自改变字段顺序。

---

# 13. DILA 寄存器 `0x5000/0x5100`

每个 DILA 页必须实现：

| offset | 名称 | 访问 | 说明 |
|---:|---|---|---|
| `+0x10` | `REF_FREQ_MHZ` | RW shadow | 独立模式基频，0.001 Hz |
| `+0x14` | `PHASE_1F_U32` | RW shadow | 1f 相位 |
| `+0x18` | `PHASE_2F_CORR_U32` | RW shadow | 2f 修正 |
| `+0x1C` | `OUTPUT_RATE_HZ` | RW shadow | 解调输出率 |
| `+0x20` | `MODE` | RW shadow | bit0 phase-lock；bit1 magnitude；bit2 bypass |
| `+0x24` | `LPF_PROFILE` | RO | 固定滤波 profile |
| `+0x28` | `DATA_Q_FORMAT` | RO | 输出定点格式说明 |
| `+0x2C` | `IN_SAT_COUNT` | RO/W1C | 输入饱和 |
| `+0x30` | `MIX_SAT_COUNT` | RO/W1C | 混频饱和 |
| `+0x34` | `LPF_SAT_COUNT` | RO/W1C | 滤波饱和 |
| `+0x38` | `OUT_COUNT` | RO | 输出点数 |
| `+0x3C` | `FIFO_LEVEL` | RO | 输出 FIFO level |

DILA shadow 参数在 WMS 周期边界 commit；不得在一个扫描周期中途切换处理参数。

---

# 14. DILA 必须完成的验证

## 14.1 数学 golden test

使用 Python/MATLAB 生成至少以下输入：

1. 纯 1f；
2. 纯 2f；
3. 1f+2f；
4. 叠加 DC；
5. 叠加白噪声；
6. 相位偏移；
7. 幅值接近满量程；
8. WMS phase wrap；
9. cycle boundary；
10. 随机组合。

RTL 输出必须与 golden reference 逐点/容差比较，容差来源于定点量化分析，不允许只“看波形差不多”。

## 14.2 背压

- DILA output ready 间歇拉低；
- 长时间拉低直至 FIFO almost full；
- FIFO overflow；
- 恢复后 block 边界仍正确。

## 14.3 双通道

DILA0/DILA1 独立 enable、独立配置、不同参考频率/phase correction 时互不干扰。

---

# 15. 成员2 WMS stub 合同

如果成员2尚未交付，可在 `sim/stubs/wms_ref_stub.v` 使用完全相同端口产生：

- `scan_start`；
- `cycle_id`；
- `sine_phase`；
- `phase_valid`。

stub 只能用于仿真，不得进入正式 `rtl/`。

---

# 16. XDC/时序要求

你只提交：

`constraints/member1_adc_dila.xdc`

内容包括：

- AD4630 输入/控制相关约束；
- ADC3660 DCLK/FCLK/data lane input timing；
- generated/source clock；
- 必要 false path/max delay/CDC 说明；
- 不得包含其他成员 pins。

DILA 是 `sys_clk` 逻辑，不应通过 false path 逃避真实 timing 问题。

---

# 17. 最终交付目录

```text
member1_adc_dila/
├── README.md
├── rtl/
│   ├── adc_ad4630_if.v
│   ├── adc_adc3660_if.v
│   ├── adc_capture_fifo.v / FIFO wrapper
│   ├── adc_stream_fanout.v
│   ├── dila_core.v
│   ├── dila_ref_gen.v
│   ├── dila_mixer.v
│   ├── dila_lpf.v
│   ├── dila_decimator.v
│   └── dila_block_framer.v
├── sim/
│   ├── tb/
│   │   ├── tb_adc_ad4630_if.v
│   │   ├── tb_adc_adc3660_if.v
│   │   ├── tb_dila_core.v
│   │   └── tb_adc_dila_e2e.v
│   ├── models/
│   ├── vectors/
│   └── stubs/wms_ref_stub.v
├── constraints/member1_adc_dila.xdc
├── scripts/run_sim.tcl
├── scripts/run_synth_check.tcl
├── reports/SIM_REPORT.md
├── reports/SYNTH_REPORT.md
├── reports/TIMING_CDC_NOTES.md
└── docs/
    ├── INTERFACE.md
    ├── REGISTER_MAP.md
    ├── HARDWARE_MAPPING.md
    ├── adc3660_lane_map.md
    ├── DILA_NUMERIC_FORMAT.md
    ├── DILA_FILTER_PROFILE.md
    └── KNOWN_ISSUES.md
```

---

# 18. 最终验收标准

本任务只有同时满足以下条件才视为完成：

- [ ] AD4630 正常连续采样仿真 PASS；
- [ ] ADC3660 lane/DDR/FCLK 数据重组 PASS；
- [ ] 两路 ADC 均输出统一 `sample_stream`；
- [ ] 下游 backpressure 不会直接停 ADC；
- [ ] FIFO overflow 可检测/计数；
- [ ] DILA 1f/2f I/Q 与 golden model 在冻结误差内一致；
- [ ] DILA phase-lock-to-WMS PASS；
- [ ] DILA independent mode PASS；
- [ ] 周期边界/cycle_id/timestamp 正确；
- [ ] DILA `msg_stream` 背压 PASS；
- [ ] 双通道并行 PASS；
- [ ] Vivado synthesis PASS；
- [ ] ADC3660 timing/CDC 说明完整；
- [ ] 项目负责人无需修改内部 RTL 即可实例化。
