`timescale 1ns/1ps
module adc_ad4630_dual_if #(
    parameter integer SYS_CLK_HZ=100000000,
    parameter integer SIMULATION=0,
    parameter integer FIFO_DEPTH=256
)(
    input wire sys_clk, input wire rst_sys_n,
    input wire wms0_scan_start, input wire [31:0] wms0_cycle_id,
    input wire [31:0] wms0_sine_phase, input wire wms0_phase_valid,
    input wire wms1_scan_start, input wire [31:0] wms1_cycle_id,
    input wire [31:0] wms1_sine_phase, input wire wms1_phase_valid,
    input wire [63:0] timestamp_now, input wire time_sync_valid,
    input wire cfg_valid, input wire cfg_write, input wire [31:0] cfg_addr,
    input wire [31:0] cfg_wdata, input wire [3:0] cfg_wstrb,
    output wire cfg_ready, output wire [31:0] cfg_rdata, output wire cfg_error,
    output wire m0_valid, input wire m0_ready, output wire [233:0] m0_tagged_sample,
    output wire m1_valid, input wire m1_ready, output wire [233:0] m1_tagged_sample,
    input wire [1:0] external_drop_increment0, output wire capture_drop_pulse0,
    input wire [1:0] external_drop_increment1, output wire capture_drop_pulse1,
    output wire raw_enable0, output wire [31:0] sample_rate_actual0,
    output wire raw_enable1, output wire [31:0] sample_rate_actual1,
    output wire [31:0] capture_fifo_level0, output wire capture_idle0,
    output wire [31:0] capture_fifo_level1, output wire capture_idle1,
    output wire [31:0] expected_per_cycle0, output wire [31:0] expected_per_cycle1,
    input wire [7:0] adc_sdo, input wire adc_busy,
    output wire adc_sdi, output reg adc_rst_n, output reg adc_cnv,
    output wire adc_cs_n, output wire adc_sck,
    output wire [7:0] cfg_error_code
);
    localparam integer BOOT_TICKS=SIMULATION?20:SYS_CLK_HZ/250;
    localparam integer RESET_TICKS=SIMULATION?4:SYS_CLK_HZ/1000000;
    localparam integer SETTLE_TICKS=SIMULATION?20:SYS_CLK_HZ/1000;
    reg [3:0] state;
    reg [31:0] timer, period_count, conversion_age;
    reg [2:0] quiet_count;
    reg initialized, timeout_pulse, sample_pulse;
    reg [23:0] sample_word0, sample_word1;
    reg [193:0] capture_tag0, capture_tag1;
    reg [63:0] cycle_tick0, cycle_tick1;
    reg [31:0] tag_cycle0, tag_cycle1;
    reg [23:0] shift_word0, shift_word1;
    reg [2:0] nibble_count;
    reg cap_cs,cap_sck;
    reg busy_seen;
    reg in_flight0, in_flight1;
    (* ASYNC_REG="TRUE" *) reg busy_meta,busy_sync;
    wire enable0,enable1,soft_reset0,soft_reset1,clear_fifo0,clear_fifo1;
    wire timing_pending0;
    wire [31:0] period_ticks,cnv_ticks,busy_timeout;
    wire fifo_ready0,fifo_ready1;
    wire [31:0] fifo_level0,fifo_level1;
    wire [1:0] ready_bus,error_bus;
    wire [31:0] rdata0,rdata1;
    assign cfg_ready=|ready_bus;
    assign cfg_error=|error_bus;
    assign cfg_rdata=rdata0|rdata1;
    assign capture_fifo_level0=fifo_level0;
    assign capture_fifo_level1=fifo_level1;
    assign sample_rate_actual1=sample_rate_actual0;
    // Cancel on the write edge, before a pre-disable sample can be queued.
    wire control_write=cfg_valid && cfg_write && !cfg_error && cfg_wstrb[0];
    wire cancel0=clear_fifo0 || (control_write && cfg_addr==32'h4004 && !cfg_wdata[0]);
    wire cancel1=clear_fifo1 || (control_write && cfg_addr==32'h4104 && !cfg_wdata[0]);
    wire accept0=enable0 && !cancel0;
    wire accept1=enable1 && !cancel1;
    wire push0=sample_pulse && in_flight0 && accept0;
    wire push1=sample_pulse && in_flight1 && accept1;
    assign capture_idle0=!enable0 && !in_flight0 && !push0 && fifo_level0==0;
    assign capture_idle1=!enable1 && !in_flight1 && !push1 && fifo_level1==0;
    wire local_rst_n=rst_sys_n && !soft_reset0;
    reg spi_start;
    reg [2:0] init_index;
    reg [23:0] spi_word;
    wire spi_busy,spi_done,spi_cs,spi_sck,spi_oe;
    wire [7:0] spi_read;
    always @* begin
        case(init_index)
            0:spi_word=24'hbfff00;
            1:spi_word=24'h002080;
            2:spi_word=24'h802000;
            default:spi_word=24'h001401;
        endcase
    end
    adc_spi_master #(.HALF_TICKS(10),.CS_HOLD_TICKS(2)) u_spi (
        .clk(sys_clk),.rst_n(local_rst_n),.start(spi_start),.tx_word(spi_word),
        .read_enable(init_index==2),.sdi(adc_sdo[0]),.cs_n(spi_cs),.sck(spi_sck),
        .sdo(adc_sdi),.sdo_enable(spi_oe),.busy(spi_busy),.done(spi_done),.read_data(spi_read));
    assign adc_cs_n=initialized?cap_cs:spi_cs;
    assign adc_sck=initialized?cap_sck:spi_sck;
    adc_channel_regs #(.CHANNEL(0),.SYS_CLK_HZ(SYS_CLK_HZ),.DEFAULT_RATE(1000000),
        .SHARED_AD4630(1),.BASE_ADDR(32'h4000)) u_regs0(
        .clk(sys_clk),.rst_n(rst_sys_n),.scan_start(wms0_scan_start),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(ready_bus[0]),.cfg_rdata(rdata0),.cfg_error(error_bus[0]),.cfg_error_code(cfg_error_code[3:0]),
        .initialized(initialized),.phy_busy(state!=6),.capture_pulse(push0),
        .overflow_pulse(push0 && !fifo_ready0),.timeout_pulse(timeout_pulse && in_flight0),
        .align_pulse(state==4 && spi_done && init_index==2 && spi_read!=8'h80),
        .external_drop_increment(external_drop_increment0),.fifo_level(fifo_level0),.sync_count(32'd0),
        .enable(enable0),.raw_enable(raw_enable0),.soft_reset(soft_reset0),.clear_fifo(clear_fifo0),
        .period_ticks(period_ticks),.rate_actual(sample_rate_actual0),.cnv_ticks(cnv_ticks),.busy_timeout(busy_timeout),
        .expected_per_cycle(expected_per_cycle0),.error_status(),
        .shared_peer_enable(enable1),.shared_timing_pending(timing_pending0),
        .shared_rate_actual(sample_rate_actual0),.shared_cnv_ticks(cnv_ticks),.shared_busy_timeout(busy_timeout),
        .timing_pending(timing_pending0));
    sync_fifo #(.WIDTH(234),.DEPTH(FIFO_DEPTH)) u_capture_fifo0(
        .clk(sys_clk),.rst_n(rst_sys_n && !clear_fifo0),.s_valid(push0),.s_ready(fifo_ready0),
        .s_data({capture_tag0,6'd0,1'b0,
                 (sample_word0==24'h7fffff || sample_word0==24'h800000),{{8{sample_word0[23]}},sample_word0}}),
        .m_valid(m0_valid),.m_ready(m0_ready),.m_data(m0_tagged_sample),.level(fifo_level0),
        .full(),.empty(),.almost_full(),.full_stall_pulse());
    assign capture_drop_pulse0=push0 && !fifo_ready0;
    adc_channel_regs #(.CHANNEL(1),.SYS_CLK_HZ(SYS_CLK_HZ),.DEFAULT_RATE(1000000),
        .SHARED_AD4630(1),.BASE_ADDR(32'h4100)) u_regs1(
        .clk(sys_clk),.rst_n(rst_sys_n),.scan_start(wms1_scan_start),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(ready_bus[1]),.cfg_rdata(rdata1),.cfg_error(error_bus[1]),.cfg_error_code(cfg_error_code[7:4]),
        .initialized(initialized),.phy_busy(state!=6),.capture_pulse(push1),
        .overflow_pulse(push1 && !fifo_ready1),.timeout_pulse(timeout_pulse && in_flight1),
        .align_pulse(state==4 && spi_done && init_index==2 && spi_read!=8'h80),
        .external_drop_increment(external_drop_increment1),.fifo_level(fifo_level1),.sync_count(32'd0),
        .enable(enable1),.raw_enable(raw_enable1),.soft_reset(soft_reset1),.clear_fifo(clear_fifo1),
        .period_ticks(),.rate_actual(),.cnv_ticks(),.busy_timeout(),
        .expected_per_cycle(expected_per_cycle1),.error_status(),
        .shared_peer_enable(enable0),.shared_timing_pending(timing_pending0),
        .shared_rate_actual(sample_rate_actual0),.shared_cnv_ticks(cnv_ticks),.shared_busy_timeout(busy_timeout),
        .timing_pending());
    sync_fifo #(.WIDTH(234),.DEPTH(FIFO_DEPTH)) u_capture_fifo1(
        .clk(sys_clk),.rst_n(rst_sys_n && !clear_fifo1),.s_valid(push1),.s_ready(fifo_ready1),
        .s_data({capture_tag1,6'd0,1'b0,
                 (sample_word1==24'h7fffff || sample_word1==24'h800000),{{8{sample_word1[23]}},sample_word1}}),
        .m_valid(m1_valid),.m_ready(m1_ready),.m_data(m1_tagged_sample),.level(fifo_level1),
        .full(),.empty(),.almost_full(),.full_stall_pulse());
    assign capture_drop_pulse1=push1 && !fifo_ready1;
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            busy_meta<=0;busy_sync<=0;
            cycle_tick0<=0;tag_cycle0<=0;cycle_tick1<=0;tag_cycle1<=0;
        end else begin
            busy_meta<=adc_busy;busy_sync<=busy_meta;
            if(wms0_scan_start)begin cycle_tick0<=timestamp_now;tag_cycle0<=wms0_cycle_id;end
            if(wms1_scan_start)begin cycle_tick1<=timestamp_now;tag_cycle1<=wms1_cycle_id;end
        end
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            state<=0;timer<=0;adc_rst_n<=1;adc_cnv<=0;initialized<=0;
            timeout_pulse<=0;sample_pulse<=0;period_count<=0;conversion_age<=0;
            quiet_count<=4;
            cap_cs<=1;cap_sck<=0;busy_seen<=0;spi_start<=0;init_index<=0;
            sample_word0<=0;sample_word1<=0;shift_word0<=0;shift_word1<=0;nibble_count<=0;
            capture_tag0<=0;capture_tag1<=0;in_flight0<=0;in_flight1<=0;
        end else if(soft_reset0)begin
            state<=0;timer<=0;adc_rst_n<=1;adc_cnv<=0;initialized<=0;
            timeout_pulse<=0;sample_pulse<=0;period_count<=0;cap_cs<=1;cap_sck<=0;
            quiet_count<=4;
            spi_start<=0;init_index<=0;in_flight0<=0;in_flight1<=0;
        end else begin
            spi_start<=0;timeout_pulse<=0;sample_pulse<=0;
            if(!accept0)in_flight0<=0;
            if(!accept1)in_flight1<=0;
            if(sample_pulse || timeout_pulse)begin in_flight0<=0;in_flight1<=0;end
            // A transient disable must not shorten the physical CNV interval.
            if(initialized)begin
                if(period_count!=0)period_count<=period_count-1'b1;
            end else period_count<=0;
            // Keep the ADC digital interface quiet before the next CNV even
            // after a late BUSY response or an exhausted sample-period timer.
            if(!adc_cs_n || adc_sck)quiet_count<=4;
            else if(quiet_count!=0)quiet_count<=quiet_count-1'b1;
            case(state)
                0:if(timer==BOOT_TICKS-1)begin timer<=0;adc_rst_n<=0;state<=1;end else timer<=timer+1'b1;
                1:if(timer==RESET_TICKS-1)begin timer<=0;adc_rst_n<=1;state<=2;end else timer<=timer+1'b1;
                2:if(timer==SETTLE_TICKS-1)begin timer<=0;state<=3;end else timer<=timer+1'b1;
                3:begin spi_start<=1;state<=4;end
                4:if(spi_done)begin
                    if(init_index==2 && spi_read!=8'h80)begin timer<=0;init_index<=0;state<=0;end
                    else if(init_index==3)begin initialized<=1;state<=6;end
                    else begin init_index<=init_index+1'b1;timer<=0;state<=5;end
                end
                5:if(timer==10)state<=3;else timer<=timer+1'b1;
                6:if((accept0 || accept1) && !timing_pending0 && period_count==0 && quiet_count==0)begin
                    adc_cnv<=1;conversion_age<=0;busy_seen<=0;state<=7;
                    period_count<=period_ticks-1'b1;
                    in_flight0<=accept0;in_flight1<=accept1;
                    capture_tag0<={time_sync_valid,wms0_phase_valid,wms0_scan_start?timestamp_now:cycle_tick0,
                        timestamp_now,wms0_sine_phase,wms0_scan_start?wms0_cycle_id:tag_cycle0};
                    capture_tag1<={time_sync_valid,wms1_phase_valid,wms1_scan_start?timestamp_now:cycle_tick1,
                        timestamp_now,wms1_sine_phase,wms1_scan_start?wms1_cycle_id:tag_cycle1};
                end
                7:begin
                    conversion_age<=conversion_age+1'b1;
                    if(conversion_age+1>=cnv_ticks)adc_cnv<=0;
                    if(busy_sync)busy_seen<=1;
                    if(busy_seen && !busy_sync && conversion_age>=30)begin
                        cap_cs<=0;timer<=0;nibble_count<=0;shift_word0<=0;shift_word1<=0;state<=8;
                    end else if(conversion_age>=busy_timeout)begin
                        timeout_pulse<=1;adc_cnv<=0;state<=6;
                    end
                end
                8:if(timer==1)begin state<=9;timer<=0;end else timer<=timer+1'b1;
                9:begin
                    cap_sck<=1;
                    shift_word0<={shift_word0[19:0],adc_sdo[0],adc_sdo[1],adc_sdo[2],adc_sdo[3]};
                    shift_word1<={shift_word1[19:0],adc_sdo[4],adc_sdo[5],adc_sdo[6],adc_sdo[7]};
                    state<=12;
                end
                // Two SYS ticks per half-cycle leave a routed SCK/SDO
                // round-trip budget; capture SCK is 25 MHz at SYS=100 MHz.
                12:state<=10;
                10:begin
                    cap_sck<=0;
                    if(nibble_count==5)begin sample_word0<=shift_word0;sample_word1<=shift_word1;sample_pulse<=1;state<=13;end
                    else begin nibble_count<=nibble_count+1'b1;state<=14;end
                end
                13:state<=11;
                14:state<=9;
                11:begin cap_cs<=1;state<=6;end
                default:state<=0;
            endcase
        end
    end
endmodule
