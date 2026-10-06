`timescale 1ns/1ps
module adc_ad4630_if #(
    parameter integer SYS_CLK_HZ=100000000,
    parameter integer SIMULATION=0,
    parameter integer FIFO_DEPTH=256
)(
    input wire sys_clk, input wire rst_sys_n,
    input wire wms_scan_start, input wire [31:0] wms_cycle_id,
    input wire [31:0] wms_sine_phase, input wire wms_phase_valid,
    input wire [63:0] timestamp_now, input wire time_sync_valid,
    input wire cfg_valid, input wire cfg_write, input wire [31:0] cfg_addr,
    input wire [31:0] cfg_wdata, input wire [3:0] cfg_wstrb,
    output wire cfg_ready, output wire [31:0] cfg_rdata, output wire cfg_error,
    output wire m_valid, input wire m_ready,
    output wire [31:0] m_data, output wire [7:0] m_flags,
    output wire [233:0] m_tagged_sample,
    input wire [1:0] external_drop_increment,output wire capture_drop_pulse,
    output wire raw_enable, output wire [31:0] sample_rate_actual,
    output wire [31:0] capture_fifo_level,output wire capture_idle,
    output wire [31:0] expected_per_cycle,
    input wire [7:0] adc_sdo, input wire adc_busy,
    output wire adc_sdi, output reg adc_rst_n, output reg adc_cnv,
    output wire adc_cs_n, output wire adc_sck,
    output wire [3:0] cfg_error_code
);
    localparam integer BOOT_TICKS=SIMULATION?20:SYS_CLK_HZ/250;
    localparam integer RESET_TICKS=SIMULATION?4:SYS_CLK_HZ/1000000;
    localparam integer SETTLE_TICKS=SIMULATION?20:SYS_CLK_HZ/1000;
    reg [3:0] state;
    reg [31:0] timer, period_count, conversion_age;
    reg [2:0] quiet_count;
    reg initialized, timeout_pulse, sample_pulse;
    reg [23:0] sample_word;
    reg [191:0] capture_tag;
    reg [63:0] cycle_tick;
    reg [31:0] tag_cycle;
    reg tag_phase_valid,tag_sync_valid;
    reg [23:0] shift_word;
    reg [2:0] nibble_count;
    reg cap_cs,cap_sck;
    reg busy_seen;
    (* ASYNC_REG="TRUE" *) reg busy_meta,busy_sync;
    wire enable,soft_reset,clear_fifo;
    wire [31:0] period_ticks,cnv_ticks,busy_timeout,error_status;
    wire fifo_ready;
    wire [31:0] fifo_level;
    assign capture_fifo_level=fifo_level;
    assign capture_idle=!enable && !sample_pulse && fifo_level==0 && state<=6;
    wire local_rst_n=rst_sys_n && !soft_reset;
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
    adc_channel_regs #(.CHANNEL(0),.SYS_CLK_HZ(SYS_CLK_HZ),.DEFAULT_RATE(1000000),.BASE_ADDR(32'h4000)) u_regs(
        .clk(sys_clk),.rst_n(rst_sys_n),.scan_start(wms_scan_start),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(cfg_ready),.cfg_rdata(cfg_rdata),.cfg_error(cfg_error),.cfg_error_code(cfg_error_code),
        .initialized(initialized),.phy_busy(state!=6),.capture_pulse(sample_pulse),
        .overflow_pulse(sample_pulse && !fifo_ready),.timeout_pulse(timeout_pulse),
        .align_pulse(state==4 && spi_done && init_index==2 && spi_read!=8'h80),
        .external_drop_increment(external_drop_increment),.fifo_level(fifo_level),.sync_count(32'd0),.enable(enable),.raw_enable(raw_enable),
        .soft_reset(soft_reset),.clear_fifo(clear_fifo),.period_ticks(period_ticks),
        .rate_actual(sample_rate_actual),.cnv_ticks(cnv_ticks),.busy_timeout(busy_timeout),
        .expected_per_cycle(expected_per_cycle),.error_status(error_status));
    sync_fifo #(.WIDTH(234),.DEPTH(FIFO_DEPTH)) u_capture_fifo(
        .clk(sys_clk),.rst_n(rst_sys_n && !clear_fifo),.s_valid(sample_pulse),.s_ready(fifo_ready),
        .s_data({tag_sync_valid,tag_phase_valid,capture_tag,6'd0,1'b0,
                 (sample_word==24'h7fffff || sample_word==24'h800000),{{8{sample_word[23]}},sample_word}}),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_tagged_sample),.level(fifo_level),
        .full(),.empty(),.almost_full(),.full_stall_pulse());
    assign capture_drop_pulse=sample_pulse && !fifo_ready;
    assign m_data=m_tagged_sample[31:0];assign m_flags=m_tagged_sample[39:32];
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin busy_meta<=0;busy_sync<=0;cycle_tick<=0;tag_cycle<=0;end
        else begin
            busy_meta<=adc_busy;busy_sync<=busy_meta;
            if(wms_scan_start)begin cycle_tick<=timestamp_now;tag_cycle<=wms_cycle_id;end
        end
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            state<=0;timer<=0;adc_rst_n<=1;adc_cnv<=0;initialized<=0;
            timeout_pulse<=0;sample_pulse<=0;period_count<=0;conversion_age<=0;
            quiet_count<=4;
            cap_cs<=1;cap_sck<=0;busy_seen<=0;spi_start<=0;init_index<=0;
            sample_word<=0;shift_word<=0;nibble_count<=0;capture_tag<=0;
            tag_phase_valid<=0;tag_sync_valid<=0;
        end else if(soft_reset)begin
            state<=0;timer<=0;adc_rst_n<=1;adc_cnv<=0;initialized<=0;
            timeout_pulse<=0;sample_pulse<=0;period_count<=0;cap_cs<=1;cap_sck<=0;
            quiet_count<=4;
            spi_start<=0;init_index<=0;
        end else begin
            spi_start<=0;timeout_pulse<=0;sample_pulse<=0;
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
                6:if(enable && period_count==0 && quiet_count==0)begin
                    adc_cnv<=1;conversion_age<=0;busy_seen<=0;state<=7;
                    period_count<=period_ticks-1'b1;
                    capture_tag<={wms_scan_start?timestamp_now:cycle_tick,timestamp_now,wms_sine_phase,wms_scan_start?wms_cycle_id:tag_cycle};
                    tag_phase_valid<=wms_phase_valid;tag_sync_valid<=time_sync_valid;
                end
                7:begin
                    conversion_age<=conversion_age+1'b1;
                    if(conversion_age+1>=cnv_ticks)adc_cnv<=0;
                    if(busy_sync)busy_seen<=1;
                    if(busy_seen && !busy_sync && conversion_age>=30)begin
                        cap_cs<=0;timer<=0;nibble_count<=0;shift_word<=0;state<=8;
                    end else if(conversion_age>=busy_timeout)begin
                        timeout_pulse<=1;adc_cnv<=0;state<=6;
                    end
                end
                8:if(timer==1)begin state<=9;timer<=0;end else timer<=timer+1'b1;
                9:begin
                    cap_sck<=1;
                    shift_word<={shift_word[19:0],adc_sdo[0],adc_sdo[1],adc_sdo[2],adc_sdo[3]};
                    state<=12;
                end
                // Two SYS ticks per half-cycle leave a routed SCK/SDO
                // round-trip budget; capture SCK is 25 MHz at SYS=100 MHz.
                12:state<=10;
                10:begin
                    cap_sck<=0;
                    if(nibble_count==5)begin sample_word<=shift_word;sample_pulse<=1;state<=13;end
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


