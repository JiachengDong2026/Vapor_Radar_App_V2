# FPGA 下位机寄存器地址冻结表 V1.0

> 状态：FROZEN  
> 总线：`cfg_bus`, 32-bit address / 32-bit data  
> 每模块：0x100 B 地址页  
> 端序：内部寄存器为 bit-vector；进入 USB payload 后统一 little-endian。

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

| Offset | 名称 | 属性 | 单位/含义 |
|---:|---|---|---|
| `+0x10` | SAW_FREQ_MHZ | RW shadow | 0.001 Hz |
| `+0x14` | SAW_AMPL_Q31 | RW shadow | Q1.31 |
| `+0x18` | SAW_OFFSET_Q31 | RW shadow | Q1.31 |
| `+0x1C` | SINE_FREQ_MHZ | RW shadow | 0.001 Hz |
| `+0x20` | SINE_AMPL_Q31 | RW shadow | Q1.31 |
| `+0x24` | SINE_PHASE_U32 | RW shadow | U0.32 turn |
| `+0x28` | DAC_UPDATE_HZ_REQ | RW shadow | requested |
| `+0x2C` | DAC_UPDATE_HZ_ACT | RO | actual |
| `+0x30` | CYCLE_ID | RO | current cycle |
| `+0x34` | LAST_SCAN_TICK_LO | RO | timestamp |
| `+0x38` | LAST_SCAN_TICK_HI | RO | timestamp |
| `+0x3C` | SAT_COUNT | RO/W1C | saturation count |
| `+0x40` | PHASE_MODE | RW | bit0 continuous phase；bit1 reset phase on commit |

## 4. DAC0/1 AD5791 (`0x3000/0x3100`)

| Offset | 名称 | 属性 | 说明 |
|---:|---|---|---|
| `+0x10` | DEVICE_CTRL | RW shadow | AD5791 control mirror |
| `+0x14` | CLEAR_CODE | RW | clear code |
| `+0x18` | DAC_MIN_CODE | RW | lower clamp |
| `+0x1C` | DAC_MAX_CODE | RW | upper clamp |
| `+0x20` | LAST_CODE | RO | last output code |
| `+0x24` | SPI_CLK_HZ | RW | target SPI clock |
| `+0x28` | WRITE_COUNT | RO | sample writes |
| `+0x2C` | SPI_ERROR_COUNT | RO | error count |
| `+0x30` | DEVICE_ID_RAW | RO | optional readback |

## 5. ADC0 AD4630 (`0x4000`)

| Address | 名称 | 属性 | 说明 |
|---:|---|---|---|
| `0x4010` | SAMPLE_RATE_REQ_HZ | RW shadow | requested |
| `0x4014` | SAMPLE_RATE_ACT_HZ | RO | actual |
| `0x4018` | SAMPLE_FORMAT | RO | width/signed |
| `0x401C` | EXPECTED_PER_CYCLE | RW | 0=auto |
| `0x4020` | FIFO_LEVEL | RO | capture FIFO |
| `0x4024` | DROP_COUNT | RO/W1C | dropped samples |
| `0x4028` | SAMPLE_COUNT_LO | RO | total |
| `0x402C` | SAMPLE_COUNT_HI | RO | total |
| `0x4030` | CNV_HIGH_TICKS | RW | device-specific |
| `0x4034` | BUSY_TIMEOUT_TICKS | RW | timeout |
| `0x4038` | IF_MODE | RW | serial lane config |
| `0x403C` | RAW_STREAM_ENABLE | RW | raw upload enable |

## 6. ADC1 ADC3660 (`0x4100`)

| Address | 名称 | 属性 | 说明 |
|---:|---|---|---|
| `0x4110` | SAMPLE_RATE_REQ_HZ | RW shadow | requested |
| `0x4114` | SAMPLE_RATE_ACT_HZ | RO | actual |
| `0x4118` | SAMPLE_FORMAT | RO | width/mode |
| `0x411C` | EXPECTED_PER_CYCLE | RW | 0=auto |
| `0x4120` | FIFO_LEVEL | RO | capture FIFO |
| `0x4124` | DROP_COUNT | RO/W1C | dropped samples |
| `0x4128` | SAMPLE_COUNT_LO | RO | total |
| `0x412C` | SAMPLE_COUNT_HI | RO | total |
| `0x4130` | LANE_MODE | RW | physical/output mode |
| `0x4134` | DCLK_STATUS | RO | clock detect |
| `0x4138` | SYNC_COUNT | RO | sync count |
| `0x413C` | RAW_STREAM_ENABLE | RW | raw upload enable |
| `0x4140` | SPI_CLK_HZ | RW | control SPI |

## 7. DILA0/1 (`0x5000/0x5100`)

| Offset | 名称 | 属性 | 说明 |
|---:|---|---|---|
| `+0x10` | REF_FREQ_MHZ | RW shadow | independent mode, 0.001 Hz |
| `+0x14` | PHASE_1F_U32 | RW shadow | phase offset |
| `+0x18` | PHASE_2F_CORR_U32 | RW shadow | 2f correction |
| `+0x1C` | OUTPUT_RATE_HZ | RW shadow | output rate |
| `+0x20` | MODE | RW shadow | bit0 lock_to_wms；bit1 magnitude；bit2 bypass |
| `+0x24` | LPF_PROFILE | RO | filter profile ID |
| `+0x28` | DATA_Q_FORMAT | RO | fixed-point description |
| `+0x2C` | IN_SAT_COUNT | RO/W1C | input saturation |
| `+0x30` | MIX_SAT_COUNT | RO/W1C | mixer saturation |
| `+0x34` | LPF_SAT_COUNT | RO/W1C | LPF saturation |
| `+0x38` | OUT_COUNT | RO | output count |
| `+0x3C` | FIFO_LEVEL | RO | output FIFO |

## 8. Sensor pages (`0x6000-0x6600`)

成员3必须保留各页公共首部，且使用以下已冻结的专用地址。详细语义以 `FPGA下位机Verilog开发指南_V1.0.md` 为准。

### PTB210 (`0x6000`)
`0x6010 BAUD`, `0x6014 UART_FORMAT`, `0x6018 POLL_INTERVAL_MS`, `0x601C MODE`, `0x6020 LAST_PRESSURE_MPA`, `0x6024 RX_FRAME_COUNT`, `0x6028 PARSE_ERROR_COUNT`, `0x602C TIMEOUT_MS`, `0x6030 DEVICE_ID_HASH`.

### HMP (`0x6100`)
`0x6110 BAUD`, `0x6114 MODBUS_ADDR`, `0x6118 SERIAL_FORMAT`, `0x611C POLL_INTERVAL_MS`, `0x6120 MEAS_MASK`, `0x6124 LAST_RH_F32_BITS`, `0x6128 LAST_TEMP_F32_BITS`, `0x612C MODBUS_CRC_ERR_COUNT`, `0x6130 MODBUS_TIMEOUT_COUNT`, `0x6134 PRESS_COMP_F32_BITS`.

### EPSILON2 (`0x6200`)
`0x6210 BAUD`, `0x6214 FDI_MSG_MASK_LO`, `0x6218 FDI_MSG_MASK_HI`, `0x621C RAW_FORWARD_ENABLE`, `0x6220 GOOD_FRAME_COUNT`, `0x6224 CRC_ERR_COUNT`, `0x6228 SYNC_EVENT_COUNT`, `0x622C LAST_FDI_MSG_ID`, `0x6230 LAST_GNSS_TIME_LO`, `0x6234 LAST_GNSS_TIME_HI`.

### BMP390 (`0x6300`)
`0x6310 I2C_ADDR`, `0x6314 POLL_INTERVAL_MS`, `0x6318 OSR_CFG`, `0x631C ODR_CFG`, `0x6320 IIR_CFG`, `0x6324 PWR_CTRL`, `0x6328 CHIP_ID`, `0x632C RAW_PRESSURE`, `0x6330 RAW_TEMPERATURE`, `0x6334 I2C_ERR_COUNT`, `0x6338 COMPENSATION_MODE`.

### SHT45 (`0x6400`)
`0x6410 I2C_ADDR`, `0x6414 POLL_INTERVAL_MS`, `0x6418 REPEATABILITY`, `0x641C HEATER_MODE`, `0x6420 RAW_TEMP`, `0x6424 RAW_RH`, `0x6428 CRC_ERR_COUNT`, `0x642C I2C_ERR_COUNT`, `0x6430 SERIAL_LO`, `0x6434 SERIAL_HI`.

### TFA1500-L (`0x6500`)
`0x6510 BAUD`, `0x6514 RANGE_MODE`, `0x6518 COMMAND`, `0x651C LAST_DISTANCE_MM`, `0x6520 DISTANCE_VALID`, `0x6524 APD_TEMP_RAW`, `0x6528 RX_FRAME_COUNT`, `0x652C CHECKSUM_ERR_COUNT`, `0x6530 HF_INVALID_COUNT`.

### RD105 (`0x6600`)
`0x6610 BAUD`, `0x6614 DEVICE_ADDR`, `0x6618 PROTOCOL_MODE`, `0x661C CHANNEL`, `0x6620 TARGET_TEMP_UC`, `0x6624 ACTUAL_TEMP_UC`, `0x6628 ERRORCODE`, `0x662C POLL_INTERVAL_MS`, `0x6630 CRC_ERR_COUNT`, `0x6634 TIMEOUT_COUNT`.

## 9. 扩展规则

1. 成员仅可在自己 0x100 B 页内新增未占用 offset；
2. 新增 offset 必须 32-bit 对齐；
3. 不得重定义已冻结地址；
4. 若 0x100 B 不够，必须向项目负责人申请新页；
5. 所有新增寄存器都要在模块 README 中给出 reset value、R/W 属性、单位、合法范围和 commit 语义。
