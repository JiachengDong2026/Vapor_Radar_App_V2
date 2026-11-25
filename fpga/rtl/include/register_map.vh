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
`define REG_BASE_HC2A            `REG_BASE_HMP
`define REG_BASE_EPSILON2        32'h0000_6200
`define REG_BASE_BMP390          32'h0000_6300
`define REG_BASE_SHT45           32'h0000_6400
`define REG_BASE_SDFM300         32'h0000_6500
`define REG_BASE_AI8             32'h0000_6600
`define REG_BASE_RD105           32'h0000_6A00 // Independent RD105 page; LC0 remains 6800.
// Independent raw TTL UART pages for the two LC laser controllers.
`define REG_BASE_LC0             32'h0000_6800
`define REG_BASE_LC1             32'h0000_6900
`define REG_LC_BAUD              8'h10
`define REG_LC_FORMAT            8'h14
`define REG_LC_TX_DATA           8'h18
`define REG_LC_RX_DATA           8'h1C
`define REG_LC_TX_LEVEL          8'h20
`define REG_LC_RX_LEVEL          8'h24
`define REG_LC_TX_COUNT          8'h28
`define REG_LC_RX_COUNT          8'h2C
`define REG_LC_DROP_COUNT        8'h30
`define REG_LC_PARITY_COUNT      8'h34
`define REG_LC_FRAMING_COUNT     8'h38
`define REG_LC_FIFO_DEPTH        8'h3C

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

// ADC1 offsets. Formal DUAL_AD4630=1: AD4630 CH1, 24-bit shared-rate.
// +10/+14 read the ADC0 active rate; +30/+34 read shared CNV/timeout.
// +38 reads MODES=0x80; +40 is absent. Legacy ADC3660 aliases below remain.
`define ADC_DUAL_AD4630_ID0        32'h0020_0101
`define ADC_DUAL_AD4630_ID1        32'h0021_0101
`define REG_ADC1_SHARED_CNV_TICKS  8'h30
`define REG_ADC1_SHARED_BUSY_TICKS 8'h34
`define REG_ADC1_AD4630_IF_MODE    8'h38
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

`define HC2A_ID_VERSION             32'h00410106
// CON11 GPIO TTL HC2A RO-ASCII candidate (SDFM300 retained); HMP pressure commit is unsupported.
`define REG_HC2A_BAUD               8'h10
`define REG_HC2A_ADDRESS            8'h14
`define REG_HC2A_SERIAL_FORMAT      8'h18
`define REG_HC2A_POLL_INTERVAL_MS   8'h1C
`define REG_HC2A_MEAS_MASK          8'h20
`define REG_HC2A_LAST_RH_F32_BITS   8'h24
`define REG_HC2A_LAST_TEMP_F32_BITS 8'h28
`define REG_HC2A_CHECKSUM_ERR_COUNT 8'h2C
`define REG_HC2A_TIMEOUT_COUNT      8'h30
`define REG_HC2A_DEVICE_ALARM       8'h34
`define REG_HC2A_FIFO_LEVEL         8'h38
`define REG_HC2A_DROP_COUNT         8'h3C
`define REG_HC2A_LAST_ALARM         8'h40
`define REG_HC2A_FRAME_COUNT        8'h44
`define REG_HC2A_FORMAT_ERR_COUNT   8'h48
// Isolated HC2A diagnostic extension; stable acquisition ID/data schema retained.
`define REG_HC2A_DEBUG_SIGNATURE    8'h4C
`define REG_HC2A_DEBUG_RX_TOTAL     8'h50
`define REG_HC2A_DEBUG_UART_ERRORS  8'h54
`define REG_HC2A_DEBUG_SNAPSHOT     8'h58
`define REG_HC2A_DEBUG_FAILURE      8'h5C
`define REG_HC2A_DEBUG_RAW_BASE     8'h60
`define HC2A_DEBUG_SIGNATURE        32'h48434432

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

// SDFM300 offsets.
`define REG_SDFM300_BAUD                8'h10
`define REG_SDFM300_LAST_DISTANCE_MM    8'h1C
`define REG_SDFM300_DISTANCE_VALID      8'h20
`define REG_SDFM300_RX_FRAME_COUNT      8'h28
`define REG_SDFM300_CHECKSUM_ERR_COUNT  8'h2C
`define REG_SDFM300_INVALID_COUNT    8'h30
`define REG_SDFM300_FIFO_LEVEL          8'h34
`define REG_SDFM300_DROP_COUNT          8'h38

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
`define REG_RD105_CONFIRMED_TARGET  8'h40
`define REG_RD105_FRAME_COUNT       8'h44
`define REG_RD105_CONFIRMED_COUNT   8'h48
`define REG_RD105_SAMPLE_CHANNEL    8'h4C
`define REG_RD105_PARAM_COMMAND     8'h80
`define REG_RD105_PARAM_ADDRESS     8'h84
`define REG_RD105_PARAM_QUANTITY    8'h88
`define REG_RD105_PARAM_STATUS      8'h8C
`define REG_RD105_PARAM_COUNT       8'h90
`define REG_RD105_PARAM_WRITE_DATA  8'hC0
`define REG_RD105_PARAM_READ_DATA   8'hE0

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

// AI8 revision 0x0200 offsets (source 0046 / page 6600).
`define REG_AI8_BAUD_HZ          8'h10
`define REG_AI8_SLAVE_ADDR       8'h14
`define REG_AI8_SERIAL_FORMAT    8'h18
`define REG_AI8_CHANNEL          8'h1C
`define REG_AI8_TARGET_TEMP_UC   8'h20
`define REG_AI8_ACTUAL_TEMP_UC   8'h24
`define REG_AI8_DEVICE_STATUS    8'h28
`define REG_AI8_POLL_INTERVAL_MS 8'h2C
`define REG_AI8_ACTIVE_TEMP_UC   8'h40
`define REG_AI8_CONFIRMED_COUNT  8'h48
`define REG_AI8_COMMAND_STATUS  8'h4C
`define REG_AI8_TARGET_RAW       8'h50
`define REG_AI8_SET_READBACK     8'h54
`define REG_AI8_SP_PV_RAW        8'h58
`define REG_AI8_SV_OP_RAW        8'h5C
`define REG_AI8_TIMEOUT_MS       8'h60
`define REG_AI8_RETRY_LIMIT      8'h64

// Retained EPSILON and DLIA host extensions, 2026-10-17.
`define REG_DILA_CUTOFF_SHADOW    8'h58
`define REG_DILA_CUTOFF_ACTIVE    8'h5C
`define REG_DILA_FILTER_ORDER_SHADOW 8'h60
`define REG_DILA_FILTER_ORDER_ACTIVE 8'h64
`define REG_DILA_COEFF_WORD_BASE    8'h68
`define REG_DILA_COEFF_WORD_LAST    8'hDC
`define REG_DILA_DESIGN_RATE_SHADOW 8'hE0
`define REG_DILA_DESIGN_CUTOFF_SHADOW 8'hE4
`define REG_DILA_DESIGN_RATE_ACTIVE 8'hE8
`define REG_DILA_DESIGN_CUTOFF_ACTIVE 8'hEC
`define REG_DILA_SOS_API_ID          8'hF0
`define REG_DILA_SOS_STATUS          8'hF4
`define REG_DILA_CONFIG_GENERATION   8'hF8
`define REG_DILA_INPUT_RATE_ACTUAL   8'hFC
`define REG_EPSILON_TX_CONTROL   8'h40
`define REG_EPSILON_TX_LENGTH    8'h44
`define REG_EPSILON_TX_KIND      8'h48
`define REG_EPSILON_TX_STATUS    8'h4C
`define REG_EPSILON_TX_BYTES     8'h50
`define REG_EPSILON_TX_COMPLETE  8'h54
`define REG_EPSILON_TX_FAILED    8'h58
`define REG_EPSILON_RX_LENGTH    8'h5C
`define REG_EPSILON_RX_INDEX     8'h60
`define REG_EPSILON_RX_DATA      8'h64
`define REG_EPSILON_TX_DATA      8'h68
`define REG_EPSILON_TX_LOADED    8'h6C
`define REG_EPSILON_RX_TIMEOUT   8'h70
`define REG_EPSILON_TX_TARGET    8'h74
`define REG_EPSILON_RTCM_BAUD    8'h78
`define REG_EPSILON_RTCM_BYTES   8'h7C

// PPS calibration revision 0x0200, source 0002 / page 1000.
`define TIME_SYNC_ID_VERSION        32'h00020200
`define REG_TIME_CAL_SNAPSHOT       8'h44
`define REG_TIME_TICKS_PER_SECOND   8'h48
`define REG_TIME_SNAPSHOT_SEQ       8'h4C
`define REG_TIME_SNAPSHOT_TICK_LO   8'h50
`define REG_TIME_SNAPSHOT_TICK_HI   8'h54
`define REG_TIME_SNAPSHOT_UTC_LO    8'h58
`define REG_TIME_SNAPSHOT_UTC_HI    8'h5C
`define REG_TIME_SNAPSHOT_STATUS   8'h60
`define REG_TIME_REJECTED_PERIODS  8'h64
`define REG_TIME_NOMINAL_HZ        8'h68
`define REG_TIME_ANCHOR_SECONDS    8'h70
`define REG_TIME_ANCHOR_SEQ        8'h74
`define REG_TIME_ANCHOR_COMMAND    8'h78
// DM422 adapter revision 0x0200, source 0047 / page 6700.
`define MOTOR_ID_VERSION            32'h00470200
`define REG_MOTOR_HEARTBEAT         8'h38
`define REG_MOTOR_CORE_STATUS       8'h3C
`define REG_MOTOR_CLOCK_HZ          8'h40
`define REG_MOTOR_WATCHDOG_MS       8'h44
`define REG_MOTOR_PULSES_PER_MM     8'h48

// PPS single-scan extension; independent per WMS channel, reset mode=0.
`define REG_WMS_TRIGGER_MODE           8'h4C
`define REG_WMS_IDLE_LEVEL             8'h50
`define REG_WMS_TRIGGER_STATUS         8'h54
`define REG_WMS_TRIGGER_COUNT          8'h58
`define REG_WMS_MISSED_COUNT           8'h5C
`define REG_WMS_LAST_PPS_SEQ           8'h60
`define REG_WMS_LAST_PPS_LO            8'h64
`define REG_WMS_LAST_PPS_HI            8'h68
`define REG_WMS_ACTUAL_START_LO        8'h6C
`define REG_WMS_ACTUAL_START_HI        8'h70
`define REG_WMS_ACTUAL_END_LO          8'h74
`define REG_WMS_ACTUAL_END_HI          8'h78
`define REG_WMS_COMPLETED_COUNT        8'h7C
`define REG_WMS_ABORTED_COUNT          8'h80
`define REG_WMS_TRIGGER_API            8'h84
`define REG_WMS_REJECTED_COUNT         8'h88
`define REG_WMS_DISC_API               8'h8c
`define REG_WMS_DISC_STATUS            8'h90
`define REG_WMS_DISC_STEP              8'h94

`endif
