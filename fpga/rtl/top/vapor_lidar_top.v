`default_nettype none
// Formal physical top. DUAL_AD4630 selects the two low-speed analog inputs.
module vapor_lidar_top #(parameter integer SIMULATION=0,GPIF_CLK_HZ=50000000,
    DUAL_AD4630=1,RAW0_MAX_SAMPLES=16384,
    RAW1_MAX_SAMPLES=(DUAL_AD4630 ? 16384 : 131072))(
    input wire CLK_FPGA_25MHZ,
    inout wire [31:0] FPGA_GPIF_DQ,
    inout wire [12:0] FPGA_GPIF_CTL,
    input wire FPGA_GPIF_INTN,
    output wire FPGA_GPIF_PCLK,CYUSB_RSTN,
    input wire FPGA_RS232A_RXD,FPGA_RS232B_RXD,FPGA_RS485_RXD_L,FPGA_RS422_RXD_L,FPGA_UART_RXD_L,TFA_LF_RXD,
    output wire FPGA_RS232A_TXD,FPGA_RS485_TXD_L,FPGA_RS485_DERE_L,FPGA_RS422_TXD_L,FPGA_UART_TXD_L,
    output wire FPGA_UART_EN_L,RS232_PHY_FORCEON,FPGA_RS232B_TXD,
    input wire SYNC_IN,BMP390_INT,
    inout wire I2C_SCL,I2C_SDA,
    output wire MOTOR_PUL,MOTOR_DIR,MOTOR_ENA,
    output wire [1:0] dac_sclk,dac_sync_n,dac_sdin,dac_rst_n,dac_clr_n,dac_ldac_n,
    input wire [1:0] dac_sdo,
    output wire  ADC_AD4630_SDI,
    output wire  ADC_AD4630_RSTN,
    output wire  ADC_AD4630_CNV,
    output wire  ADC_AD4630_CSN,
    output wire  ADC_AD4630_SCK,
    input wire  ADC_AD4630_BUSY,
    input wire [7:0] ADC_AD4630_SDO,
    input wire  ADC_ADC3660_DA5,
    input wire  ADC_ADC3660_DA6,
    input wire  ADC_ADC3660_DB5,
    input wire  ADC_ADC3660_DB6,
    input wire  ADC_ADC3660_DCLK,
    input wire  ADC_ADC3660_FCLK,
    output wire  ADC_ADC3660_DCLKIN,
    output wire  ADC_ADC3660_CLKP,
    output wire  ADC_ADC3660_CLKN,
    output wire  ADC_ADC3660_SEN,
    output wire  ADC_ADC3660_SCLK,
    output wire  ADC_ADC3660_RST,
    output wire  ADC_ADC3660_SYNC,
    inout wire  ADC_ADC3660_SDIO
);
    reg [7:0] power_count=0;
    always @(posedge CLK_FPGA_25MHZ)if(power_count!=255)power_count<=power_count+1'b1;
    wire sys_clk,gpif_clk,rst_power_n,rst_operational_n,rst_gpif_power_n,clock_locked;
    wire [31:0] clock_fault_ref,clock_fault_sys;
    wire rst_control_n,rst_adc_n,rst_wms_n,rst_sensors_n,rst_motor_n,rst_stream_n,rst_transport_n;
    wire reset_pending,soft_reset_pulse,clock_reset_request,stream_reset_pulse,stream_clear_pulse,usb_clear_pulse,fx3_reset_request;
    wire [31:0] reset_mask,fx3_reset_ms,forced_clear_count;
    wire global_enable,stream_enable,usb_enable,watchdog_kick,watchdog_expired;
    wire [31:0] watchdog_timeout_ms,watchdog_expirations;
    wire [63:0] timestamp_now,gnss_time_tag,sync_event_tick,sync_event_gnss_tag;
    wire time_sync_valid,gnss_time_tag_valid,sync_event_pulse,sync_event_gnss_valid;
    wire [31:0] sync_seq,time_errors;
    wire [63:0] stream_mask,raw_stream_mask;
    wire arb_mode,acquisition_running,acquisition_requested,action_busy;
    wire [31:0] max_high_burst,tx_high_water,system_errors,irq_summary,reset_reason,clock_fault_count;
    wire [1:0] stop_flush,wms_scan_start,wms_phase_valid,wms_running,wms_config_changed;
    wire [63:0] wms_cycle_id,wms_sine_phase;
    wire [1:0] channel_idle;
    wire motor_busy,motor_done;
    wire [31:0] motion_id,motor_position,motor_remaining,motor_errors;
    wire [6:0] device_online;
    wire [223:0] device_error,device_drop,device_level;
    wire scl_low,sda_low;
    assign I2C_SCL=scl_low ? 1'b0 : 1'bz;
    assign I2C_SDA=sda_low ? 1'b0 : 1'bz;
    assign FPGA_UART_EN_L=1'b1;
    assign RS232_PHY_FORCEON=1'b1;
    assign FPGA_RS422_TXD_L=1'b1;
    wire [2:0] master_valid,master_write,master_ready,master_error;
    wire [95:0] master_addr,master_wdata,master_rdata;
    wire [11:0] master_wstrb;
    wire [11:0] master_error_code;
    wire [3:0] cfg_error_code;
    wire [83:0] slave_error_code;
    wire cfg_valid,cfg_write,cfg_ready,cfg_error;
    wire [31:0] cfg_addr,cfg_wdata,cfg_rdata;
    wire [3:0] cfg_wstrb;
    wire [20:0] slave_valid,slave_ready,slave_error,module_present;
    wire [671:0] slave_rdata,module_status,module_errors;
    wire slave_write;wire [31:0] slave_addr,slave_wdata;wire [3:0] slave_wstrb;
    wire [31:0] crossbar_timeouts,poll_timeouts;
    wire [31:0] module_error_summary,module_irq,event_drops,total_drops,sensor_level;
    wire [95:0] event_queue_level;
    wire [63:0] arb_grants,hub_grants;
    wire [9:0] arb_pending;
    wire [5:0] hub_pending;
    wire [31:0] packet_errors,packet_frames,sequence_tx,sequence_rx,protocol_errors,crc_errors,parser_level;
    wire packet_busy,packet_valid,packet_ready,packet_last;
    wire [31:0] packet_data,tx_level,rx_level,gpif_tx_level,gpif_rx_free;
    wire gt_valid,gt_ready,gt_last,gr_valid,gr_ready,rx_valid,rx_ready;
    wire [31:0] gt_data,gr_data,rx_data;
    wire [159:0] gpif_counters,sys_gpif_counters;
    wire gpif_idle;
    wire command_valid,command_done,byte_valid,byte_ready;
    wire [7:0] byte_data;
    wire [31:0] command_status,command_sequence,command_payload_bytes,payload_word,payload_data;
    wire [15:0] command_source,command_id,action_code,action_source;
    wire [127:0] action_args;
    wire action_valid,action_ready;wire [31:0] action_status;
    wire [7:0] response_frame_type;wire [31:0] response_sequence;wire response_sequence_valid;
    wire [23:0] event_frame_type;
    (* ASYNC_REG="TRUE" *)reg [1:0] link_sync;
    always @(posedge sys_clk or negedge rst_power_n)
        if(!rst_power_n)link_sync<=0;else link_sync<={link_sync[0],FPGA_GPIF_CTL[4]};
    // FLAG A goes low on ordinary FIFO-full as well as USB disconnect. It is
    // evidence that firmware has armed DMA, not an instantaneous USB link pin.
    reg firmware_seen;
    always @(posedge sys_clk or negedge rst_power_n)
        if(!rst_power_n)firmware_seen<=0;
        else if(!CYUSB_RSTN)firmware_seen<=0;
        else if(link_sync[1])firmware_seen<=1;
    wire link_ready=firmware_seen && CYUSB_RSTN;
    wire path_quiet;
    reg [63:0] tx_count64,rx_count64;
    reg [31:0] tx_previous,rx_previous;

    wire system_ready,system_error;wire [31:0] system_rdata;
    wire [3:0] system_error_code;
    wire time_ready,time_error;wire [31:0] time_rdata;
    wire [3:0] time_error_code;
    wire member1_ready,member1_error;wire [31:0] member1_rdata;
    wire [15:0] member1_error_code;
    wire member2_ready,member2_error;wire [31:0] member2_rdata;
    wire [3:0] member2_error_code;
    wire member3_ready,member3_error;wire [31:0] member3_rdata;
    wire [27:0] member3_error_code;
    wire motor_ready,motor_error;wire [31:0] motor_rdata;
    wire [3:0] motor_error_code;
    wire [6:0] sensor_valid;
    wire [6:0] sensor_ready;
    wire [223:0] sensor_data;
    wire [27:0] sensor_keep;
    wire [6:0] sensor_sof;
    wire [6:0] sensor_last;
    wire [111:0] sensor_source_id;
    wire [111:0] sensor_msg_id;
    wire [447:0] sensor_timestamp;
    wire [223:0] sensor_cycle_id;
    wire [223:0] sensor_flags;
    wire [6:0] sensor_gated_valid;
    wire [6:0] sensor_gated_ready;
    wire [223:0] sensor_gated_data;
    wire [27:0] sensor_gated_keep;
    wire [6:0] sensor_gated_sof;
    wire [6:0] sensor_gated_last;
    wire [111:0] sensor_gated_source_id;
    wire [111:0] sensor_gated_msg_id;
    wire [447:0] sensor_gated_timestamp;
    wire [223:0] sensor_gated_cycle_id;
    wire [223:0] sensor_gated_flags;
    wire [5:0] hub_in_valid;
    wire [5:0] hub_in_ready;
    wire [191:0] hub_in_data;
    wire [23:0] hub_in_keep;
    wire [5:0] hub_in_sof;
    wire [5:0] hub_in_last;
    wire [95:0] hub_in_source_id;
    wire [95:0] hub_in_msg_id;
    wire [383:0] hub_in_timestamp;
    wire [191:0] hub_in_cycle_id;
    wire [191:0] hub_in_flags;
    wire hub_valid;
    wire hub_ready;
    wire [31:0] hub_data;
    wire [3:0] hub_keep;
    wire hub_sof;
    wire hub_last;
    wire [15:0] hub_source_id;
    wire [15:0] hub_msg_id;
    wire [63:0] hub_timestamp;
    wire [31:0] hub_cycle_id;
    wire [31:0] hub_flags;
    wire [2:0] events_valid;
    wire [2:0] events_ready;
    wire [95:0] events_data;
    wire [11:0] events_keep;
    wire [2:0] events_sof;
    wire [2:0] events_last;
    wire [47:0] events_source_id;
    wire [47:0] events_msg_id;
    wire [191:0] events_timestamp;
    wire [95:0] events_cycle_id;
    wire [95:0] events_flags;
    wire [2:0] events_gated_valid;
    wire [2:0] events_gated_ready;
    wire [95:0] events_gated_data;
    wire [11:0] events_gated_keep;
    wire [2:0] events_gated_sof;
    wire [2:0] events_gated_last;
    wire [47:0] events_gated_source_id;
    wire [47:0] events_gated_msg_id;
    wire [191:0] events_gated_timestamp;
    wire [95:0] events_gated_cycle_id;
    wire [95:0] events_gated_flags;
    wire response_valid;
    wire response_ready;
    wire [31:0] response_data;
    wire [3:0] response_keep;
    wire response_sof;
    wire response_last;
    wire [15:0] response_source_id;
    wire [15:0] response_msg_id;
    wire [63:0] response_timestamp;
    wire [31:0] response_cycle_id;
    wire [31:0] response_flags;
    wire [1:0] raw_valid;
    wire [1:0] raw_ready;
    wire [63:0] raw_data;
    wire [7:0] raw_keep;
    wire [1:0] raw_sof;
    wire [1:0] raw_last;
    wire [31:0] raw_source_id;
    wire [31:0] raw_msg_id;
    wire [127:0] raw_timestamp;
    wire [63:0] raw_cycle_id;
    wire [63:0] raw_flags;
    wire [1:0] dila_valid;
    wire [1:0] dila_ready;
    wire [63:0] dila_data;
    wire [7:0] dila_keep;
    wire [1:0] dila_sof;
    wire [1:0] dila_last;
    wire [31:0] dila_source_id;
    wire [31:0] dila_msg_id;
    wire [127:0] dila_timestamp;
    wire [63:0] dila_cycle_id;
    wire [63:0] dila_flags;
    wire [1:0] dila_gated_valid;
    wire [1:0] dila_gated_ready;
    wire [63:0] dila_gated_data;
    wire [7:0] dila_gated_keep;
    wire [1:0] dila_gated_sof;
    wire [1:0] dila_gated_last;
    wire [31:0] dila_gated_source_id;
    wire [31:0] dila_gated_msg_id;
    wire [127:0] dila_gated_timestamp;
    wire [63:0] dila_gated_cycle_id;
    wire [63:0] dila_gated_flags;
    wire [9:0] arb_in_valid;
    wire [9:0] arb_in_ready;
    wire [319:0] arb_in_data;
    wire [39:0] arb_in_keep;
    wire [9:0] arb_in_sof;
    wire [9:0] arb_in_last;
    wire [159:0] arb_in_source_id;
    wire [159:0] arb_in_msg_id;
    wire [639:0] arb_in_timestamp;
    wire [319:0] arb_in_cycle_id;
    wire [319:0] arb_in_flags;
    wire arb_valid;
    wire arb_ready;
    wire [31:0] arb_data;
    wire [3:0] arb_keep;
    wire arb_sof;
    wire arb_last;
    wire [15:0] arb_source_id;
    wire [15:0] arb_msg_id;
    wire [63:0] arb_timestamp;
    wire [31:0] arb_cycle_id;
    wire [31:0] arb_flags;
    wire [383:0] gate_drops;
    assign path_quiet=!command_valid && !packet_busy && !packet_valid && !arb_valid && tx_level==0;
    wire raw0_valid,raw0_ready,raw0_idle,raw0_capture_phase_valid,raw0_capture_time_sync_valid;
    wire [31:0] raw0_data,raw0_capture_cycle_id,raw0_capture_phase,raw0_sample_rate_hz;
    wire [63:0] raw0_capture_timestamp,raw0_cycle_timestamp;
    wire [7:0] raw0_flags;
    wire [31:0] raw0_drop_count,raw0_cycle_drops,raw0_frames,raw0_level,raw0_fifo_level,dila0_fifo_level;
    wire dila0_idle;

    wire raw1_valid,raw1_ready,raw1_idle,raw1_capture_phase_valid,raw1_capture_time_sync_valid;
    wire [31:0] raw1_data,raw1_capture_cycle_id,raw1_capture_phase,raw1_sample_rate_hz;
    wire [63:0] raw1_capture_timestamp,raw1_cycle_timestamp;
    wire [7:0] raw1_flags;
    wire [31:0] raw1_drop_count,raw1_cycle_drops,raw1_frames,raw1_level,raw1_fifo_level,dila1_fifo_level;
    wire dila1_idle;

    clk_rst_mgr #(.SIMULATION(SIMULATION),.GPIF_CLK_HZ(GPIF_CLK_HZ)) u_clock(
        .ref_clk(CLK_FPGA_25MHZ),
        .ext_reset_n(&power_count),
        .sw_global_reset(1'b0),
        .sys_clk(sys_clk),
        .gpif_clk(gpif_clk),
        .rst_sys_n(rst_operational_n),
        .rst_persistent_n(rst_power_n),
        .rst_gpif_n(rst_gpif_power_n),
        .clocks_locked(clock_locked)
    );
    clock_health_monitor u_clock_health(
        .ref_clk(CLK_FPGA_25MHZ),
        .por_n(&power_count),
        .clock_locked(clock_locked),
        .fault_total(clock_fault_ref)
    );
    counter_cdc u_clock_fault_cdc(
        .src_clk(CLK_FPGA_25MHZ),
        .src_rst_n(&power_count),
        .dst_clk(sys_clk),
        .dst_rst_n(rst_power_n),
        .src_count(clock_fault_ref),
        .dst_count(clock_fault_sys)
    );
    wire managed_rst_control_n;assign rst_control_n=managed_rst_control_n && rst_operational_n;
    wire managed_rst_adc_n;assign rst_adc_n=managed_rst_adc_n && rst_operational_n;
    wire managed_rst_wms_n;assign rst_wms_n=managed_rst_wms_n && rst_operational_n;
    wire managed_rst_sensors_n;assign rst_sensors_n=managed_rst_sensors_n && rst_operational_n;
    wire managed_rst_motor_n;assign rst_motor_n=managed_rst_motor_n && rst_operational_n;
    wire managed_rst_stream_n;assign rst_stream_n=managed_rst_stream_n && rst_operational_n;
    wire managed_rst_transport_n;assign rst_transport_n=managed_rst_transport_n && rst_operational_n;
    system_reset_controller #(.STARTUP_FX3_RESET_MS(SIMULATION ? 0 : 10)) u_resets(
        .sys_clk(sys_clk),
        .rst_power_n(rst_power_n),
        .soft_request(soft_reset_pulse),
        .clock_request(clock_reset_request),
        .watchdog_request(watchdog_expired),
        .stream_reset_request(stream_reset_pulse),
        .stream_clear_request(stream_clear_pulse),
        .usb_clear_request(usb_clear_pulse),
        .fx3_request(fx3_reset_request),
        .reset_mask(reset_mask),
        .fx3_reset_ms(fx3_reset_ms),
        .path_quiet(path_quiet),
        .reset_pending(reset_pending),
        .rst_control_n(managed_rst_control_n),
        .rst_adc_n(managed_rst_adc_n),
        .rst_wms_n(managed_rst_wms_n),
        .rst_sensors_n(managed_rst_sensors_n),
        .rst_motor_n(managed_rst_motor_n),
        .rst_stream_n(managed_rst_stream_n),
        .rst_transport_n(managed_rst_transport_n),
        .fx3_reset_n(CYUSB_RSTN),
        .forced_clear_count(forced_clear_count)
    );
    watchdog u_watchdog(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_power_n),
        .timeout_ms(watchdog_timeout_ms),
        .kick(watchdog_kick),
        .expired_pulse(watchdog_expired),
        .expiration_count(watchdog_expirations)
    );
    time_sync_core #(.CHECK_CLOCK_VALID(1)) u_time(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_power_n),
        .cfg_valid(slave_valid[2]),
        .cfg_write(slave_write),
        .cfg_addr(slave_addr),
        .cfg_wdata(slave_wdata),
        .cfg_wstrb(slave_wstrb),
        .cfg_ready(time_ready),
        .cfg_error(time_error),
        .cfg_rdata(time_rdata),
        .cfg_error_code(time_error_code),
        .timestamp_now(timestamp_now),
        .gnss_time_tag(gnss_time_tag),
        .gnss_time_tag_valid(gnss_time_tag_valid),
        .sync_seq(sync_seq),
        .sync_event_pulse(sync_event_pulse),
        .sync_event_tick(sync_event_tick),
        .sync_event_gnss_tag(sync_event_gnss_tag),
        .sync_event_gnss_valid(sync_event_gnss_valid),
        .sync_valid(time_sync_valid),
        .sync_in_async(SYNC_IN),
        .error_status(time_errors),
        .clock_valid(rst_operational_n)
    );
    wms_dac_dual u_member2(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_wms_n),
        .cfg_valid(|slave_valid[6:3]),
        .cfg_write(slave_write),
        .cfg_addr(slave_addr),
        .cfg_wdata(slave_wdata),
        .cfg_wstrb(slave_wstrb),
        .cfg_ready(member2_ready),
        .cfg_error(member2_error),
        .cfg_rdata(member2_rdata),
        .cfg_error_code(member2_error_code),
        .enable({2{global_enable}}),
        .timestamp_now(timestamp_now),
        .time_sync_valid(time_sync_valid),
        .scan_start(wms_scan_start),
        .cycle_id(wms_cycle_id),
        .sine_phase(wms_sine_phase),
        .phase_valid(wms_phase_valid),
        .config_changed(wms_config_changed),
        .wms_running(wms_running),
        .dac_sclk(dac_sclk),
        .dac_sync_n(dac_sync_n),
        .dac_sdin(dac_sdin),
        .dac_sdo(dac_sdo),
        .dac_rst_n(dac_rst_n),
        .dac_clr_n(dac_clr_n),
        .dac_ldac_n(dac_ldac_n)
    );
    member1_adc_dila #(.SIMULATION(SIMULATION),.DUAL_AD4630(DUAL_AD4630)) u_member1(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_adc_n),
        .cfg_valid(|slave_valid[10:7]),
        .cfg_write(slave_write),
        .cfg_addr(slave_addr),
        .cfg_wdata(slave_wdata),
        .cfg_wstrb(slave_wstrb),
        .cfg_ready(member1_ready),
        .cfg_error(member1_error),
        .cfg_rdata(member1_rdata),
        .cfg_error_code(member1_error_code),
        .timestamp_now(timestamp_now),
        .time_sync_valid(time_sync_valid),
        .ADC_AD4630_SDI(ADC_AD4630_SDI),
        .ADC_AD4630_RSTN(ADC_AD4630_RSTN),
        .ADC_AD4630_CNV(ADC_AD4630_CNV),
        .ADC_AD4630_CSN(ADC_AD4630_CSN),
        .ADC_AD4630_SCK(ADC_AD4630_SCK),
        .ADC_AD4630_BUSY(ADC_AD4630_BUSY),
        .ADC_AD4630_SDO(ADC_AD4630_SDO),
        .ADC_ADC3660_DA5(ADC_ADC3660_DA5),
        .ADC_ADC3660_DA6(ADC_ADC3660_DA6),
        .ADC_ADC3660_DB5(ADC_ADC3660_DB5),
        .ADC_ADC3660_DB6(ADC_ADC3660_DB6),
        .ADC_ADC3660_DCLK(ADC_ADC3660_DCLK),
        .ADC_ADC3660_FCLK(ADC_ADC3660_FCLK),
        .ADC_ADC3660_DCLKIN(ADC_ADC3660_DCLKIN),
        .ADC_ADC3660_CLKP(ADC_ADC3660_CLKP),
        .ADC_ADC3660_CLKN(ADC_ADC3660_CLKN),
        .ADC_ADC3660_SEN(ADC_ADC3660_SEN),
        .ADC_ADC3660_SCLK(ADC_ADC3660_SCLK),
        .ADC_ADC3660_RST(ADC_ADC3660_RST),
        .ADC_ADC3660_SYNC(ADC_ADC3660_SYNC),
        .ADC_ADC3660_SDIO(ADC_ADC3660_SDIO),
        .wms0_scan_start(wms_scan_start[0]),
        .wms0_cycle_id(wms_cycle_id[0 +: 32]),
        .wms0_sine_phase(wms_sine_phase[0 +: 32]),
        .wms0_phase_valid(wms_phase_valid[0]),
        .raw0_valid(raw0_valid),
        .raw0_ready(raw0_ready),
        .raw0_data(raw0_data),
        .raw0_flags(raw0_flags),
        .raw0_capture_cycle_id(raw0_capture_cycle_id),
        .raw0_capture_phase(raw0_capture_phase),
        .raw0_capture_timestamp(raw0_capture_timestamp),
        .raw0_cycle_timestamp(raw0_cycle_timestamp),
        .raw0_capture_phase_valid(raw0_capture_phase_valid),
        .raw0_capture_time_sync_valid(raw0_capture_time_sync_valid),
        .raw0_sample_rate_hz(raw0_sample_rate_hz),
        .raw0_fifo_level(raw0_fifo_level),
        .raw0_idle(raw0_idle),
        .dila0_valid(dila_valid[0]),
        .dila0_ready(dila_ready[0]),
        .dila0_data(dila_data[0 +: 32]),
        .dila0_keep(dila_keep[0 +: 4]),
        .dila0_sof(dila_sof[0]),
        .dila0_last(dila_last[0]),
        .dila0_source_id(dila_source_id[0 +: 16]),
        .dila0_msg_id(dila_msg_id[0 +: 16]),
        .dila0_timestamp(dila_timestamp[0 +: 64]),
        .dila0_cycle_id(dila_cycle_id[0 +: 32]),
        .dila0_flags(dila_flags[0 +: 32]),
        .dila0_fifo_level(dila0_fifo_level),
        .dila0_idle(dila0_idle),
        .wms1_scan_start(wms_scan_start[1]),
        .wms1_cycle_id(wms_cycle_id[32 +: 32]),
        .wms1_sine_phase(wms_sine_phase[32 +: 32]),
        .wms1_phase_valid(wms_phase_valid[1]),
        .raw1_valid(raw1_valid),
        .raw1_ready(raw1_ready),
        .raw1_data(raw1_data),
        .raw1_flags(raw1_flags),
        .raw1_capture_cycle_id(raw1_capture_cycle_id),
        .raw1_capture_phase(raw1_capture_phase),
        .raw1_capture_timestamp(raw1_capture_timestamp),
        .raw1_cycle_timestamp(raw1_cycle_timestamp),
        .raw1_capture_phase_valid(raw1_capture_phase_valid),
        .raw1_capture_time_sync_valid(raw1_capture_time_sync_valid),
        .raw1_sample_rate_hz(raw1_sample_rate_hz),
        .raw1_fifo_level(raw1_fifo_level),
        .raw1_idle(raw1_idle),
        .dila1_valid(dila_valid[1]),
        .dila1_ready(dila_ready[1]),
        .dila1_data(dila_data[32 +: 32]),
        .dila1_keep(dila_keep[4 +: 4]),
        .dila1_sof(dila_sof[1]),
        .dila1_last(dila_last[1]),
        .dila1_source_id(dila_source_id[16 +: 16]),
        .dila1_msg_id(dila_msg_id[16 +: 16]),
        .dila1_timestamp(dila_timestamp[64 +: 64]),
        .dila1_cycle_id(dila_cycle_id[32 +: 32]),
        .dila1_flags(dila_flags[32 +: 32]),
        .dila1_fifo_level(dila1_fifo_level),
        .dila1_idle(dila1_idle)
    );
    member3_sensor_bank #(.PTB_BOOT_MS(SIMULATION ? 1 : 2000)) u_member3(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_sensors_n),
        .cfg_valid(|slave_valid[17:11]),
        .cfg_write(slave_write),
        .cfg_addr(slave_addr),
        .cfg_wdata(slave_wdata),
        .cfg_wstrb(slave_wstrb),
        .cfg_ready(member3_ready),
        .cfg_error(member3_error),
        .cfg_rdata(member3_rdata),
        .cfg_error_code(member3_error_code),
        .timestamp_now(timestamp_now),
        .time_sync_valid(time_sync_valid),
        .time_sync_seq(sync_seq),
        .sync_event_pulse(sync_event_pulse),
        .m_valid(sensor_valid),
        .m_ready(sensor_ready),
        .m_data(sensor_data),
        .m_keep(sensor_keep),
        .m_sof(sensor_sof),
        .m_last(sensor_last),
        .m_source_id(sensor_source_id),
        .m_msg_id(sensor_msg_id),
        .m_timestamp(sensor_timestamp),
        .m_cycle_id(sensor_cycle_id),
        .m_flags(sensor_flags),
        .ptb_rxd(FPGA_RS232A_RXD),
        .ptb_txd(FPGA_RS232A_TXD),
        .rs485_rxd(FPGA_RS485_RXD_L),
        .rs485_txd(FPGA_RS485_TXD_L),
        .rs485_de(FPGA_RS485_DERE_L),
        .epsilon_rxd(FPGA_RS232B_RXD),
        .epsilon_txd(FPGA_RS232B_TXD),
        .tfa_hf_rxd(FPGA_UART_RXD_L),
        .tfa_lf_rxd(TFA_LF_RXD),
        .tfa_txd(FPGA_UART_TXD_L),
        .scl_i(I2C_SCL),
        .sda_i(I2C_SDA),
        .scl_drive_low(scl_low),
        .sda_drive_low(sda_low),
        .bmp_int(BMP390_INT),
        .gnss_time_tag(gnss_time_tag),
        .gnss_time_tag_valid(gnss_time_tag_valid),
        .device_online(device_online),
        .device_error(device_error),
        .device_drop_count(device_drop),
        .device_fifo_level(device_level)
    );
    stepper_ctrl u_motor(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_motor_n),
        .cfg_valid(slave_valid[18]),
        .cfg_write(slave_write),
        .cfg_addr(slave_addr),
        .cfg_wdata(slave_wdata),
        .cfg_wstrb(slave_wstrb),
        .cfg_ready(motor_ready),
        .cfg_error(motor_error),
        .cfg_rdata(motor_rdata),
        .cfg_error_code(motor_error_code),
        .system_enable(global_enable),
        .pul(MOTOR_PUL),
        .dir(MOTOR_DIR),
        .ena(MOTOR_ENA),
        .busy(motor_busy),
        .done_pulse(motor_done),
        .motion_id(motion_id),
        .position(motor_position),
        .remaining(motor_remaining),
        .error_status(motor_errors)
    );
    adc_cycle_framer #(.MAX_SAMPLES(RAW0_MAX_SAMPLES),.SOURCE_ID(16'h0020),.ADC_BITS(24)) u_raw0(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable(raw_stream_mask[32] && global_enable && stream_enable && usb_enable && !reset_pending),
        .flush(stop_flush[0]),
        .sample_rate_hz(raw0_sample_rate_hz),
        .s_valid(raw0_valid),
        .s_ready(raw0_ready),
        .s_data(raw0_data),
        .s_flags(raw0_flags),
        .s_capture_cycle_id(raw0_capture_cycle_id),
        .s_cycle_timestamp(raw0_cycle_timestamp),
        .s_capture_phase_valid(raw0_capture_phase_valid),
        .s_capture_time_sync_valid(raw0_capture_time_sync_valid),
        .m_valid(raw_valid[0]),
        .m_ready(raw_ready[0]),
        .m_data(raw_data[0 +: 32]),
        .m_keep(raw_keep[0 +: 4]),
        .m_sof(raw_sof[0]),
        .m_last(raw_last[0]),
        .m_source_id(raw_source_id[0 +: 16]),
        .m_msg_id(raw_msg_id[0 +: 16]),
        .m_timestamp(raw_timestamp[0 +: 64]),
        .m_cycle_id(raw_cycle_id[0 +: 32]),
        .m_flags(raw_flags[0 +: 32]),
        .drop_count(raw0_drop_count),
        .cycle_drop_count(raw0_cycle_drops),
        .frame_count(raw0_frames),
        .buffered_samples(raw0_level)
    );
    assign channel_idle[0]=raw0_idle && raw0_level==0 && dila0_idle && !dila_valid[0] && !raw_valid[0];
    adc_cycle_framer #(.MAX_SAMPLES(RAW1_MAX_SAMPLES),.SOURCE_ID(16'h0021),.ADC_BITS(DUAL_AD4630 ? 24 : 16)) u_raw1(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable(raw_stream_mask[33] && global_enable && stream_enable && usb_enable && !reset_pending),
        .flush(stop_flush[1]),
        .sample_rate_hz(raw1_sample_rate_hz),
        .s_valid(raw1_valid),
        .s_ready(raw1_ready),
        .s_data(raw1_data),
        .s_flags(raw1_flags),
        .s_capture_cycle_id(raw1_capture_cycle_id),
        .s_cycle_timestamp(raw1_cycle_timestamp),
        .s_capture_phase_valid(raw1_capture_phase_valid),
        .s_capture_time_sync_valid(raw1_capture_time_sync_valid),
        .m_valid(raw_valid[1]),
        .m_ready(raw_ready[1]),
        .m_data(raw_data[32 +: 32]),
        .m_keep(raw_keep[4 +: 4]),
        .m_sof(raw_sof[1]),
        .m_last(raw_last[1]),
        .m_source_id(raw_source_id[16 +: 16]),
        .m_msg_id(raw_msg_id[16 +: 16]),
        .m_timestamp(raw_timestamp[64 +: 64]),
        .m_cycle_id(raw_cycle_id[32 +: 32]),
        .m_flags(raw_flags[32 +: 32]),
        .drop_count(raw1_drop_count),
        .cycle_drop_count(raw1_cycle_drops),
        .frame_count(raw1_frames),
        .buffered_samples(raw1_level)
    );
    assign channel_idle[1]=raw1_idle && raw1_level==0 && dila1_idle && !dila_valid[1] && !raw_valid[1];
    stream_gate u_gate_sensor0(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((stream_mask[0]) && stream_enable && usb_enable && !reset_pending),
        .s_valid(sensor_valid[0]),
        .s_ready(sensor_ready[0]),
        .s_data(sensor_data[0 +: 32]),
        .s_keep(sensor_keep[0 +: 4]),
        .s_sof(sensor_sof[0]),
        .s_last(sensor_last[0]),
        .s_source_id(sensor_source_id[0 +: 16]),
        .s_msg_id(sensor_msg_id[0 +: 16]),
        .s_timestamp(sensor_timestamp[0 +: 64]),
        .s_cycle_id(sensor_cycle_id[0 +: 32]),
        .s_flags(sensor_flags[0 +: 32]),
        .m_valid(sensor_gated_valid[0]),
        .m_ready(sensor_gated_ready[0]),
        .m_data(sensor_gated_data[0 +: 32]),
        .m_keep(sensor_gated_keep[0 +: 4]),
        .m_sof(sensor_gated_sof[0]),
        .m_last(sensor_gated_last[0]),
        .m_source_id(sensor_gated_source_id[0 +: 16]),
        .m_msg_id(sensor_gated_msg_id[0 +: 16]),
        .m_timestamp(sensor_gated_timestamp[0 +: 64]),
        .m_cycle_id(sensor_gated_cycle_id[0 +: 32]),
        .m_flags(sensor_gated_flags[0 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[0 +: 32])
    );
    stream_gate u_gate_sensor1(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((stream_mask[1]) && stream_enable && usb_enable && !reset_pending),
        .s_valid(sensor_valid[1]),
        .s_ready(sensor_ready[1]),
        .s_data(sensor_data[32 +: 32]),
        .s_keep(sensor_keep[4 +: 4]),
        .s_sof(sensor_sof[1]),
        .s_last(sensor_last[1]),
        .s_source_id(sensor_source_id[16 +: 16]),
        .s_msg_id(sensor_msg_id[16 +: 16]),
        .s_timestamp(sensor_timestamp[64 +: 64]),
        .s_cycle_id(sensor_cycle_id[32 +: 32]),
        .s_flags(sensor_flags[32 +: 32]),
        .m_valid(sensor_gated_valid[1]),
        .m_ready(sensor_gated_ready[1]),
        .m_data(sensor_gated_data[32 +: 32]),
        .m_keep(sensor_gated_keep[4 +: 4]),
        .m_sof(sensor_gated_sof[1]),
        .m_last(sensor_gated_last[1]),
        .m_source_id(sensor_gated_source_id[16 +: 16]),
        .m_msg_id(sensor_gated_msg_id[16 +: 16]),
        .m_timestamp(sensor_gated_timestamp[64 +: 64]),
        .m_cycle_id(sensor_gated_cycle_id[32 +: 32]),
        .m_flags(sensor_gated_flags[32 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[32 +: 32])
    );
    stream_gate u_gate_sensor2(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((stream_mask[2]) && stream_enable && usb_enable && !reset_pending),
        .s_valid(sensor_valid[2]),
        .s_ready(sensor_ready[2]),
        .s_data(sensor_data[64 +: 32]),
        .s_keep(sensor_keep[8 +: 4]),
        .s_sof(sensor_sof[2]),
        .s_last(sensor_last[2]),
        .s_source_id(sensor_source_id[32 +: 16]),
        .s_msg_id(sensor_msg_id[32 +: 16]),
        .s_timestamp(sensor_timestamp[128 +: 64]),
        .s_cycle_id(sensor_cycle_id[64 +: 32]),
        .s_flags(sensor_flags[64 +: 32]),
        .m_valid(sensor_gated_valid[2]),
        .m_ready(sensor_gated_ready[2]),
        .m_data(sensor_gated_data[64 +: 32]),
        .m_keep(sensor_gated_keep[8 +: 4]),
        .m_sof(sensor_gated_sof[2]),
        .m_last(sensor_gated_last[2]),
        .m_source_id(sensor_gated_source_id[32 +: 16]),
        .m_msg_id(sensor_gated_msg_id[32 +: 16]),
        .m_timestamp(sensor_gated_timestamp[128 +: 64]),
        .m_cycle_id(sensor_gated_cycle_id[64 +: 32]),
        .m_flags(sensor_gated_flags[64 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[64 +: 32])
    );
    stream_gate u_gate_sensor3(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((stream_mask[3]) && stream_enable && usb_enable && !reset_pending),
        .s_valid(sensor_valid[3]),
        .s_ready(sensor_ready[3]),
        .s_data(sensor_data[96 +: 32]),
        .s_keep(sensor_keep[12 +: 4]),
        .s_sof(sensor_sof[3]),
        .s_last(sensor_last[3]),
        .s_source_id(sensor_source_id[48 +: 16]),
        .s_msg_id(sensor_msg_id[48 +: 16]),
        .s_timestamp(sensor_timestamp[192 +: 64]),
        .s_cycle_id(sensor_cycle_id[96 +: 32]),
        .s_flags(sensor_flags[96 +: 32]),
        .m_valid(sensor_gated_valid[3]),
        .m_ready(sensor_gated_ready[3]),
        .m_data(sensor_gated_data[96 +: 32]),
        .m_keep(sensor_gated_keep[12 +: 4]),
        .m_sof(sensor_gated_sof[3]),
        .m_last(sensor_gated_last[3]),
        .m_source_id(sensor_gated_source_id[48 +: 16]),
        .m_msg_id(sensor_gated_msg_id[48 +: 16]),
        .m_timestamp(sensor_gated_timestamp[192 +: 64]),
        .m_cycle_id(sensor_gated_cycle_id[96 +: 32]),
        .m_flags(sensor_gated_flags[96 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[96 +: 32])
    );
    stream_gate u_gate_sensor4(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((stream_mask[4]) && stream_enable && usb_enable && !reset_pending),
        .s_valid(sensor_valid[4]),
        .s_ready(sensor_ready[4]),
        .s_data(sensor_data[128 +: 32]),
        .s_keep(sensor_keep[16 +: 4]),
        .s_sof(sensor_sof[4]),
        .s_last(sensor_last[4]),
        .s_source_id(sensor_source_id[64 +: 16]),
        .s_msg_id(sensor_msg_id[64 +: 16]),
        .s_timestamp(sensor_timestamp[256 +: 64]),
        .s_cycle_id(sensor_cycle_id[128 +: 32]),
        .s_flags(sensor_flags[128 +: 32]),
        .m_valid(sensor_gated_valid[4]),
        .m_ready(sensor_gated_ready[4]),
        .m_data(sensor_gated_data[128 +: 32]),
        .m_keep(sensor_gated_keep[16 +: 4]),
        .m_sof(sensor_gated_sof[4]),
        .m_last(sensor_gated_last[4]),
        .m_source_id(sensor_gated_source_id[64 +: 16]),
        .m_msg_id(sensor_gated_msg_id[64 +: 16]),
        .m_timestamp(sensor_gated_timestamp[256 +: 64]),
        .m_cycle_id(sensor_gated_cycle_id[128 +: 32]),
        .m_flags(sensor_gated_flags[128 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[128 +: 32])
    );
    stream_gate u_gate_sensor5(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((stream_mask[5]) && stream_enable && usb_enable && !reset_pending),
        .s_valid(sensor_valid[5]),
        .s_ready(sensor_ready[5]),
        .s_data(sensor_data[160 +: 32]),
        .s_keep(sensor_keep[20 +: 4]),
        .s_sof(sensor_sof[5]),
        .s_last(sensor_last[5]),
        .s_source_id(sensor_source_id[80 +: 16]),
        .s_msg_id(sensor_msg_id[80 +: 16]),
        .s_timestamp(sensor_timestamp[320 +: 64]),
        .s_cycle_id(sensor_cycle_id[160 +: 32]),
        .s_flags(sensor_flags[160 +: 32]),
        .m_valid(sensor_gated_valid[5]),
        .m_ready(sensor_gated_ready[5]),
        .m_data(sensor_gated_data[160 +: 32]),
        .m_keep(sensor_gated_keep[20 +: 4]),
        .m_sof(sensor_gated_sof[5]),
        .m_last(sensor_gated_last[5]),
        .m_source_id(sensor_gated_source_id[80 +: 16]),
        .m_msg_id(sensor_gated_msg_id[80 +: 16]),
        .m_timestamp(sensor_gated_timestamp[320 +: 64]),
        .m_cycle_id(sensor_gated_cycle_id[160 +: 32]),
        .m_flags(sensor_gated_flags[160 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[160 +: 32])
    );
    stream_gate u_gate_sensor6(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((stream_mask[6]) && stream_enable && usb_enable && !reset_pending),
        .s_valid(sensor_valid[6]),
        .s_ready(sensor_ready[6]),
        .s_data(sensor_data[192 +: 32]),
        .s_keep(sensor_keep[24 +: 4]),
        .s_sof(sensor_sof[6]),
        .s_last(sensor_last[6]),
        .s_source_id(sensor_source_id[96 +: 16]),
        .s_msg_id(sensor_msg_id[96 +: 16]),
        .s_timestamp(sensor_timestamp[384 +: 64]),
        .s_cycle_id(sensor_cycle_id[192 +: 32]),
        .s_flags(sensor_flags[192 +: 32]),
        .m_valid(sensor_gated_valid[6]),
        .m_ready(sensor_gated_ready[6]),
        .m_data(sensor_gated_data[192 +: 32]),
        .m_keep(sensor_gated_keep[24 +: 4]),
        .m_sof(sensor_gated_sof[6]),
        .m_last(sensor_gated_last[6]),
        .m_source_id(sensor_gated_source_id[96 +: 16]),
        .m_msg_id(sensor_gated_msg_id[96 +: 16]),
        .m_timestamp(sensor_gated_timestamp[384 +: 64]),
        .m_cycle_id(sensor_gated_cycle_id[192 +: 32]),
        .m_flags(sensor_gated_flags[192 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[192 +: 32])
    );
    stream_gate u_gate_dila0(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((stream_mask[48+0]) && stream_enable && usb_enable && !reset_pending),
        .s_valid(dila_valid[0]),
        .s_ready(dila_ready[0]),
        .s_data(dila_data[0 +: 32]),
        .s_keep(dila_keep[0 +: 4]),
        .s_sof(dila_sof[0]),
        .s_last(dila_last[0]),
        .s_source_id(dila_source_id[0 +: 16]),
        .s_msg_id(dila_msg_id[0 +: 16]),
        .s_timestamp(dila_timestamp[0 +: 64]),
        .s_cycle_id(dila_cycle_id[0 +: 32]),
        .s_flags(dila_flags[0 +: 32]),
        .m_valid(dila_gated_valid[0]),
        .m_ready(dila_gated_ready[0]),
        .m_data(dila_gated_data[0 +: 32]),
        .m_keep(dila_gated_keep[0 +: 4]),
        .m_sof(dila_gated_sof[0]),
        .m_last(dila_gated_last[0]),
        .m_source_id(dila_gated_source_id[0 +: 16]),
        .m_msg_id(dila_gated_msg_id[0 +: 16]),
        .m_timestamp(dila_gated_timestamp[0 +: 64]),
        .m_cycle_id(dila_gated_cycle_id[0 +: 32]),
        .m_flags(dila_gated_flags[0 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[224 +: 32])
    );
    stream_gate u_gate_dila1(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((stream_mask[48+1]) && stream_enable && usb_enable && !reset_pending),
        .s_valid(dila_valid[1]),
        .s_ready(dila_ready[1]),
        .s_data(dila_data[32 +: 32]),
        .s_keep(dila_keep[4 +: 4]),
        .s_sof(dila_sof[1]),
        .s_last(dila_last[1]),
        .s_source_id(dila_source_id[16 +: 16]),
        .s_msg_id(dila_msg_id[16 +: 16]),
        .s_timestamp(dila_timestamp[64 +: 64]),
        .s_cycle_id(dila_cycle_id[32 +: 32]),
        .s_flags(dila_flags[32 +: 32]),
        .m_valid(dila_gated_valid[1]),
        .m_ready(dila_gated_ready[1]),
        .m_data(dila_gated_data[32 +: 32]),
        .m_keep(dila_gated_keep[4 +: 4]),
        .m_sof(dila_gated_sof[1]),
        .m_last(dila_gated_last[1]),
        .m_source_id(dila_gated_source_id[16 +: 16]),
        .m_msg_id(dila_gated_msg_id[16 +: 16]),
        .m_timestamp(dila_gated_timestamp[64 +: 64]),
        .m_cycle_id(dila_gated_cycle_id[32 +: 32]),
        .m_flags(dila_gated_flags[32 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[256 +: 32])
    );
    stream_gate u_gate_events0(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((1'b1) && stream_enable && usb_enable && !reset_pending),
        .s_valid(events_valid[0]),
        .s_ready(events_ready[0]),
        .s_data(events_data[0 +: 32]),
        .s_keep(events_keep[0 +: 4]),
        .s_sof(events_sof[0]),
        .s_last(events_last[0]),
        .s_source_id(events_source_id[0 +: 16]),
        .s_msg_id(events_msg_id[0 +: 16]),
        .s_timestamp(events_timestamp[0 +: 64]),
        .s_cycle_id(events_cycle_id[0 +: 32]),
        .s_flags(events_flags[0 +: 32]),
        .m_valid(events_gated_valid[0]),
        .m_ready(events_gated_ready[0]),
        .m_data(events_gated_data[0 +: 32]),
        .m_keep(events_gated_keep[0 +: 4]),
        .m_sof(events_gated_sof[0]),
        .m_last(events_gated_last[0]),
        .m_source_id(events_gated_source_id[0 +: 16]),
        .m_msg_id(events_gated_msg_id[0 +: 16]),
        .m_timestamp(events_gated_timestamp[0 +: 64]),
        .m_cycle_id(events_gated_cycle_id[0 +: 32]),
        .m_flags(events_gated_flags[0 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[288 +: 32])
    );
    stream_gate u_gate_events1(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((stream_mask[2]) && stream_enable && usb_enable && !reset_pending),
        .s_valid(events_valid[1]),
        .s_ready(events_ready[1]),
        .s_data(events_data[32 +: 32]),
        .s_keep(events_keep[4 +: 4]),
        .s_sof(events_sof[1]),
        .s_last(events_last[1]),
        .s_source_id(events_source_id[16 +: 16]),
        .s_msg_id(events_msg_id[16 +: 16]),
        .s_timestamp(events_timestamp[64 +: 64]),
        .s_cycle_id(events_cycle_id[32 +: 32]),
        .s_flags(events_flags[32 +: 32]),
        .m_valid(events_gated_valid[1]),
        .m_ready(events_gated_ready[1]),
        .m_data(events_gated_data[32 +: 32]),
        .m_keep(events_gated_keep[4 +: 4]),
        .m_sof(events_gated_sof[1]),
        .m_last(events_gated_last[1]),
        .m_source_id(events_gated_source_id[16 +: 16]),
        .m_msg_id(events_gated_msg_id[16 +: 16]),
        .m_timestamp(events_gated_timestamp[64 +: 64]),
        .m_cycle_id(events_gated_cycle_id[32 +: 32]),
        .m_flags(events_gated_flags[32 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[320 +: 32])
    );
    stream_gate u_gate_events2(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .enable((stream_mask[1]) && stream_enable && usb_enable && !reset_pending),
        .s_valid(events_valid[2]),
        .s_ready(events_ready[2]),
        .s_data(events_data[64 +: 32]),
        .s_keep(events_keep[8 +: 4]),
        .s_sof(events_sof[2]),
        .s_last(events_last[2]),
        .s_source_id(events_source_id[32 +: 16]),
        .s_msg_id(events_msg_id[32 +: 16]),
        .s_timestamp(events_timestamp[128 +: 64]),
        .s_cycle_id(events_cycle_id[64 +: 32]),
        .s_flags(events_flags[64 +: 32]),
        .m_valid(events_gated_valid[2]),
        .m_ready(events_gated_ready[2]),
        .m_data(events_gated_data[64 +: 32]),
        .m_keep(events_gated_keep[8 +: 4]),
        .m_sof(events_gated_sof[2]),
        .m_last(events_gated_last[2]),
        .m_source_id(events_gated_source_id[32 +: 16]),
        .m_msg_id(events_gated_msg_id[32 +: 16]),
        .m_timestamp(events_gated_timestamp[128 +: 64]),
        .m_cycle_id(events_gated_cycle_id[64 +: 32]),
        .m_flags(events_gated_flags[64 +: 32]),
        .drop_pulse(),
        .drop_count(gate_drops[352 +: 32])
    );
    assign hub_in_valid[0]=sensor_gated_valid[0];
    assign sensor_gated_ready[0]=hub_in_ready[0];
    assign hub_in_data[0 +: 32]=sensor_gated_data[0 +: 32];
    assign hub_in_keep[0 +: 4]=sensor_gated_keep[0 +: 4];
    assign hub_in_sof[0]=sensor_gated_sof[0];
    assign hub_in_last[0]=sensor_gated_last[0];
    assign hub_in_source_id[0 +: 16]=sensor_gated_source_id[0 +: 16];
    assign hub_in_msg_id[0 +: 16]=sensor_gated_msg_id[0 +: 16];
    assign hub_in_timestamp[0 +: 64]=sensor_gated_timestamp[0 +: 64];
    assign hub_in_cycle_id[0 +: 32]=sensor_gated_cycle_id[0 +: 32];
    assign hub_in_flags[0 +: 32]=sensor_gated_flags[0 +: 32];
    assign hub_in_valid[1]=sensor_gated_valid[1];
    assign sensor_gated_ready[1]=hub_in_ready[1];
    assign hub_in_data[32 +: 32]=sensor_gated_data[32 +: 32];
    assign hub_in_keep[4 +: 4]=sensor_gated_keep[4 +: 4];
    assign hub_in_sof[1]=sensor_gated_sof[1];
    assign hub_in_last[1]=sensor_gated_last[1];
    assign hub_in_source_id[16 +: 16]=sensor_gated_source_id[16 +: 16];
    assign hub_in_msg_id[16 +: 16]=sensor_gated_msg_id[16 +: 16];
    assign hub_in_timestamp[64 +: 64]=sensor_gated_timestamp[64 +: 64];
    assign hub_in_cycle_id[32 +: 32]=sensor_gated_cycle_id[32 +: 32];
    assign hub_in_flags[32 +: 32]=sensor_gated_flags[32 +: 32];
    assign hub_in_valid[2]=sensor_gated_valid[3];
    assign sensor_gated_ready[3]=hub_in_ready[2];
    assign hub_in_data[64 +: 32]=sensor_gated_data[96 +: 32];
    assign hub_in_keep[8 +: 4]=sensor_gated_keep[12 +: 4];
    assign hub_in_sof[2]=sensor_gated_sof[3];
    assign hub_in_last[2]=sensor_gated_last[3];
    assign hub_in_source_id[32 +: 16]=sensor_gated_source_id[48 +: 16];
    assign hub_in_msg_id[32 +: 16]=sensor_gated_msg_id[48 +: 16];
    assign hub_in_timestamp[128 +: 64]=sensor_gated_timestamp[192 +: 64];
    assign hub_in_cycle_id[64 +: 32]=sensor_gated_cycle_id[96 +: 32];
    assign hub_in_flags[64 +: 32]=sensor_gated_flags[96 +: 32];
    assign hub_in_valid[3]=sensor_gated_valid[4];
    assign sensor_gated_ready[4]=hub_in_ready[3];
    assign hub_in_data[96 +: 32]=sensor_gated_data[128 +: 32];
    assign hub_in_keep[12 +: 4]=sensor_gated_keep[16 +: 4];
    assign hub_in_sof[3]=sensor_gated_sof[4];
    assign hub_in_last[3]=sensor_gated_last[4];
    assign hub_in_source_id[48 +: 16]=sensor_gated_source_id[64 +: 16];
    assign hub_in_msg_id[48 +: 16]=sensor_gated_msg_id[64 +: 16];
    assign hub_in_timestamp[192 +: 64]=sensor_gated_timestamp[256 +: 64];
    assign hub_in_cycle_id[96 +: 32]=sensor_gated_cycle_id[128 +: 32];
    assign hub_in_flags[96 +: 32]=sensor_gated_flags[128 +: 32];
    assign hub_in_valid[4]=sensor_gated_valid[5];
    assign sensor_gated_ready[5]=hub_in_ready[4];
    assign hub_in_data[128 +: 32]=sensor_gated_data[160 +: 32];
    assign hub_in_keep[16 +: 4]=sensor_gated_keep[20 +: 4];
    assign hub_in_sof[4]=sensor_gated_sof[5];
    assign hub_in_last[4]=sensor_gated_last[5];
    assign hub_in_source_id[64 +: 16]=sensor_gated_source_id[80 +: 16];
    assign hub_in_msg_id[64 +: 16]=sensor_gated_msg_id[80 +: 16];
    assign hub_in_timestamp[256 +: 64]=sensor_gated_timestamp[320 +: 64];
    assign hub_in_cycle_id[128 +: 32]=sensor_gated_cycle_id[160 +: 32];
    assign hub_in_flags[128 +: 32]=sensor_gated_flags[160 +: 32];
    assign hub_in_valid[5]=sensor_gated_valid[6];
    assign sensor_gated_ready[6]=hub_in_ready[5];
    assign hub_in_data[160 +: 32]=sensor_gated_data[192 +: 32];
    assign hub_in_keep[20 +: 4]=sensor_gated_keep[24 +: 4];
    assign hub_in_sof[5]=sensor_gated_sof[6];
    assign hub_in_last[5]=sensor_gated_last[6];
    assign hub_in_source_id[80 +: 16]=sensor_gated_source_id[96 +: 16];
    assign hub_in_msg_id[80 +: 16]=sensor_gated_msg_id[96 +: 16];
    assign hub_in_timestamp[320 +: 64]=sensor_gated_timestamp[384 +: 64];
    assign hub_in_cycle_id[160 +: 32]=sensor_gated_cycle_id[192 +: 32];
    assign hub_in_flags[160 +: 32]=sensor_gated_flags[192 +: 32];
    sensor_hub #(.N(6)) u_sensor_hub(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .s_valid(hub_in_valid),
        .s_ready(hub_in_ready),
        .s_data(hub_in_data),
        .s_keep(hub_in_keep),
        .s_sof(hub_in_sof),
        .s_last(hub_in_last),
        .s_source_id(hub_in_source_id),
        .s_msg_id(hub_in_msg_id),
        .s_timestamp(hub_in_timestamp),
        .s_cycle_id(hub_in_cycle_id),
        .s_flags(hub_in_flags),
        .m_valid(hub_valid),
        .m_ready(hub_ready),
        .m_data(hub_data),
        .m_keep(hub_keep),
        .m_sof(hub_sof),
        .m_last(hub_last),
        .m_source_id(hub_source_id),
        .m_msg_id(hub_msg_id),
        .m_timestamp(hub_timestamp),
        .m_cycle_id(hub_cycle_id),
        .m_flags(hub_flags),
        .grant_count(hub_grants),
        .pending_mask(hub_pending)
    );
    cfg_bus_arbiter u_cfg_arbiter(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_control_n),
        .s_valid(master_valid),
        .s_write(master_write),
        .s_addr(master_addr),
        .s_wdata(master_wdata),
        .s_wstrb(master_wstrb),
        .s_ready(master_ready),
        .s_error(master_error),
        .s_rdata(master_rdata),
        .s_error_code(master_error_code),
        .m_valid(cfg_valid),
        .m_write(cfg_write),
        .m_addr(cfg_addr),
        .m_wdata(cfg_wdata),
        .m_wstrb(cfg_wstrb),
        .m_ready(cfg_ready),
        .m_error(cfg_error),
        .m_rdata(cfg_rdata),
        .m_error_code(cfg_error_code)
    );
    reg_ctrl_crossbar u_crossbar(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_control_n),
        .cfg_valid(cfg_valid),
        .cfg_write(cfg_write),
        .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata),
        .cfg_wstrb(cfg_wstrb),
        .cfg_ready(cfg_ready),
        .cfg_error(cfg_error),
        .cfg_rdata(cfg_rdata),
        .cfg_error_code(cfg_error_code),
        .slave_valid(slave_valid),
        .slave_write(slave_write),
        .slave_addr(slave_addr),
        .slave_wdata(slave_wdata),
        .slave_wstrb(slave_wstrb),
        .slave_ready(slave_ready),
        .slave_error(slave_error),
        .slave_rdata(slave_rdata),
        .slave_error_code(slave_error_code),
        .timeout_count(crossbar_timeouts)
    );
    assign slave_ready[0]=system_ready;assign slave_error[0]=system_error;assign slave_rdata[0 +: 32]=system_rdata;
    assign slave_error_code[0 +: 4]=system_error_code;
    assign slave_ready[1]=system_ready;assign slave_error[1]=system_error;assign slave_rdata[32 +: 32]=system_rdata;
    assign slave_error_code[4 +: 4]=system_error_code;
    assign slave_ready[19]=system_ready;assign slave_error[19]=system_error;assign slave_rdata[608 +: 32]=system_rdata;
    assign slave_error_code[76 +: 4]=system_error_code;
    assign slave_ready[20]=system_ready;assign slave_error[20]=system_error;assign slave_rdata[640 +: 32]=system_rdata;
    assign slave_error_code[80 +: 4]=system_error_code;
    assign slave_ready[2]=time_ready;assign slave_error[2]=time_error;assign slave_rdata[64 +: 32]=time_rdata;
    assign slave_error_code[8 +: 4]=time_error_code;
    assign slave_ready[3]=member2_ready;assign slave_error[3]=member2_error;assign slave_rdata[96 +: 32]=member2_rdata;
    assign slave_error_code[12 +: 4]=member2_error_code;
    assign slave_ready[4]=member2_ready;assign slave_error[4]=member2_error;assign slave_rdata[128 +: 32]=member2_rdata;
    assign slave_error_code[16 +: 4]=member2_error_code;
    assign slave_ready[5]=member2_ready;assign slave_error[5]=member2_error;assign slave_rdata[160 +: 32]=member2_rdata;
    assign slave_error_code[20 +: 4]=member2_error_code;
    assign slave_ready[6]=member2_ready;assign slave_error[6]=member2_error;assign slave_rdata[192 +: 32]=member2_rdata;
    assign slave_error_code[24 +: 4]=member2_error_code;
    assign slave_ready[7]=member1_ready;assign slave_error[7]=member1_error;assign slave_rdata[224 +: 32]=member1_rdata;
    assign slave_error_code[28 +: 4]=member1_error_code[0 +: 4];
    assign slave_ready[8]=member1_ready;assign slave_error[8]=member1_error;assign slave_rdata[256 +: 32]=member1_rdata;
    assign slave_error_code[32 +: 4]=member1_error_code[4 +: 4];
    assign slave_ready[9]=member1_ready;assign slave_error[9]=member1_error;assign slave_rdata[288 +: 32]=member1_rdata;
    assign slave_error_code[36 +: 4]=member1_error_code[8 +: 4];
    assign slave_ready[10]=member1_ready;assign slave_error[10]=member1_error;assign slave_rdata[320 +: 32]=member1_rdata;
    assign slave_error_code[40 +: 4]=member1_error_code[12 +: 4];
    assign slave_ready[11]=member3_ready;assign slave_error[11]=member3_error;assign slave_rdata[352 +: 32]=member3_rdata;
    assign slave_error_code[44 +: 4]=member3_error_code[0 +: 4];
    assign slave_ready[12]=member3_ready;assign slave_error[12]=member3_error;assign slave_rdata[384 +: 32]=member3_rdata;
    assign slave_error_code[48 +: 4]=member3_error_code[4 +: 4];
    assign slave_ready[13]=member3_ready;assign slave_error[13]=member3_error;assign slave_rdata[416 +: 32]=member3_rdata;
    assign slave_error_code[52 +: 4]=member3_error_code[8 +: 4];
    assign slave_ready[14]=member3_ready;assign slave_error[14]=member3_error;assign slave_rdata[448 +: 32]=member3_rdata;
    assign slave_error_code[56 +: 4]=member3_error_code[12 +: 4];
    assign slave_ready[15]=member3_ready;assign slave_error[15]=member3_error;assign slave_rdata[480 +: 32]=member3_rdata;
    assign slave_error_code[60 +: 4]=member3_error_code[16 +: 4];
    assign slave_ready[16]=member3_ready;assign slave_error[16]=member3_error;assign slave_rdata[512 +: 32]=member3_rdata;
    assign slave_error_code[64 +: 4]=member3_error_code[20 +: 4];
    assign slave_ready[17]=member3_ready;assign slave_error[17]=member3_error;assign slave_rdata[544 +: 32]=member3_rdata;
    assign slave_error_code[68 +: 4]=member3_error_code[24 +: 4];
    assign slave_ready[18]=motor_ready;assign slave_error[18]=motor_error;assign slave_rdata[576 +: 32]=motor_rdata;
    assign slave_error_code[72 +: 4]=motor_error_code;
    cfg_status_poller u_poller(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_control_n),
        .cfg_valid(master_valid[2]),
        .cfg_write(master_write[2]),
        .cfg_addr(master_addr[64 +: 32]),
        .cfg_wdata(master_wdata[64 +: 32]),
        .cfg_wstrb(master_wstrb[8 +: 4]),
        .cfg_ready(master_ready[2]),
        .cfg_error(master_error[2]),
        .cfg_rdata(master_rdata[64 +: 32]),
        .module_status(module_status),
        .module_errors(module_errors),
        .module_present(module_present),
        .timeout_count(poll_timeouts)
    );
    cmd_decoder #(.ACTION_TIMEOUT(300000000)) u_decoder(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_control_n),
        .timestamp_now(timestamp_now),
        .command_valid(command_valid),
        .command_done(command_done),
        .command_status(command_status),
        .command_sequence(command_sequence),
        .command_payload_bytes(command_payload_bytes),
        .command_source(command_source),
        .command_id(command_id),
        .action_valid(action_valid),
        .action_ready(action_ready),
        .action_status(action_status),
        .action_code(action_code),
        .action_source(action_source),
        .action_args(action_args),
        .payload_read_word(payload_word),
        .payload_read_data(payload_data),
        .cfg_valid(master_valid[0]),
        .cfg_write(master_write[0]),
        .cfg_addr(master_addr[0 +: 32]),
        .cfg_wdata(master_wdata[0 +: 32]),
        .cfg_wstrb(master_wstrb[0 +: 4]),
        .cfg_ready(master_ready[0]),
        .cfg_error(master_error[0]),
        .cfg_rdata(master_rdata[0 +: 32]),
        .cfg_error_code(master_error_code[0 +: 4]),
        .m_valid(response_valid),
        .m_ready(response_ready),
        .m_data(response_data),
        .m_keep(response_keep),
        .m_sof(response_sof),
        .m_last(response_last),
        .m_source_id(response_source_id),
        .m_msg_id(response_msg_id),
        .m_timestamp(response_timestamp),
        .m_cycle_id(response_cycle_id),
        .m_flags(response_flags),
        .m_frame_type(response_frame_type),
        .m_sequence(response_sequence),
        .m_sequence_valid(response_sequence_valid)
    );
    action_controller u_actions(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_control_n),
        .action_valid(action_valid),
        .action_ready(action_ready),
        .action_status(action_status),
        .action_code(action_code),
        .action_source(action_source),
        .action_args(action_args),
        .stop_flush(stop_flush),
        .acquisition_running(acquisition_requested),
        .cfg_valid(master_valid[1]),
        .cfg_write(master_write[1]),
        .cfg_addr(master_addr[32 +: 32]),
        .cfg_wdata(master_wdata[32 +: 32]),
        .cfg_wstrb(master_wstrb[4 +: 4]),
        .cfg_ready(master_ready[1]),
        .cfg_error(master_error[1]),
        .cfg_rdata(master_rdata[32 +: 32]),
        .cfg_error_code(master_error_code[4 +: 4]),
        .channel_datapath_idle(channel_idle),
        .sensor_datapath_idle(sensor_level==0 && !(|sensor_valid)),
        .busy(action_busy)
    );
    assign acquisition_running=global_enable && ((|wms_running) || module_status[224] || module_status[256] || module_status[352] || module_status[384] || module_status[416] || module_status[448] || module_status[480] || module_status[512] || module_status[544]);
    status_manager u_status(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .timestamp_now(timestamp_now),
        .time_sync_valid(time_sync_valid),
        .module_status(module_status),
        .module_errors(module_errors),
        .module_present(module_present),
        .system_status(module_status[31:0]),
        .total_drop_count(total_drops),
        .reset_reason(reset_reason),
        .sync_event_pulse(sync_event_pulse),
        .sync_seq(sync_seq),
        .sync_event_tick(sync_event_tick),
        .sync_event_gnss_tag(sync_event_gnss_tag),
        .sync_event_gnss_valid(sync_event_gnss_valid),
        .motor_done(motor_done),
        .motion_id(motion_id),
        .motor_position(motor_position),
        .motor_remaining(motor_remaining),
        .motor_errors(motor_errors),
        .error_summary(module_error_summary),
        .module_irq(module_irq),
        .event_drop_count(event_drops),
        .m_valid(events_valid),
        .m_ready(events_ready),
        .m_data(events_data),
        .m_keep(events_keep),
        .m_sof(events_sof),
        .m_last(events_last),
        .m_source_id(events_source_id),
        .m_msg_id(events_msg_id),
        .m_timestamp(events_timestamp),
        .m_cycle_id(events_cycle_id),
        .m_flags(events_flags),
        .m_frame_type(event_frame_type),
        .queue_level(event_queue_level)
    );
    assign sensor_level=device_level[0 +: 32]+device_level[32 +: 32]+device_level[64 +: 32]+device_level[96 +: 32]+device_level[128 +: 32]+device_level[160 +: 32]+device_level[192 +: 32];
    assign total_drops=raw0_drop_count+raw1_drop_count+event_drops+forced_clear_count+packet_errors+device_drop[0 +: 32]+device_drop[32 +: 32]+device_drop[64 +: 32]+device_drop[96 +: 32]+device_drop[128 +: 32]+device_drop[160 +: 32]+device_drop[192 +: 32]+gate_drops[0 +: 32]+gate_drops[32 +: 32]+gate_drops[64 +: 32]+gate_drops[96 +: 32]+gate_drops[128 +: 32]+gate_drops[160 +: 32]+gate_drops[192 +: 32]+gate_drops[224 +: 32]+gate_drops[256 +: 32]+gate_drops[288 +: 32]+gate_drops[320 +: 32]+gate_drops[352 +: 32];
    system_registers #(.GPIF_CLK_HZ(GPIF_CLK_HZ),.USE_EXTERNAL_CLOCK_FAULTS(1)) u_system(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_power_n),
        .cfg_valid(slave_valid[0] || slave_valid[1] || slave_valid[19] || slave_valid[20]),
        .cfg_write(slave_write),
        .cfg_addr(slave_addr),
        .cfg_wdata(slave_wdata),
        .cfg_wstrb(slave_wstrb),
        .cfg_ready(system_ready),
        .cfg_error(system_error),
        .cfg_rdata(system_rdata),
        .cfg_error_code(system_error_code),
        .timestamp_now(timestamp_now),
        .clock_locked(rst_operational_n),
        .link_ready(link_ready),
        .acquisition_running(acquisition_running),
        .watchdog_expired(watchdog_expired),
        .module_error_summary(module_error_summary | ((|sys_gpif_counters[127:96]) ? 32'h20 : 32'd0)),
        .module_irq(module_irq),
        .stream_mask(stream_mask),
        .raw_stream_mask(raw_stream_mask),
        .arb_mode(arb_mode),
        .max_high_burst(max_high_burst),
        .tx_high_water(tx_high_water),
        .fx3_reset_ms(fx3_reset_ms),
        .fx3_reset_request(fx3_reset_request),
        .global_enable(global_enable),
        .soft_reset_pulse(soft_reset_pulse),
        .watchdog_kick(watchdog_kick),
        .watchdog_timeout_ms(watchdog_timeout_ms),
        .reset_mask(reset_mask),
        .reset_reason(reset_reason),
        .clock_fault_count(clock_fault_count),
        .stream_enable(stream_enable),
        .usb_enable(usb_enable),
        .clock_reset_request(clock_reset_request),
        .stream_reset_pulse(stream_reset_pulse),
        .stream_clear_pulse(stream_clear_pulse),
        .usb_clear_pulse(usb_clear_pulse),
        .protocol_error_count(protocol_errors),
        .crc_error_count(crc_errors),
        .tx_fifo_level(tx_level),
        .rx_fifo_level(rx_level),
        .total_drop_count(total_drops),
        .adc0_fifo_level(raw0_level),
        .adc1_fifo_level(raw1_level),
        .dila0_fifo_level(dila0_fifo_level),
        .dila1_fifo_level(dila1_fifo_level),
        .sensor_fifo_level(sensor_level),
        .msg_pending_mask({26'd0,arb_pending[5:0]}),
        .bulk_pending_mask({28'd0,arb_pending[9:6]}),
        .arb_grant_count(arb_grants),
        .tx_word_count(tx_count64),
        .rx_word_count(rx_count64),
        .gpif_stall_count(sys_gpif_counters[128 +: 32]),
        .last_sequence_rx(sequence_rx),
        .last_sequence_tx(sequence_tx),
        .error_summary(system_errors),
        .irq_summary(irq_summary),
        .clock_fault_total(clock_fault_sys)
    );
    assign arb_in_valid[0]=response_valid;
    assign response_ready=arb_in_ready[0];
    assign arb_in_data[0 +: 32]=response_data;
    assign arb_in_keep[0 +: 4]=response_keep;
    assign arb_in_sof[0]=response_sof;
    assign arb_in_last[0]=response_last;
    assign arb_in_source_id[0 +: 16]=response_source_id;
    assign arb_in_msg_id[0 +: 16]=response_msg_id;
    assign arb_in_timestamp[0 +: 64]=response_timestamp;
    assign arb_in_cycle_id[0 +: 32]=response_cycle_id;
    assign arb_in_flags[0 +: 32]=response_flags;
    assign arb_in_valid[1]=events_gated_valid[0];
    assign events_gated_ready[0]=arb_in_ready[1];
    assign arb_in_data[32 +: 32]=events_gated_data[0 +: 32];
    assign arb_in_keep[4 +: 4]=events_gated_keep[0 +: 4];
    assign arb_in_sof[1]=events_gated_sof[0];
    assign arb_in_last[1]=events_gated_last[0];
    assign arb_in_source_id[16 +: 16]=events_gated_source_id[0 +: 16];
    assign arb_in_msg_id[16 +: 16]=events_gated_msg_id[0 +: 16];
    assign arb_in_timestamp[64 +: 64]=events_gated_timestamp[0 +: 64];
    assign arb_in_cycle_id[32 +: 32]=events_gated_cycle_id[0 +: 32];
    assign arb_in_flags[32 +: 32]=events_gated_flags[0 +: 32];
    assign arb_in_valid[2]=events_gated_valid[1];
    assign events_gated_ready[1]=arb_in_ready[2];
    assign arb_in_data[64 +: 32]=events_gated_data[32 +: 32];
    assign arb_in_keep[8 +: 4]=events_gated_keep[4 +: 4];
    assign arb_in_sof[2]=events_gated_sof[1];
    assign arb_in_last[2]=events_gated_last[1];
    assign arb_in_source_id[32 +: 16]=events_gated_source_id[16 +: 16];
    assign arb_in_msg_id[32 +: 16]=events_gated_msg_id[16 +: 16];
    assign arb_in_timestamp[128 +: 64]=events_gated_timestamp[64 +: 64];
    assign arb_in_cycle_id[64 +: 32]=events_gated_cycle_id[32 +: 32];
    assign arb_in_flags[64 +: 32]=events_gated_flags[32 +: 32];
    assign arb_in_valid[3]=sensor_gated_valid[2];
    assign sensor_gated_ready[2]=arb_in_ready[3];
    assign arb_in_data[96 +: 32]=sensor_gated_data[64 +: 32];
    assign arb_in_keep[12 +: 4]=sensor_gated_keep[8 +: 4];
    assign arb_in_sof[3]=sensor_gated_sof[2];
    assign arb_in_last[3]=sensor_gated_last[2];
    assign arb_in_source_id[48 +: 16]=sensor_gated_source_id[32 +: 16];
    assign arb_in_msg_id[48 +: 16]=sensor_gated_msg_id[32 +: 16];
    assign arb_in_timestamp[192 +: 64]=sensor_gated_timestamp[128 +: 64];
    assign arb_in_cycle_id[96 +: 32]=sensor_gated_cycle_id[64 +: 32];
    assign arb_in_flags[96 +: 32]=sensor_gated_flags[64 +: 32];
    assign arb_in_valid[4]=hub_valid;
    assign hub_ready=arb_in_ready[4];
    assign arb_in_data[128 +: 32]=hub_data;
    assign arb_in_keep[16 +: 4]=hub_keep;
    assign arb_in_sof[4]=hub_sof;
    assign arb_in_last[4]=hub_last;
    assign arb_in_source_id[64 +: 16]=hub_source_id;
    assign arb_in_msg_id[64 +: 16]=hub_msg_id;
    assign arb_in_timestamp[256 +: 64]=hub_timestamp;
    assign arb_in_cycle_id[128 +: 32]=hub_cycle_id;
    assign arb_in_flags[128 +: 32]=hub_flags;
    assign arb_in_valid[5]=events_gated_valid[2];
    assign events_gated_ready[2]=arb_in_ready[5];
    assign arb_in_data[160 +: 32]=events_gated_data[64 +: 32];
    assign arb_in_keep[20 +: 4]=events_gated_keep[8 +: 4];
    assign arb_in_sof[5]=events_gated_sof[2];
    assign arb_in_last[5]=events_gated_last[2];
    assign arb_in_source_id[80 +: 16]=events_gated_source_id[32 +: 16];
    assign arb_in_msg_id[80 +: 16]=events_gated_msg_id[32 +: 16];
    assign arb_in_timestamp[320 +: 64]=events_gated_timestamp[128 +: 64];
    assign arb_in_cycle_id[160 +: 32]=events_gated_cycle_id[64 +: 32];
    assign arb_in_flags[160 +: 32]=events_gated_flags[64 +: 32];
    assign arb_in_valid[6]=raw_valid[0];
    assign raw_ready[0]=arb_in_ready[6];
    assign arb_in_data[192 +: 32]=raw_data[0 +: 32];
    assign arb_in_keep[24 +: 4]=raw_keep[0 +: 4];
    assign arb_in_sof[6]=raw_sof[0];
    assign arb_in_last[6]=raw_last[0];
    assign arb_in_source_id[96 +: 16]=raw_source_id[0 +: 16];
    assign arb_in_msg_id[96 +: 16]=raw_msg_id[0 +: 16];
    assign arb_in_timestamp[384 +: 64]=raw_timestamp[0 +: 64];
    assign arb_in_cycle_id[192 +: 32]=raw_cycle_id[0 +: 32];
    assign arb_in_flags[192 +: 32]=raw_flags[0 +: 32];
    assign arb_in_valid[7]=raw_valid[1];
    assign raw_ready[1]=arb_in_ready[7];
    assign arb_in_data[224 +: 32]=raw_data[32 +: 32];
    assign arb_in_keep[28 +: 4]=raw_keep[4 +: 4];
    assign arb_in_sof[7]=raw_sof[1];
    assign arb_in_last[7]=raw_last[1];
    assign arb_in_source_id[112 +: 16]=raw_source_id[16 +: 16];
    assign arb_in_msg_id[112 +: 16]=raw_msg_id[16 +: 16];
    assign arb_in_timestamp[448 +: 64]=raw_timestamp[64 +: 64];
    assign arb_in_cycle_id[224 +: 32]=raw_cycle_id[32 +: 32];
    assign arb_in_flags[224 +: 32]=raw_flags[32 +: 32];
    assign arb_in_valid[8]=dila_gated_valid[0];
    assign dila_gated_ready[0]=arb_in_ready[8];
    assign arb_in_data[256 +: 32]=dila_gated_data[0 +: 32];
    assign arb_in_keep[32 +: 4]=dila_gated_keep[0 +: 4];
    assign arb_in_sof[8]=dila_gated_sof[0];
    assign arb_in_last[8]=dila_gated_last[0];
    assign arb_in_source_id[128 +: 16]=dila_gated_source_id[0 +: 16];
    assign arb_in_msg_id[128 +: 16]=dila_gated_msg_id[0 +: 16];
    assign arb_in_timestamp[512 +: 64]=dila_gated_timestamp[0 +: 64];
    assign arb_in_cycle_id[256 +: 32]=dila_gated_cycle_id[0 +: 32];
    assign arb_in_flags[256 +: 32]=dila_gated_flags[0 +: 32];
    assign arb_in_valid[9]=dila_gated_valid[1];
    assign dila_gated_ready[1]=arb_in_ready[9];
    assign arb_in_data[288 +: 32]=dila_gated_data[32 +: 32];
    assign arb_in_keep[36 +: 4]=dila_gated_keep[4 +: 4];
    assign arb_in_sof[9]=dila_gated_sof[1];
    assign arb_in_last[9]=dila_gated_last[1];
    assign arb_in_source_id[144 +: 16]=dila_gated_source_id[16 +: 16];
    assign arb_in_msg_id[144 +: 16]=dila_gated_msg_id[16 +: 16];
    assign arb_in_timestamp[576 +: 64]=dila_gated_timestamp[64 +: 64];
    assign arb_in_cycle_id[288 +: 32]=dila_gated_cycle_id[32 +: 32];
    assign arb_in_flags[288 +: 32]=dila_gated_flags[32 +: 32];
    wire [7:0] arb_frame_type;wire [31:0] arb_sequence;wire arb_sequence_valid;
    stream_arbiter #(.N(10)) u_stream_arbiter(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .arb_mode(arb_mode),
        .max_high_burst(max_high_burst),
        .s_priority({2'd3,2'd3,2'd3,2'd3,2'd2,2'd2,2'd1,2'd1,2'd0,2'd0}),
        .s_valid(arb_in_valid),
        .s_ready(arb_in_ready),
        .s_data(arb_in_data),
        .s_keep(arb_in_keep),
        .s_sof(arb_in_sof),
        .s_last(arb_in_last),
        .s_source_id(arb_in_source_id),
        .s_msg_id(arb_in_msg_id),
        .s_timestamp(arb_in_timestamp),
        .s_cycle_id(arb_in_cycle_id),
        .s_flags(arb_in_flags),
        .m_valid(arb_valid),
        .m_ready(arb_ready),
        .m_data(arb_data),
        .m_keep(arb_keep),
        .m_sof(arb_sof),
        .m_last(arb_last),
        .m_source_id(arb_source_id),
        .m_msg_id(arb_msg_id),
        .m_timestamp(arb_timestamp),
        .m_cycle_id(arb_cycle_id),
        .m_flags(arb_flags),
        .s_frame_type({8'h10,8'h10,8'h10,8'h10,event_frame_type[23:16],8'h10,8'h10,event_frame_type[15:8],event_frame_type[7:0],response_frame_type}),
        .s_sequence({288'd0,response_sequence}),
        .s_sequence_valid({9'd0,response_sequence_valid}),
        .m_frame_type(arb_frame_type),
        .m_sequence(arb_sequence),
        .m_sequence_valid(arb_sequence_valid),
        .grant_count(arb_grants),
        .pending_mask(arb_pending)
    );
    data_packetizer u_packetizer(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_stream_n),
        .s_valid(arb_valid),
        .s_ready(arb_ready),
        .s_data(arb_data),
        .s_keep(arb_keep),
        .s_sof(arb_sof),
        .s_last(arb_last),
        .s_source_id(arb_source_id),
        .s_msg_id(arb_msg_id),
        .s_timestamp(arb_timestamp),
        .s_cycle_id(arb_cycle_id),
        .s_flags(arb_flags),
        .s_frame_type(arb_frame_type),
        .s_sequence(arb_sequence),
        .s_sequence_valid(arb_sequence_valid),
        .m_valid(packet_valid),
        .m_ready(packet_ready),
        .m_data(packet_data),
        .m_last(packet_last),
        .last_sequence(sequence_tx),
        .frame_count(packet_frames),
        .format_error_count(packet_errors),
        .busy(packet_busy)
    );
    gpif_transport_buffers u_transport(
        .reset_n(rst_transport_n),
        .sys_clk(sys_clk),
        .gpif_clk(gpif_clk),
        .tx_valid(packet_valid),
        .tx_ready(packet_ready),
        .tx_data(packet_data),
        .tx_last(packet_last),
        .rx_valid(rx_valid),
        .rx_ready(rx_ready),
        .rx_data(rx_data),
        .gpif_tx_valid(gt_valid),
        .gpif_tx_ready(gt_ready),
        .gpif_tx_data(gt_data),
        .gpif_tx_last(gt_last),
        .gpif_rx_valid(gr_valid),
        .gpif_rx_ready(gr_ready),
        .gpif_rx_data(gr_data),
        .sys_tx_level(tx_level),
        .sys_rx_level(rx_level),
        .gpif_tx_level(gpif_tx_level),
        .gpif_rx_free(gpif_rx_free)
    );
    wire gpif_reset_async=rst_transport_n && rst_gpif_power_n;
    (* ASYNC_REG="TRUE" *)reg [2:0] gpif_release;
    always @(posedge gpif_clk or negedge gpif_reset_async)
        if(!gpif_reset_async)gpif_release<=0;else gpif_release<={gpif_release[1:0],1'b1};
    wire rst_gpif_n=gpif_release[2];

    usb_fx3_gpif_if #(.SIMULATION(SIMULATION)) u_gpif(
        .gpif_clk(gpif_clk),
        .rst_gpif_n(rst_gpif_n),
        .usb_dq(FPGA_GPIF_DQ),
        .usb_ctl(FPGA_GPIF_CTL),
        .usb_pclk(FPGA_GPIF_PCLK),
        .tx_valid(gt_valid),
        .tx_ready(gt_ready),
        .tx_data(gt_data),
        .tx_last(gt_last),
        .rx_valid(gr_valid),
        .rx_ready(gr_ready),
        .rx_data(gr_data),
        .rx_free(gpif_rx_free),
        .tx_word_count(gpif_counters[0 +: 32]),
        .rx_word_count(gpif_counters[32 +: 32]),
        .tx_frame_count(gpif_counters[64 +: 32]),
        .error_count(gpif_counters[96 +: 32]),
        .stall_count(gpif_counters[128 +: 32]),
        .idle(gpif_idle)
    );
    counter_cdc u_usb_counter0(
        .src_clk(gpif_clk),
        .src_rst_n(rst_gpif_n),
        .dst_clk(sys_clk),
        .dst_rst_n(rst_transport_n),
        .src_count(gpif_counters[0 +: 32]),
        .dst_count(sys_gpif_counters[0 +: 32])
    );
    counter_cdc u_usb_counter1(
        .src_clk(gpif_clk),
        .src_rst_n(rst_gpif_n),
        .dst_clk(sys_clk),
        .dst_rst_n(rst_transport_n),
        .src_count(gpif_counters[32 +: 32]),
        .dst_count(sys_gpif_counters[32 +: 32])
    );
    counter_cdc u_usb_counter2(
        .src_clk(gpif_clk),
        .src_rst_n(rst_gpif_n),
        .dst_clk(sys_clk),
        .dst_rst_n(rst_transport_n),
        .src_count(gpif_counters[64 +: 32]),
        .dst_count(sys_gpif_counters[64 +: 32])
    );
    counter_cdc u_usb_counter3(
        .src_clk(gpif_clk),
        .src_rst_n(rst_gpif_n),
        .dst_clk(sys_clk),
        .dst_rst_n(rst_transport_n),
        .src_count(gpif_counters[96 +: 32]),
        .dst_count(sys_gpif_counters[96 +: 32])
    );
    counter_cdc u_usb_counter4(
        .src_clk(gpif_clk),
        .src_rst_n(rst_gpif_n),
        .dst_clk(sys_clk),
        .dst_rst_n(rst_transport_n),
        .src_count(gpif_counters[128 +: 32]),
        .dst_count(sys_gpif_counters[128 +: 32])
    );
    wire [31:0] tx_increment=sys_gpif_counters[31:0]-tx_previous;
    wire [31:0] rx_increment=sys_gpif_counters[63:32]-rx_previous;
    always @(posedge sys_clk or negedge rst_transport_n)
        if(!rst_transport_n)begin tx_count64<=0;rx_count64<=0;tx_previous<=0;rx_previous<=0;end
        else begin
            tx_count64<=tx_count64+tx_increment;rx_count64<=rx_count64+rx_increment;
            tx_previous<=sys_gpif_counters[31:0];rx_previous<=sys_gpif_counters[63:32];
        end

    word_to_byte_stream u_rx_bytes(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_transport_n),
        .s_valid(rx_valid),
        .s_ready(rx_ready),
        .s_data(rx_data),
        .m_valid(byte_valid),
        .m_ready(byte_ready),
        .m_data(byte_data)
    );
    vlp_cmd_rx u_command_rx(
        .sys_clk(sys_clk),
        .rst_sys_n(rst_transport_n),
        .s_valid(byte_valid),
        .s_ready(byte_ready),
        .s_data(byte_data),
        .command_valid(command_valid),
        .command_done(command_done),
        .command_status(command_status),
        .command_sequence(command_sequence),
        .command_payload_bytes(command_payload_bytes),
        .command_source(command_source),
        .command_id(command_id),
        .payload_read_word(payload_word),
        .payload_read_data(payload_data),
        .protocol_error_count(protocol_errors),
        .crc_error_count(crc_errors),
        .last_sequence(sequence_rx),
        .buffered_bytes(parser_level)
    );
endmodule
`default_nettype wire
