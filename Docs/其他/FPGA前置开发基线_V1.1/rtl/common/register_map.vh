`ifndef VAPOR_LIDAR_REGISTER_MAP_VH
`define VAPOR_LIDAR_REGISTER_MAP_VH

// Module base addresses
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

// Common offsets
`define REG_OFS_ID_VERSION       8'h00
`define REG_OFS_CONTROL          8'h04
`define REG_OFS_STATUS           8'h08
`define REG_OFS_ERROR            8'h0C

// WMS offsets
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

// DAC offsets
`define REG_DAC_DEVICE_CTRL         8'h10
`define REG_DAC_CLEAR_CODE          8'h14
`define REG_DAC_MIN_CODE            8'h18
`define REG_DAC_MAX_CODE            8'h1C
`define REG_DAC_LAST_CODE           8'h20
`define REG_DAC_SPI_CLK_HZ          8'h24
`define REG_DAC_WRITE_COUNT         8'h28
`define REG_DAC_SPI_ERROR_COUNT     8'h2C
`define REG_DAC_DEVICE_ID_RAW       8'h30

// ADC0 AD4630 offsets
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

// ADC1 ADC3660 offsets
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

// DILA offsets
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

// STREAM/BUFFER offsets
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
