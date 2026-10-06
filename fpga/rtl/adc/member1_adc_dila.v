module member1_adc_dila #(
    parameter integer SYS_CLK_HZ = 100000000,
    parameter integer SIMULATION = 0,
    parameter integer DUAL_AD4630 = 0
)(
    input wire        sys_clk,
    input wire        rst_sys_n,
    input wire [63:0] timestamp_now,
    input wire        time_sync_valid,
    input wire        wms0_scan_start,
    input wire [31:0] wms0_cycle_id,
    input wire [31:0] wms0_sine_phase,
    input wire        wms0_phase_valid,
    input wire        wms1_scan_start,
    input wire [31:0] wms1_cycle_id,
    input wire [31:0] wms1_sine_phase,
    input wire        wms1_phase_valid,
    input wire        cfg_valid,
    input wire        cfg_write,
    input wire [31:0] cfg_addr,
    input wire [31:0] cfg_wdata,
    input wire [3:0]  cfg_wstrb,
    output wire        cfg_ready,
    output wire [31:0] cfg_rdata,
    output wire        cfg_error,
    output wire        ADC_AD4630_SDI,
    output wire        ADC_AD4630_RSTN,
    output wire        ADC_AD4630_CNV,
    output wire        ADC_AD4630_CSN,
    output wire        ADC_AD4630_SCK,
    input wire        ADC_AD4630_BUSY,
    input wire [7:0]  ADC_AD4630_SDO,
    input wire        ADC_ADC3660_DA5,
    input wire        ADC_ADC3660_DA6,
    input wire        ADC_ADC3660_DB5,
    input wire        ADC_ADC3660_DB6,
    input wire        ADC_ADC3660_DCLK,
    input wire        ADC_ADC3660_FCLK,
    output wire        ADC_ADC3660_DCLKIN,
    output wire        ADC_ADC3660_CLKP,
    output wire        ADC_ADC3660_CLKN,
    output wire        ADC_ADC3660_SEN,
    output wire        ADC_ADC3660_SCLK,
    output wire        ADC_ADC3660_RST,
    output wire        ADC_ADC3660_SYNC,
    inout wire        ADC_ADC3660_SDIO,
    output wire        raw0_valid,
    input wire        raw0_ready,
    output wire [31:0] raw0_data,
    output wire [7:0]  raw0_flags,
    output wire [31:0] raw0_capture_cycle_id,
    output wire [31:0] raw0_capture_phase,
    output wire [63:0] raw0_capture_timestamp,
    output wire [63:0] raw0_cycle_timestamp,
    output wire        raw0_capture_phase_valid,
    output wire        raw0_capture_time_sync_valid,
    output wire        dila0_valid,
    input wire        dila0_ready,
    output wire [31:0] dila0_data,
    output wire [3:0]  dila0_keep,
    output wire        dila0_sof,
    output wire        dila0_last,
    output wire [15:0] dila0_source_id,
    output wire [15:0] dila0_msg_id,
    output wire [63:0] dila0_timestamp,
    output wire [31:0] dila0_cycle_id,
    output wire [31:0] dila0_flags,
    output wire        raw1_valid,
    input wire        raw1_ready,
    output wire [31:0] raw1_data,
    output wire [7:0]  raw1_flags,
    output wire [31:0] raw1_capture_cycle_id,
    output wire [31:0] raw1_capture_phase,
    output wire [63:0] raw1_capture_timestamp,
    output wire [63:0] raw1_cycle_timestamp,
    output wire        raw1_capture_phase_valid,
    output wire        raw1_capture_time_sync_valid,
    output wire        dila1_valid,
    input wire        dila1_ready,
    output wire [31:0] dila1_data,
    output wire [3:0]  dila1_keep,
    output wire        dila1_sof,
    output wire        dila1_last,
    output wire [15:0] dila1_source_id,
    output wire [15:0] dila1_msg_id,
    output wire [63:0] dila1_timestamp,
    output wire [31:0] dila1_cycle_id,
    output wire [31:0] dila1_flags,
    output wire [31:0] raw0_sample_rate_hz,
    output wire [31:0] raw1_sample_rate_hz,
    output wire [31:0] raw0_fifo_level,
    output wire [31:0] raw1_fifo_level,
    output wire [31:0] dila0_fifo_level,
    output wire [31:0] dila1_fifo_level,
    output wire raw0_idle,
    output wire raw1_idle,
    output wire dila0_idle,
    output wire dila1_idle,
    output wire [15:0] cfg_error_code
);
    wire [3:0] ready_bus,error_bus;
    wire [31:0] rdata0,rdata1,rdata2,rdata3;
    assign cfg_ready=|ready_bus;assign cfg_error=|error_bus;
    assign cfg_rdata=rdata0|rdata1|rdata2|rdata3;
    wire clear_request=cfg_valid && cfg_ready && !cfg_error && cfg_write && cfg_wstrb[0] && (cfg_wdata[1] || cfg_wdata[3]);
    wire adc0_clear=clear_request && cfg_addr==32'h4004;
    wire adc1_clear=clear_request && cfg_addr==32'h4104;
    wire dila0_clear=clear_request && cfg_addr==32'h5004;
    wire dila1_clear=clear_request && cfg_addr==32'h5104;
    wire [1:0] drop_increment0;
    wire capture_drop0,dila_drop0;
    wire adc0_valid,adc0_ready,raw0_enable,din0_valid,din0_ready;
    wire [233:0] adc0_pack,raw0_pack,din0_pack;
    wire [31:0] adc0_rate,adc0_expected,raw0_drops,din0_drops;
    wire [31:0] adc0_level,raw0_level,din0_level,frame0_level;
    wire adc0_idle,core0_idle;
    assign raw0_sample_rate_hz=adc0_rate;
    assign raw0_fifo_level=adc0_level+raw0_level;
    assign dila0_fifo_level=frame0_level;
    assign raw0_idle=adc0_idle && raw0_level==0;
    assign dila0_idle=adc0_idle && din0_level==0 && core0_idle;
    adc_stream_fanout u_fanout0(.clk(sys_clk),.rst_n(rst_sys_n),.raw_enable(raw0_enable),
        .clear_raw(adc0_clear),.clear_dila(adc0_clear|dila0_clear),
        .raw_fifo_level(raw0_level),.dila_fifo_level(din0_level),
        .s_valid(adc0_valid),.s_ready(adc0_ready),.s_data(adc0_pack),
        .raw_valid(raw0_valid),.raw_ready(raw0_ready),.raw_data(raw0_pack),
        .dila_valid(din0_valid),.dila_ready(din0_ready),.dila_data(din0_pack),
        .raw_drop_count(raw0_drops),.dila_drop_count(din0_drops),.drop_increment(drop_increment0),.dila_drop_pulse(dila_drop0));
    assign {raw0_capture_time_sync_valid,raw0_capture_phase_valid,raw0_cycle_timestamp,raw0_capture_timestamp,
        raw0_capture_phase,raw0_capture_cycle_id,raw0_flags,raw0_data}=raw0_pack;
    dila_core #(.SYS_CLK_HZ(SYS_CLK_HZ),.INPUT_RATE_HZ(1000000),.USE_CAPTURE_TAGS(1),
        .SOURCE_ID(16'h0030),.BASE_ADDR(32'h5000)) u_dila0(
        .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.sample_valid(din0_valid),.sample_ready(din0_ready),
        .sample_data(din0_pack[31:0]),.sample_flags(din0_pack[39:32]),.capture_tag(din0_pack[233:40]),
        .input_sample_rate_hz(adc0_rate),.expected_per_cycle(adc0_expected),.input_overflow_pulse(capture_drop0|dila_drop0),
        .wms_scan_start(wms0_scan_start),.wms_cycle_id(wms0_cycle_id),.wms_sine_phase(wms0_sine_phase),.wms_phase_valid(wms0_phase_valid),
        .timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(ready_bus[2]),.cfg_rdata(rdata2),.cfg_error(error_bus[2]),.cfg_error_code(cfg_error_code[11:8]),
        .m_valid(dila0_valid),.m_ready(dila0_ready),.m_data(dila0_data),.m_keep(dila0_keep),.m_sof(dila0_sof),.m_last(dila0_last),
        .m_source_id(dila0_source_id),.m_msg_id(dila0_msg_id),.m_timestamp(dila0_timestamp),.m_cycle_id(dila0_cycle_id),.m_flags(dila0_flags),
        .output_queue_level(frame0_level),.datapath_idle(core0_idle));
    wire [1:0] drop_increment1;
    wire capture_drop1,dila_drop1;
    wire adc1_valid,adc1_ready,raw1_enable,din1_valid,din1_ready;
    wire [233:0] adc1_pack,raw1_pack,din1_pack;
    wire [31:0] adc1_rate,adc1_expected,raw1_drops,din1_drops;
    wire [31:0] adc1_level,raw1_level,din1_level,frame1_level;
    wire adc1_idle,core1_idle;
    assign raw1_sample_rate_hz=adc1_rate;
    assign raw1_fifo_level=adc1_level+raw1_level;
    assign dila1_fifo_level=frame1_level;
    assign raw1_idle=adc1_idle && raw1_level==0;
    assign dila1_idle=adc1_idle && din1_level==0 && core1_idle;
    adc_stream_fanout u_fanout1(.clk(sys_clk),.rst_n(rst_sys_n),.raw_enable(raw1_enable),
        .clear_raw(adc1_clear),.clear_dila(adc1_clear|dila1_clear),
        .raw_fifo_level(raw1_level),.dila_fifo_level(din1_level),
        .s_valid(adc1_valid),.s_ready(adc1_ready),.s_data(adc1_pack),
        .raw_valid(raw1_valid),.raw_ready(raw1_ready),.raw_data(raw1_pack),
        .dila_valid(din1_valid),.dila_ready(din1_ready),.dila_data(din1_pack),
        .raw_drop_count(raw1_drops),.dila_drop_count(din1_drops),.drop_increment(drop_increment1),.dila_drop_pulse(dila_drop1));
    assign {raw1_capture_time_sync_valid,raw1_capture_phase_valid,raw1_cycle_timestamp,raw1_capture_timestamp,
        raw1_capture_phase,raw1_capture_cycle_id,raw1_flags,raw1_data}=raw1_pack;
    dila_core #(.SYS_CLK_HZ(SYS_CLK_HZ),.INPUT_RATE_HZ(DUAL_AD4630?1000000:12500000),.USE_CAPTURE_TAGS(1),
        .SOURCE_ID(16'h0031),.BASE_ADDR(32'h5100)) u_dila1(
        .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.sample_valid(din1_valid),.sample_ready(din1_ready),
        .sample_data(din1_pack[31:0]),.sample_flags(din1_pack[39:32]),.capture_tag(din1_pack[233:40]),
        .input_sample_rate_hz(adc1_rate),.expected_per_cycle(adc1_expected),.input_overflow_pulse(capture_drop1|dila_drop1),
        .wms_scan_start(wms1_scan_start),.wms_cycle_id(wms1_cycle_id),.wms_sine_phase(wms1_sine_phase),.wms_phase_valid(wms1_phase_valid),
        .timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(ready_bus[3]),.cfg_rdata(rdata3),.cfg_error(error_bus[3]),.cfg_error_code(cfg_error_code[15:12]),
        .m_valid(dila1_valid),.m_ready(dila1_ready),.m_data(dila1_data),.m_keep(dila1_keep),.m_sof(dila1_sof),.m_last(dila1_last),
        .m_source_id(dila1_source_id),.m_msg_id(dila1_msg_id),.m_timestamp(dila1_timestamp),.m_cycle_id(dila1_cycle_id),.m_flags(dila1_flags),
        .output_queue_level(frame1_level),.datapath_idle(core1_idle));
    generate if(DUAL_AD4630)begin:g_dual
        adc_ad4630_dual_if #(.SYS_CLK_HZ(SYS_CLK_HZ),.SIMULATION(SIMULATION)) u_adc_dual(
            .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),
            .wms0_scan_start(wms0_scan_start),.wms0_cycle_id(wms0_cycle_id),
            .wms0_sine_phase(wms0_sine_phase),.wms0_phase_valid(wms0_phase_valid),
            .wms1_scan_start(wms1_scan_start),.wms1_cycle_id(wms1_cycle_id),
            .wms1_sine_phase(wms1_sine_phase),.wms1_phase_valid(wms1_phase_valid),
            .timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),
            .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
            .cfg_ready(ready_bus[0]),.cfg_rdata(rdata0),.cfg_error(error_bus[0]),.cfg_error_code(cfg_error_code[7:0]),
            .m0_valid(adc0_valid),.m0_ready(adc0_ready),.m0_tagged_sample(adc0_pack),
            .m1_valid(adc1_valid),.m1_ready(adc1_ready),.m1_tagged_sample(adc1_pack),
            .external_drop_increment0(drop_increment0),.capture_drop_pulse0(capture_drop0),
            .raw_enable0(raw0_enable),.sample_rate_actual0(adc0_rate),.expected_per_cycle0(adc0_expected),
            .capture_fifo_level0(adc0_level),.capture_idle0(adc0_idle),
            .external_drop_increment1(drop_increment1),.capture_drop_pulse1(capture_drop1),
            .raw_enable1(raw1_enable),.sample_rate_actual1(adc1_rate),.expected_per_cycle1(adc1_expected),
            .capture_fifo_level1(adc1_level),.capture_idle1(adc1_idle),
            .adc_sdo(ADC_AD4630_SDO),.adc_busy(ADC_AD4630_BUSY),.adc_sdi(ADC_AD4630_SDI),
            .adc_rst_n(ADC_AD4630_RSTN),.adc_cnv(ADC_AD4630_CNV),.adc_cs_n(ADC_AD4630_CSN),.adc_sck(ADC_AD4630_SCK));
        assign ready_bus[1]=1'b0;
        assign error_bus[1]=1'b0;
        assign rdata1=32'd0;
        // The former ADC3660 is held quiescent in the production dual mode.
        assign ADC_ADC3660_DCLKIN=1'b0;
        if(SIMULATION)begin:g_unused_sim_clock
            assign ADC_ADC3660_CLKP=1'b0;
            assign ADC_ADC3660_CLKN=1'b1;
        end else begin:g_unused_hw_clock
            OBUFDS #(.IOSTANDARD("LVDS")) u_sampling_clock(
                .I(1'b0),.O(ADC_ADC3660_CLKP),.OB(ADC_ADC3660_CLKN));
        end
        assign ADC_ADC3660_SEN=1'b1;
        assign ADC_ADC3660_SCLK=1'b0;
        assign ADC_ADC3660_RST=1'b1;
        assign ADC_ADC3660_SYNC=1'b0;
        assign ADC_ADC3660_SDIO=1'bz;
    end else begin:g_legacy_adc
    adc_ad4630_if #(.SYS_CLK_HZ(SYS_CLK_HZ),.SIMULATION(SIMULATION)) u_adc0(
        .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.wms_scan_start(wms0_scan_start),.wms_cycle_id(wms0_cycle_id),
        .wms_sine_phase(wms0_sine_phase),.wms_phase_valid(wms0_phase_valid),.timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(ready_bus[0]),.cfg_rdata(rdata0),.cfg_error(error_bus[0]),.cfg_error_code(cfg_error_code[3:0]),
        .m_valid(adc0_valid),.m_ready(adc0_ready),.m_data(),.m_flags(),.m_tagged_sample(adc0_pack),
        .external_drop_increment(drop_increment0),.capture_drop_pulse(capture_drop0),.raw_enable(raw0_enable),.sample_rate_actual(adc0_rate),.expected_per_cycle(adc0_expected),
        .capture_fifo_level(adc0_level),.capture_idle(adc0_idle),
        .adc_sdo(ADC_AD4630_SDO),.adc_busy(ADC_AD4630_BUSY),.adc_sdi(ADC_AD4630_SDI),
        .adc_rst_n(ADC_AD4630_RSTN),.adc_cnv(ADC_AD4630_CNV),.adc_cs_n(ADC_AD4630_CSN),.adc_sck(ADC_AD4630_SCK));
    adc_adc3660_if #(.SYS_CLK_HZ(SYS_CLK_HZ),.SIMULATION(SIMULATION)) u_adc1(
        .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.wms_scan_start(wms1_scan_start),.wms_cycle_id(wms1_cycle_id),
        .wms_sine_phase(wms1_sine_phase),.wms_phase_valid(wms1_phase_valid),.timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(ready_bus[1]),.cfg_rdata(rdata1),.cfg_error(error_bus[1]),.cfg_error_code(cfg_error_code[7:4]),
        .m_valid(adc1_valid),.m_ready(adc1_ready),.m_data(),.m_flags(),.m_tagged_sample(adc1_pack),
        .external_drop_increment(drop_increment1),.capture_drop_pulse(capture_drop1),.raw_enable(raw1_enable),.sample_rate_actual(adc1_rate),.expected_per_cycle(adc1_expected),
        .capture_fifo_level(adc1_level),.capture_idle(adc1_idle),
        .adc_da5(ADC_ADC3660_DA5),.adc_da6(ADC_ADC3660_DA6),.adc_db5(ADC_ADC3660_DB5),.adc_db6(ADC_ADC3660_DB6),
        .adc_dclk(ADC_ADC3660_DCLK),.adc_fclk(ADC_ADC3660_FCLK),.adc_dclkin(ADC_ADC3660_DCLKIN),
        .adc_clkp(ADC_ADC3660_CLKP),.adc_clkn(ADC_ADC3660_CLKN),.adc_sen(ADC_ADC3660_SEN),.adc_sclk(ADC_ADC3660_SCLK),
        .adc_sdio(ADC_ADC3660_SDIO),.adc_reset(ADC_ADC3660_RST),.adc_sync(ADC_ADC3660_SYNC));
    end endgenerate
endmodule

