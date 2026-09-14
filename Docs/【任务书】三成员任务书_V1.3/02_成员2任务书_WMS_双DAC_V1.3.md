# 成员2 FPGA 开发任务书——双路 WMS + 双 AD5791 DAC

> 文档版本：V1.3  
> 开发环境：Xilinx Vivado  
> RTL：Verilog-2001  
> FPGA：Xilinx XCKU11P-2FFVA1156I  
> 任务定位：只负责完整“WMS参数 → 锯齿+正弦波形 → DAC码 → AD5791物理输出”链路。**不负责任何传感器。**

---

# 1. 最终任务范围

你正式负责：

1. `wms_wavegen.v` —— 单通道可参数化 WMS；
2. WMS 正弦发生模块 `sine_lut.v` 或等效确定性实现；
3. `dac_ad5791_if.v` —— 单通道可参数化 AD5791 transport；
4. WMS0→DAC0 和 WMS1→DAC1 两条完整链；
5. `scan_start/cycle_id/sine_phase` 系统参考接口；
6. WMS/DAC 的寄存器、shadow/commit、安全更新；
7. testbench、DAC model、golden vectors、XDC fragment、Vivado 脚本和文档。

建议正式 RTL：

```text
rtl/
├── wms_wavegen.v
├── sine_lut.v
├── dac_ad5791_if.v
├── wms_dac_channel.v      # 推荐，用于单通道完整封装
└── fixed_point_helpers.v  # 如确有需要
```

`wms_wavegen` 和 `dac_ad5791_if` 必须是单通道可复用模块，不能把 WMS0/WMS1 写死在一个不可复用的大状态机里。

---

# 2. 明确不属于你的任务

- ADC；
- DILA；
- UART；
- PTB/HMP/EPSILON/BMP/SHT/TFA/RD105；
- time sync；
- USB；
- project packetizer；
- stepper；
- 顶层和最终总 XDC。

你的正式对接对象只有：

1. 项目负责人提供的 cfg/time/reset；
2. AD5791 物理引脚；
3. 向成员1/项目负责人提供冻结 WMS reference signals。

---

# 3. 必须阅读资料

1. `FPGA下位机Verilog开发指南_V1.1.md`；
2. `FPGA下位机详细架构与接口分配方案_V1.1.md`；
3. `Docs/下位机需求分析.md`；
4. 板卡原理图；
5. XCKU11P UCF；
6. Analog Devices AD5791 官方 datasheet；
7. 项目 WMS/DILA 参数说明。

特别注意：最终 WMS 可实现频率和每周期点数受 AD5791 SPI 持续更新率约束。不得只按数学公式生成很高 sample rate，而忽略 DAC transport 实际吞吐。

---

## 3.1 本任务冻结 FPGA 物理引脚

### AD5791-0（原位，模拟输出到 CON7）

| net | FPGA ball |
|---|---:|
| `DAC_AD5791_0_SCLK` | K21 |
| `DAC_AD5791_0_RSTN` | M21 |
| `DAC_AD5791_0_SYNCN` | K25 |
| `DAC_AD5791_0_SDIN` | L24 |
| `DAC_AD5791_0_SDO` | L27 |
| `DAC_AD5791_0_CLRN` | H24 |
| `DAC_AD5791_0_LDACN` | H27 |

### AD5791-1（遥测，模拟输出到 CON8）

| net | FPGA ball |
|---|---:|
| `DAC_AD5791_1_SCLK` | R22 |
| `DAC_AD5791_1_RSTN` | G26 |
| `DAC_AD5791_1_SYNCN` | J26 |
| `DAC_AD5791_1_SDIN` | G27 |
| `DAC_AD5791_1_SDO` | H26 |
| `DAC_AD5791_1_CLRN` | J24 |
| `DAC_AD5791_1_LDACN` | H23 |

# 4. 统一 `cfg_bus`

WMS0 `0x2000`；WMS1 `0x2100`；DAC0 `0x3000`；DAC1 `0x3100`。

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

统一页首部 `ID_VERSION/CONTROL/STATUS/ERROR` 不得更改。

WMS参数使用 shadow registers；`commit` 后只能在安全边界切换 active 参数。

---

# 5. WMS 数学定义

每个 DAC update 产生一个归一化 Q1.31 有符号样点：

```text
wave = offset + saw_ampl * saw(phase_saw)
              + sine_ampl * sin(phase_sine + phase0)
```

冻结定义：

- `phase_saw`：U32；一个 wrap = 一个锯齿周期；
- `phase_sine`：U32；一个 wrap = 一个正弦周期；
- `saw_q31 = signed(phase_saw - 0x80000000)`；
- 正弦输出 Q1.31；
- amplitude/offset 均 Q1.31；
- 乘法中间值至少 64 bit；
- 回到 Q1.31 时必须定义 rounding；
- 多项相加使用扩展位；
- 超范围采用饱和，不允许 wrap；
- `SAT_COUNT` 统计每次饱和。

---

# 6. DDS 与更新节拍

建议 32-bit phase accumulator：

```text
phase_inc = round(freq_hz / dac_update_hz * 2^32)
```

要求：

- 锯齿与正弦频率独立配置；
- WMS0/WMS1 独立配置；
- DAC update tick 必须可预测；
- `DAC_UPDATE_HZ_REQ` 与 `DAC_UPDATE_HZ_ACT` 分开；
- 如果请求频率无法实现，commit 返回 config error 或用明确规则量化并暴露 ACT 值；
- 禁止默默改变 WMS 频率。

---

# 7. WMS→DAC 流接口

推荐：

```verilog
output wire [31:0] dac_sample;
output wire        dac_sample_valid;
input  wire        dac_sample_ready;
```

规则：

- handshake 后样点才被 DAC transport 接受；
- 若下一 update tick 到来时上一样点仍未接受，置 `UPDATE_OVERRUN`；
- 不得静默 drop；
- WMS 配置在 commit 时检查所需 update rate 是否超过当前 AD5791 transport 能力。

---

# 8. 向系统输出的 WMS reference 接口

每路必须输出：

```verilog
output wire        scan_start;
output wire [31:0] cycle_id;
output wire [31:0] sine_phase;
output wire        wms_running;
output wire        phase_valid;
```

## 8.1 `scan_start`

- 在新锯齿周期起点产生；
- 宽度严格 1 个 `sys_clk`；
- 不能因为 DAC SPI 事务长度产生多个脉冲。

## 8.2 `cycle_id`

- 复位后从 0 开始；
- 每个正式 scan 周期 +1；
- 在 `scan_start` 有效拍已代表新周期 ID；
- stop/start 后是否连续计数由 CONTROL 定义，V1.3 推荐除 soft reset 外持续递增。

## 8.3 `sine_phase`

U32：

- `0` = 0；
- `0x40000000` = π/2；
- `0x80000000` = π；
- `0xC0000000` = 3π/2。

该接口供成员1 DILA 锁相。必须在 `INTERFACE.md` 明确 phase 对应的是当前 reference phase，而不是 DAC SPI shift register 的内部状态。

---

# 9. WMS 寄存器 `0x2000/0x2100`

以下 `BASE` 分别为 `0x2000/0x2100`：

| offset | 名称 | R/W | 说明 |
|---:|---|---|---|
| `+0x10` | `SAW_FREQ_MHZ` | RW shadow | 单位0.001 Hz |
| `+0x14` | `SAW_AMPL_Q31` | RW shadow | Q1.31 |
| `+0x18` | `SAW_OFFSET_Q31` | RW shadow | Q1.31 |
| `+0x1C` | `SINE_FREQ_MHZ` | RW shadow | 单位0.001 Hz |
| `+0x20` | `SINE_AMPL_Q31` | RW shadow | Q1.31 |
| `+0x24` | `SINE_PHASE_U32` | RW shadow | U32 phase |
| `+0x28` | `DAC_UPDATE_HZ_REQ` | RW shadow | 请求更新率 |
| `+0x2C` | `DAC_UPDATE_HZ_ACT` | RO | 实际更新率 |
| `+0x30` | `CYCLE_ID` | RO | 当前 cycle |
| `+0x34` | `LAST_SCAN_TICK_LO` | RO | 周期开始 timestamp 低32位 |
| `+0x38` | `LAST_SCAN_TICK_HI` | RO | 周期开始 timestamp 高32位 |
| `+0x3C` | `SAT_COUNT` | RO/W1C | 限幅次数 |
| `+0x40` | `PHASE_MODE` | RW | bit0连续相位；bit1 commit重置phase |

若新增 `UPDATE_OVERRUN_COUNT` 等诊断寄存器，只能使用空闲 offset 并记录。

---

# 10. AD5791 transport

## 10.1 物理目标

两颗 AD5791：

- DAC0 → 原位激光驱动，模拟输出经 CON7；
- DAC1 → 遥测激光驱动，模拟输出经 CON8。

每路处理：

- SCLK；
- SYNCN；
- SDIN；
- SDO（若读回）；
- RSTN；
- CLRN；
- LDACN。

具体 FPGA ball 以原理图/UCF/主架构文档为准，并在 `HARDWARE_MAPPING.md` 逐项列出。

## 10.2 功能

- 初始化；
- 正确生成 AD5791 24-bit frame；
- 更新 DAC register；
- LDAC 策略固定并文档化；
- reset/clear；
- DAC code 限幅；
- 可选 readback；
- SPI busy/ready；
- 统计传输次数/异常。

## 10.3 输入 code 映射

WMS Q1.31 不能直接裸截断成 DAC code。必须经过明确映射：

```text
Q1.31 normalized wave
       ↓
user scale / offset / allowed output window
       ↓
saturate to DAC_MIN_CODE ... DAC_MAX_CODE
       ↓
AD5791 binary code
```

必须在 `docs/DAC_CODE_MAPPING.md` 给出公式和至少 5 个例子：

- -1；
- -0.5；
- 0；
- +0.5；
- 最大正值。

---

# 11. DAC 寄存器 `0x3000/0x3100`

| offset | 名称 | R/W | 说明 |
|---:|---|---|---|
| `+0x10` | `DEVICE_CTRL` | RW shadow | AD5791控制寄存器镜像 |
| `+0x14` | `CLEAR_CODE` | RW | clear code |
| `+0x18` | `DAC_MIN_CODE` | RW | 软件限幅下界 |
| `+0x1C` | `DAC_MAX_CODE` | RW | 软件限幅上界 |
| `+0x20` | `LAST_CODE` | RO | 最近写入code |
| `+0x24` | `SPI_CLK_HZ` | RW | SPI时钟目标 |
| `+0x28` | `WRITE_COUNT` | RO | 写样点数 |
| `+0x2C` | `SPI_ERROR_COUNT` | RO | timeout/readback error |
| `+0x30` | `DEVICE_ID_RAW` | RO | 若支持读回 |

---

# 12. shadow + commit 行为

WMS相关参数不能在一个扫描周期中途改变。

推荐流程：

1. host 写 shadow；
2. `CONTROL.commit`；
3. 模块校验：频率、幅值、DAC update 能力、code limit；
4. 合法则设置 `cfg_pending`；
5. 在下一安全 scan boundary 原子复制到 active；
6. 清 `cfg_pending`；
7. 新周期使用新参数。

DAC 纯 transport 参数若改变 SPI divider，也应仅在无进行中 transaction 时生效。

---

# 13. 必须完成的仿真

## 13.1 WMS 数值测试

至少：

- saw only；
- sine only；
- saw+sine；
- offset；
- positive/negative saturation；
- phase=0/π/2/π/3π/2；
- phase wrap；
- frequency change commit；
- WMS0/1 不同参数同时运行。

Python/MATLAB golden vector 与 RTL 定点输出逐点比较。

## 13.2 DAC model

必须有 `ad5791_model.v` 或等效：

- 检查 24-bit frame；
- 检查 SYNC/SCLK edge；
- reconstruct DAC register；
- reset/clear；
- 连续更新。

## 13.3 端到端

至少仿真：

```text
WMS config
  ↓
wms_wavegen
  ↓
Q1.31 -> DAC code
  ↓
dac_ad5791_if
  ↓
AD5791 model
```

同时检查 `scan_start/cycle_id/sine_phase`。

## 13.4 边界/异常

- DAC `ready` 延迟；
- update overrun；
- 请求 update rate 超过能力；
- commit 正好发生在周期中部；
- reset during SPI；
- stop/start；
- DAC code limit。

---

# 14. 时序/XDC

提交：

`constraints/member2_wms_dac.xdc`

仅包含两颗 AD5791 相关 FPGA pins 和必要 SPI I/O timing。WMS 内部为 `sys_clk` 逻辑。

不得修改其他成员引脚或项目总 XDC。

---

# 15. 最终交付目录

```text
member2_wms_dac/
├── README.md
├── rtl/
│   ├── wms_wavegen.v
│   ├── sine_lut.v
│   ├── dac_ad5791_if.v
│   └── wms_dac_channel.v
├── sim/
│   ├── tb/
│   │   ├── tb_wms_wavegen.v
│   │   ├── tb_dac_ad5791_if.v
│   │   └── tb_wms_dac_e2e.v
│   ├── models/ad5791_model.v
│   └── vectors/
├── constraints/member2_wms_dac.xdc
├── scripts/run_sim.tcl
├── scripts/run_synth_check.tcl
├── reports/SIM_REPORT.md
├── reports/SYNTH_REPORT.md
├── reports/TIMING_CDC_NOTES.md
└── docs/
    ├── INTERFACE.md
    ├── REGISTER_MAP.md
    ├── HARDWARE_MAPPING.md
    ├── WMS_NUMERIC_FORMAT.md
    ├── DAC_CODE_MAPPING.md
    ├── MAX_UPDATE_RATE.md
    └── KNOWN_ISSUES.md
```

---

# 16. 最终验收标准

- [ ] WMS0/WMS1 可独立 enable/config；
- [ ] saw/sine/offset/gain/phase 定点输出正确；
- [ ] saturation 正确且有 counter；
- [ ] shadow/commit 只在安全边界生效；
- [ ] 两颗 AD5791 transport PASS；
- [ ] WMS→DAC model 端到端 PASS；
- [ ] update rate 超限不会静默丢样；
- [ ] `scan_start` 每周期仅一次；
- [ ] `cycle_id` 正确；
- [ ] `sine_phase` 定义与成员1合同一致；
- [ ] Vivado synthesis PASS；
- [ ] 项目负责人无需修改内部 RTL 即可实例化。
