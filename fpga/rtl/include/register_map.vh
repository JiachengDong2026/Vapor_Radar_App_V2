`ifndef VAPOR_LIDAR_REGISTER_MAP_VH
`define VAPOR_LIDAR_REGISTER_MAP_VH

// -----------------------------------------------------------------------------
// Module base addresses. Each module owns one 0x100-byte page unless explicitly
// extended by a future document revision.
// -----------------------------------------------------------------------------
`define REG_BASE_SYSTEM          32'h0000_0000
`define REG_BASE_CLOCK_RESET     32'h0000_0100
`define REG_BASE_TIME_SYNC       32'h0000_1000
`define REG_BASE_WMS0            32'h0000_2000
`define REG_BASE_WMS1            32'h0000_2100
`define REG_BASE_DAC0            32'h0000_3000
`define REG_BASE_DAC1            32'h0000_3100
`define REG_BASE_ADC0            32'h0000_4000
`define REG_BASE_ADC1            32'h0000_4100
`define REG_BASE_DILA0           32'h0000_5000
`define REG_BASE_DILA1           32'h0000_5100
`define REG_BASE_PTB210          32'h0000_6000
`define REG_BASE_HMP             32'h0000_6100
`define REG_BASE_EPSILON2        32'h0000_6200
`define REG_BASE_BMP390          32'h0000_6300
`define REG_BASE_SHT45           32'h0000_6400
`define REG_BASE_TFA1500         32'h0000_6500
`define REG_BASE_RD105           32'h0000_6600
`define REG_BASE_STEPPER         32'h0000_6700
`define REG_BASE_STREAM          32'h0000_7000
`define REG_BASE_USB_GPIF        32'h0000_8000

// Common offsets.
`define REG_OFS_ID_VERSION       8'h00
`define REG_OFS_CONTROL          8'h04
`define REG_OFS_STATUS           8'h08
`define REG_OFS_ERROR            8'h0C

// Common CONTROL bits.
`define CTRL_BIT_ENABLE          0
`define CTRL_BIT_SOFT_RESET      1
`define CTRL_BIT_COMMIT          2
`define CTRL_BIT_CLEAR_FIFO      3

// Common STATUS bits.
`define STATUS_BIT_ENABLED       0
`define STATUS_BIT_READY         1
`define STATUS_BIT_CFG_PENDING   2
`define STATUS_BIT_BUSY          3
`define STATUS_BIT_ONLINE        4
`define STATUS_BIT_FIFO_AFULL    5
`define STATUS_BIT_OVERFLOW      6
`define STATUS_BIT_ERROR         7
`define STATUS_BIT_TIME_SYNC     8

// WMS offsets.
`define REG_WMS_SAW_FREQ_MHZ        8'h10
`define REG_WMS_SAW_AMPL_Q31        8'h14
`define REG_WMS_SAW_OFFSET_Q31      8'h18
`define REG_WMS_SINE_FREQ_MHZ       8'h1C
`define REG_WMS_SINE_AMPL_Q31       8'h20
`define REG_WMS_SINE_PHASE_U32      8'h24
`define REG_WMS_DAC_UPDATE_HZ_REQ   8'h28
`define REG_WMS_DAC_UPDATE_HZ_ACT   8'h2C
`define REG_WMS_CYCLE_ID            8'h30
`define REG_WMS_LAST_SCAN_TICK_LO   8'h34
`define REG_WMS_LAST_SCAN_TICK_HI   8'h38
`define REG_WMS_SAT_COUNT           8'h3C
`define REG_WMS_PHASE_MODE          8'h40

// DAC offsets.
`define REG_DAC_DEVICE_CTRL         8'h10
`define REG_DAC_CLEAR_CODE          8'h14
`define REG_DAC_MIN_CODE            8'h18
`define REG_DAC_MAX_CODE            8'h1C
`define REG_DAC_LAST_CODE           8'h20
`define REG_DAC_SPI_CLK_HZ          8'h24
`define REG_DAC_WRITE_COUNT         8'h28
`define REG_DAC_SPI_ERROR_COUNT     8'h2C
`define REG_DAC_DEVICE_ID_RAW       8'h30

// ADC0 AD4630 offsets.
`define REG_ADC0_SAMPLE_RATE_REQ_HZ 8'h10
`define REG_ADC0_SAMPLE_RATE_ACT_HZ 8'h14
`define REG_ADC0_SAMPLE_FORMAT      8'h18
`define REG_ADC0_EXPECTED_PER_CYCLE 8'h1C
`define REG_ADC0_FIFO_LEVEL         8'h20
`define REG_ADC0_DROP_COUNT         8'h24
`define REG_ADC0_SAMPLE_COUNT_LO    8'h28
`define REG_ADC0_SAMPLE_COUNT_HI    8'h2C
`define REG_ADC0_CNV_HIGH_TICKS     8'h30
`define REG_ADC0_BUSY_TIMEOUT_TICKS 8'h34
`define REG_ADC0_IF_MODE            8'h38
`define REG_ADC0_RAW_STREAM_ENABLE  8'h3C

// ADC1 ADC3660 offsets.
`define REG_ADC1_SAMPLE_RATE_REQ_HZ 8'h10
`define REG_ADC1_SAMPLE_RATE_ACT_HZ 8'h14
`define REG_ADC1_SAMPLE_FORMAT      8'h18
`define REG_ADC1_EXPECTED_PER_CYCLE 8'h1C
`define REG_ADC1_FIFO_LEVEL         8'h20
`define REG_ADC1_DROP_COUNT         8'h24
`define REG_ADC1_SAMPLE_COUNT_LO    8'h28
`define REG_ADC1_SAMPLE_COUNT_HI    8'h2C
`define REG_ADC1_LANE_MODE          8'h30
`define REG_ADC1_DCLK_STATUS        8'h34
`define REG_ADC1_SYNC_COUNT         8'h38
`define REG_ADC1_RAW_STREAM_ENABLE  8'h3C
`define REG_ADC1_SPI_CLK_HZ         8'h40

// DILA offsets.
`define REG_DILA_REF_FREQ_MHZ       8'h10
`define REG_DILA_PHASE_1F_U32       8'h14
`define REG_DILA_PHASE_2F_CORR_U32  8'h18
`define REG_DILA_OUTPUT_RATE_HZ     8'h1C
`define REG_DILA_MODE               8'h20
`define REG_DILA_LPF_PROFILE        8'h24
`define REG_DILA_DATA_Q_FORMAT      8'h28
`define REG_DILA_IN_SAT_COUNT       8'h2C
`define REG_DILA_MIX_SAT_COUNT      8'h30
`define REG_DILA_LPF_SAT_COUNT      8'h34
`define REG_DILA_OUT_COUNT          8'h38
`define REG_DILA_FIFO_LEVEL         8'h3C
`define REG_DILA_FRAGMENT_POINTS    8'h40
`define REG_DILA_FRAGMENT_COUNT     8'h44
`define REG_DILA_DROP_COUNT         8'h48

// PTB210 offsets.
`define REG_PTB_BAUD                8'h10
`define REG_PTB_UART_FORMAT         8'h14
`define REG_PTB_POLL_INTERVAL_MS    8'h18
`define REG_PTB_MODE                8'h1C
`define REG_PTB_LAST_PRESSURE_MPA   8'h20
`define REG_PTB_RX_FRAME_COUNT      8'h24
`define REG_PTB_PARSE_ERROR_COUNT   8'h28
`define REG_PTB_TIMEOUT_MS          8'h2C
`define REG_PTB_DEVICE_ID_HASH      8'h30
`define REG_PTB_FIFO_LEVEL          8'h34
`define REG_PTB_DROP_COUNT          8'h38

// HMP offsets.
`define REG_HMP_BAUD                8'h10
`define REG_HMP_MODBUS_ADDR         8'h14
`define REG_HMP_SERIAL_FORMAT       8'h18
`define REG_HMP_POLL_INTERVAL_MS    8'h1C
`define REG_HMP_MEAS_MASK           8'h20
`define REG_HMP_LAST_RH_F32_BITS    8'h24
`define REG_HMP_LAST_TEMP_F32_BITS  8'h28
`define REG_HMP_CRC_ERR_COUNT       8'h2C
`define REG_HMP_TIMEOUT_COUNT       8'h30
`define REG_HMP_PRESS_COMP_F32_BITS 8'h34
`define REG_HMP_FIFO_LEVEL          8'h38
`define REG_HMP_DROP_COUNT          8'h3C

// EPSILON2 offsets.
`define REG_EPS_BAUD                8'h10
`define REG_EPS_FDI_MSG_MASK_LO     8'h14
`define REG_EPS_FDI_MSG_MASK_HI     8'h18
`define REG_EPS_RAW_FORWARD_ENABLE  8'h1C
`define REG_EPS_GOOD_FRAME_COUNT    8'h20
`define REG_EPS_CRC_ERR_COUNT       8'h24
`define REG_EPS_SYNC_EVENT_COUNT    8'h28
`define REG_EPS_LAST_FDI_MSG_ID     8'h2C
`define REG_EPS_LAST_GNSS_TIME_LO   8'h30
`define REG_EPS_LAST_GNSS_TIME_HI   8'h34
`define REG_EPS_FIFO_LEVEL          8'h38
`define REG_EPS_DROP_COUNT          8'h3C

// BMP390 offsets.
`define REG_BMP_I2C_ADDR            8'h10
`define REG_BMP_POLL_INTERVAL_MS    8'h14
`define REG_BMP_OSR_CFG             8'h18
`define REG_BMP_ODR_CFG             8'h1C
`define REG_BMP_IIR_CFG             8'h20
`define REG_BMP_PWR_CTRL            8'h24
`define REG_BMP_CHIP_ID             8'h28
`define REG_BMP_RAW_PRESSURE        8'h2C
`define REG_BMP_RAW_TEMPERATURE     8'h30
`define REG_BMP_I2C_ERR_COUNT       8'h34
`define REG_BMP_COMPENSATION_MODE   8'h38
`define REG_BMP_FIFO_LEVEL          8'h3C
`define REG_BMP_DROP_COUNT          8'h40

// SHT45 offsets.
`define REG_SHT_I2C_ADDR            8'h10
`define REG_SHT_POLL_INTERVAL_MS    8'h14
`define REG_SHT_REPEATABILITY       8'h18
`define REG_SHT_HEATER_MODE         8'h1C
`define REG_SHT_RAW_TEMP            8'h20
`define REG_SHT_RAW_RH              8'h24
`define REG_SHT_CRC_ERR_COUNT       8'h28
`define REG_SHT_I2C_ERR_COUNT       8'h2C
`define REG_SHT_SERIAL_LO           8'h30
`define REG_SHT_SERIAL_HI           8'h34
`define REG_SHT_FIFO_LEVEL          8'h38
`define REG_SHT_DROP_COUNT          8'h3C

// TFA1500-L offsets.
`define REG_TFA_BAUD                8'h10
`define REG_TFA_RANGE_MODE          8'h14
`define REG_TFA_COMMAND             8'h18
`define REG_TFA_LAST_DISTANCE_MM    8'h1C
`define REG_TFA_DISTANCE_VALID      8'h20
`define REG_TFA_APD_TEMP_RAW        8'h24
`define REG_TFA_RX_FRAME_COUNT      8'h28
`define REG_TFA_CHECKSUM_ERR_COUNT  8'h2C
`define REG_TFA_HF_INVALID_COUNT    8'h30
`define REG_TFA_FIFO_LEVEL          8'h34
`define REG_TFA_DROP_COUNT          8'h38

// RD105 offsets.
`define REG_RD105_BAUD              8'h10
`define REG_RD105_DEVICE_ADDR       8'h14
`define REG_RD105_PROTOCOL_MODE     8'h18
`define REG_RD105_CHANNEL           8'h1C
`define REG_RD105_TARGET_TEMP_UC    8'h20
`define REG_RD105_ACTUAL_TEMP_UC    8'h24
`define REG_RD105_ERRORCODE         8'h28
`define REG_RD105_POLL_INTERVAL_MS  8'h2C
`define REG_RD105_CRC_ERR_COUNT     8'h30
`define REG_RD105_TIMEOUT_COUNT     8'h34
`define REG_RD105_FIFO_LEVEL        8'h38
`define REG_RD105_DROP_COUNT        8'h3C

// STREAM/BUFFER offsets.
`define REG_STREAM_ARB_MODE             8'h10
`define REG_STREAM_TX_FIFO_LEVEL        8'h14
`define REG_STREAM_TX_FIFO_HIGH_WATER   8'h18
`define REG_STREAM_TOTAL_DROP_COUNT     8'h1C
`define REG_STREAM_ADC0_FIFO_LEVEL      8'h20
`define REG_STREAM_ADC1_FIFO_LEVEL      8'h24
`define REG_STREAM_DILA0_FIFO_LEVEL     8'h28
`define REG_STREAM_DILA1_FIFO_LEVEL     8'h2C
`define REG_STREAM_SENSOR_FIFO_LEVEL    8'h30
`define REG_STREAM_MAX_HIGH_BURST       8'h34
`define REG_STREAM_MSG_PENDING_MASK     8'h38
`define REG_STREAM_BULK_PENDING_MASK    8'h3C
`define REG_STREAM_ARB_GRANT_COUNT_LO   8'h40
`define REG_STREAM_ARB_GRANT_COUNT_HI   8'h44

`endif
