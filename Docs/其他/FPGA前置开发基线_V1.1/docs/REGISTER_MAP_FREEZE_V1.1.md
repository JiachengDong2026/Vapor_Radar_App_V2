# FPGA 下位机寄存器地址冻结表 V1.1

> 状态：FROZEN  
> 总线：`cfg_bus`, 32-bit address / 32-bit data  
> 每模块：0x100 B 地址页  
> 本版本取代 V1.0，并新增 DILA fragment 与 STREAM/BUFFER 仲裁相关寄存器。

## 1. 地址页

| Base | 模块 | 责任人 |
|---:|---|---|
| `0x0000` | SYSTEM | 项目负责人 |
| `0x0100` | CLOCK/RESET | 项目负责人 |
| `0x1000` | TIME_SYNC | 项目负责人 |
| `0x2000` | WMS0 | 成员2 |
| `0x2100` | WMS1 | 成员2 |
| `0x3000` | DAC0 AD5791 | 成员2 |
| `0x3100` | DAC1 AD5791 | 成员2 |
| `0x4000` | ADC0 AD4630 | 成员1 |
| `0x4100` | ADC1 ADC3660 | 成员1 |
| `0x5000` | DILA0 | 成员1 |
| `0x5100` | DILA1 | 成员1 |
| `0x6000` | PTB210 | 成员3 |
| `0x6100` | HMP | 成员3 |
| `0x6200` | EPSILON2 | 成员3 |
| `0x6300` | BMP390 | 成员3 |
| `0x6400` | SHT45 | 成员3 |
| `0x6500` | TFA1500-L | 成员3 |
| `0x6600` | RD105 | 成员3 |
| `0x6700` | STEPPER | 项目负责人 |
| `0x7000` | STREAM/BUFFER | 项目负责人 |
| `0x8000` | USB/GPIF | 项目负责人 |

## 2. 每页公共首部

| Offset | 名称 | 属性 | 说明 |
|---:|---|---|---|
| `+0x00` | ID_VERSION | RO | module/version |
| `+0x04` | CONTROL | RW/W1P | bit0 enable；bit1 soft_reset；bit2 commit；bit3 clear_fifo |
| `+0x08` | STATUS | RO | enabled/ready/cfg_pending/busy/online/FIFO/error/time_sync |
| `+0x0C` | ERROR | RO/W1C | 通用错误位 |

## 3. WMS0/1 (`0x2000/0x2100`)

与 V1.0 相同：

`+0x10 SAW_FREQ_MHZ`, `+0x14 SAW_AMPL_Q31`, `+0x18 SAW_OFFSET_Q31`, `+0x1C SINE_FREQ_MHZ`, `+0x20 SINE_AMPL_Q31`, `+0x24 SINE_PHASE_U32`, `+0x28 DAC_UPDATE_HZ_REQ`, `+0x2C DAC_UPDATE_HZ_ACT`, `+0x30 CYCLE_ID`, `+0x34/+0x38 LAST_SCAN_TICK`, `+0x3C SAT_COUNT`, `+0x40 PHASE_MODE`。

## 4. DAC0/1 AD5791 (`0x3000/0x3100`)

与 V1.0 相同：

`+0x10 DEVICE_CTRL`, `+0x14 CLEAR_CODE`, `+0x18 DAC_MIN_CODE`, `+0x1C DAC_MAX_CODE`, `+0x20 LAST_CODE`, `+0x24 SPI_CLK_HZ`, `+0x28 WRITE_COUNT`, `+0x2C SPI_ERROR_COUNT`, `+0x30 DEVICE_ID_RAW`。

## 5. ADC0/1 (`0x4000/0x4100`)

ADC 接口地址保持 V1.0 不变。ADC 对外正式成员接口仍为 `sample_stream`；RAW bulk fragment 由项目负责人 `adc_cycle_framer` 组织。

## 6. DILA0/1 (`0x5000/0x5100`)

| Offset | 名称 | 属性 | 说明 |
|---:|---|---|---|
| `+0x10` | REF_FREQ_MHZ | RW shadow | independent mode 基频 |
| `+0x14` | PHASE_1F_U32 | RW shadow | 1f phase offset |
| `+0x18` | PHASE_2F_CORR_U32 | RW shadow | 2f correction |
| `+0x1C` | OUTPUT_RATE_HZ | RW shadow | 曲线点输出率 |
| `+0x20` | MODE | RW shadow | lock/magnitude/bypass/format select |
| `+0x24` | LPF_PROFILE | RO | filter profile |
| `+0x28` | DATA_Q_FORMAT | RO | fixed-point description |
| `+0x2C` | IN_SAT_COUNT | RO/W1C | input saturation |
| `+0x30` | MIX_SAT_COUNT | RO/W1C | mixer saturation |
| `+0x34` | LPF_SAT_COUNT | RO/W1C | LPF saturation |
| `+0x38` | OUT_COUNT | RO | total output points |
| `+0x3C` | FIFO_LEVEL | RO | DILA bulk FIFO level |
| `+0x40` | FRAGMENT_POINTS | RW shadow | 默认 256；合法范围 1..256；每 fragment 最大点数 |
| `+0x44` | LAST_FRAGMENT_COUNT | RO | 最近周期生成的 fragment 数 |
| `+0x48` | DROP_COUNT | RO/W1C | 因 bulk FIFO 满等原因丢弃的 fragment/周期计数 |

规则：

- `FRAGMENT_POINTS` 在 WMS 周期边界 commit；
- 若某格式下 `header + fragment_points * bytes_per_point > 8192 B`，commit 必须失败并置 CONFIG_RANGE；
- 默认 `FRAGMENT_POINTS=256`。

## 7. Sensor pages (`0x6000-0x6600`)

各传感器原有地址保持 V1.0 不变。新增统一要求：每个 sensor driver 必须提供独立消息 FIFO 状态；若本页仍有空闲 offset，可在成员 README 中增加 `MSG_FIFO_LEVEL` 和 `MSG_DROP_COUNT`，但不得占用已有地址。若本页空间不足，由项目负责人统一新增诊断页，成员不得自行扩页。

## 8. STREAM/BUFFER (`0x7000`) —— V1.1 更新

| 地址 | 名称 | R/W | 说明 |
|---:|---|---|---|
| `0x7010` | ARB_MODE | RW | `0=RR`；`1=priority+RR+burst_cap`，正式默认 1 |
| `0x7014` | TX_FIFO_LEVEL | RO | packetizer 后 TX FIFO level |
| `0x7018` | TX_FIFO_HIGH_WATER | RW | TX almost-full threshold |
| `0x701C` | TOTAL_DROP_COUNT | RO/W1C | 全系统数据丢失统计 |
| `0x7020` | ADC0_FIFO_LEVEL | RO | RAW path 诊断 |
| `0x7024` | ADC1_FIFO_LEVEL | RO | RAW path 诊断 |
| `0x7028` | DILA0_FIFO_LEVEL | RO | DILA0 bulk FIFO |
| `0x702C` | DILA1_FIFO_LEVEL | RO | DILA1 bulk FIFO |
| `0x7030` | SENSOR_FIFO_LEVEL | RO | sensor hub 汇总/最大 FIFO level |
| `0x7034` | MAX_HIGH_BURST | RW | 默认 4；防 starvation 的连续高优先级 frame 上限 |
| `0x7038` | MSG_PENDING_MASK | RO | 当前低速消息源 pending bitmap |
| `0x703C` | BULK_PENDING_MASK | RO | 当前 DILA/RAW bulk 源 pending bitmap |
| `0x7040` | ARB_GRANT_COUNT_LO | RO | 总 grant count low |
| `0x7044` | ARB_GRANT_COUNT_HI | RO | 总 grant count high |

### 8.1 仲裁冻结语义

- 同级 RR；
- frame/fragment 锁定到 `last`；
- P0>P1>P2>P3；
- 若较低优先级持续 pending，连续完成 `MAX_HIGH_BURST` 个较高优先级 frame 后必须让出一次服务机会；
- Bulk 每次只授予 1 个 fragment，不授予整个 WMS 周期。

## 9. USB/GPIF (`0x8000`)

保持原定义。packetizer 的输入已在 V1.1 改为 arbiter 选中的统一 frame stream；USB 层无需理解各传感器原生协议。

## 10. 扩展规则

1. 不得重定义已冻结地址；
2. 新增 offset 必须 32-bit 对齐；
3. 新增寄存器必须说明 reset value、属性、单位、范围、commit 语义；
4. 多源缓存/仲裁相关寄存器统一放在 `0x7000` 页，不允许成员各自定义系统级仲裁地址；
5. `DILA FRAGMENT_POINTS` 是成员1唯一需要实现的新增正式配置项。
