`timescale 1ns/1ps
module adc_adc3660_if #(
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
    input wire adc_da5,input wire adc_da6,input wire adc_db5,input wire adc_db6,
    input wire adc_dclk,input wire adc_fclk,
    output wire adc_dclkin,output wire adc_clkp,output wire adc_clkn,
    output wire adc_sen,output wire adc_sclk,inout wire adc_sdio,
    output reg adc_reset,output wire adc_sync,
    output wire [3:0] cfg_error_code
);
    localparam integer BOOT_TICKS=SIMULATION?20:SYS_CLK_HZ/250;
    localparam integer RESET_TICKS=SIMULATION?20:SYS_CLK_HZ/500000;
    localparam integer CAL_TICKS=SIMULATION?64:200000*8;
    localparam integer FUSE_TICKS=SIMULATION?64:SYS_CLK_HZ/1000;
    reg [2:0] clock_count;
    assign adc_dclkin=clock_count[0];
    generate if(SIMULATION!=0)begin:g_sim_clock
        assign adc_clkp=clock_count[2];assign adc_clkn=~clock_count[2];
    end else begin:g_hw_clock
        OBUFDS #(.IOSTANDARD("LVDS")) u_sampling_clock(.I(clock_count[2]),.O(adc_clkp),.OB(adc_clkn));
    end endgenerate
    assign adc_sync=0;
    wire enable,soft_reset,clear_fifo;
    wire [31:0] period_ticks,cnv_ticks,busy_timeout,error_status;
    reg [3:0] state;
    reg [31:0] timer;
    reg initialized,spi_start;
    reg [7:0] init_index;
    `include "adc3660_init_rom.vh"
    wire spi_busy,spi_done,spi_sdo,spi_oe;
    wire [7:0] spi_read;
    wire local_rst_n=rst_sys_n && !soft_reset;
    adc_spi_master #(.HALF_TICKS(10)) u_spi(
        .clk(sys_clk),.rst_n(local_rst_n),.start(spi_start),.tx_word(init_word(init_index)),
        .read_enable(1'b0),.sdi(adc_sdio),.cs_n(adc_sen),.sck(adc_sclk),
        .sdo(spi_sdo),.sdo_enable(spi_oe),.busy(spi_busy),.done(spi_done),.read_data(spi_read));
    assign adc_sdio=spi_oe?spi_sdo:1'bz;
    wire rx_clk,rx_locked,rx_word_valid,rx_align_toggle;
    wire [15:0] rx_word;
    wire monitor_reset_request_n=rst_sys_n && rx_locked;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] monitor_reset_pipe;
    always @(posedge rx_clk or negedge monitor_reset_request_n)begin
        if(!monitor_reset_request_n)monitor_reset_pipe<=0;
        else monitor_reset_pipe<={monitor_reset_pipe[1:0],1'b1};
    end
    wire monitor_rst_n=monitor_reset_pipe[2];
    reg go,tag_active;
    reg rx_alive;
    (* ASYNC_REG="TRUE" *) reg alive_meta,alive_sync;
    reg alive_prev;
    reg [7:0] dclk_watchdog;
    always @(posedge rx_clk or negedge monitor_rst_n)begin
        if(!monitor_rst_n)rx_alive<=0;else rx_alive<=~rx_alive;
    end
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [1:0] rx_reset_pipe;
    wire queue_rst_n=local_rst_n && go;
    always @(posedge rx_clk or negedge queue_rst_n)begin
        if(!queue_rst_n)rx_reset_pipe<=0;
        else rx_reset_pipe<={rx_reset_pipe[0],1'b1};
    end
    adc3660_ddr_rx #(.SIMULATION(SIMULATION)) u_rx(
        .rst_n(local_rst_n),.dclk(adc_dclk),.fclk(adc_fclk),.da5(adc_da5),.da6(adc_da6),
        .go(go),.rx_clk(rx_clk),.clock_locked(rx_locked),.word_valid(rx_word_valid),
        .word_data(rx_word),.alignment_toggle(rx_align_toggle));
    wire word_ready,word_valid;
    wire [15:0] word_data;
    reg rx_overflow_toggle;
    wire rx_fifo_ready;
    always @(posedge rx_clk or negedge monitor_rst_n)begin
        if(!monitor_rst_n)rx_overflow_toggle<=0;
        else if(rx_word_valid && !rx_fifo_ready)rx_overflow_toggle<=~rx_overflow_toggle;
    end
    member1_async_fifo #(.WIDTH(16),.DEPTH(FIFO_DEPTH)) u_word_cdc(
        .wr_clk(rx_clk),.wr_rst_n(rx_reset_pipe[1]),.wr_valid(rx_word_valid),.wr_ready(rx_fifo_ready),.wr_data(rx_word),
        .wr_full(),.wr_full_stall_pulse(),.rd_clk(sys_clk),.rd_rst_n(queue_rst_n),
        .rd_valid(word_valid),.rd_ready(word_ready),.rd_data(word_data),.rd_empty());
    (* ASYNC_REG="TRUE" *) reg fc_meta,fc_sync,lock_meta,lock_sync;
    (* ASYNC_REG="TRUE" *) reg align_meta,align_sync,over_meta,over_sync;
    reg fc_prev,align_prev,over_prev;
    wire fc_edge=fc_sync!=fc_prev;
    wire align_pulse=align_sync!=align_prev;
    wire over_pulse=over_sync!=over_prev;
    reg [31:0] watchdog,sync_counter;
    reg timeout_pulse;
    reg [63:0] cycle_tick;
    reg [31:0] cycle_id;
    reg [193:0] tag_history[0:7];
    reg [2:0] tag_ptr;
    wire [2:0] history_index=tag_ptr-3'd3;
    wire tag_push=(tag_active || (go && fc_sync)) && fc_edge;
    wire tag_ready,tag_valid;
    wire [193:0] tag_data;
    wire [31:0] tag_level;
    sync_fifo #(.WIDTH(194),.DEPTH(FIFO_DEPTH)) u_tags(
        .clk(sys_clk),.rst_n(queue_rst_n),.s_valid(tag_push),.s_ready(tag_ready),.s_data(tag_history[history_index]),
        .m_valid(tag_valid),.m_ready(word_valid && word_ready),.m_data(tag_data),.level(tag_level),
        .full(),.empty(),.almost_full(),.full_stall_pulse());
    wire capture_pulse=word_valid && tag_valid;
    wire capture_ready;
    wire [31:0] fifo_level;
    assign capture_fifo_level=fifo_level;
    assign capture_idle=!enable && fifo_level==0;
    assign word_ready=tag_valid;
    // Pop both transport queues even if the capture FIFO is full: drop newest, never stop clocks.
    sync_fifo #(.WIDTH(234),.DEPTH(FIFO_DEPTH)) u_capture_fifo(
        .clk(sys_clk),.rst_n(rst_sys_n && !clear_fifo),.s_valid(capture_pulse && enable),.s_ready(capture_ready),
        .s_data({tag_data,6'd0,1'b0,(word_data==16'h7fff || word_data==16'h8000),{{16{word_data[15]}},word_data}}),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_tagged_sample),.level(fifo_level),
        .full(),.empty(),.almost_full(),.full_stall_pulse());
    assign capture_drop_pulse=(capture_pulse && enable && !capture_ready)||over_pulse||(tag_push&&!tag_ready);
    assign m_data=m_tagged_sample[31:0];assign m_flags=m_tagged_sample[39:32];
    adc_channel_regs #(.CHANNEL(1),.SYS_CLK_HZ(SYS_CLK_HZ),.DEFAULT_RATE(12500000),.BASE_ADDR(32'h4100)) u_regs(
        .clk(sys_clk),.rst_n(rst_sys_n),.scan_start(wms_scan_start),
        .cfg_valid(cfg_valid),.cfg_write(cfg_write),.cfg_addr(cfg_addr),.cfg_wdata(cfg_wdata),.cfg_wstrb(cfg_wstrb),
        .cfg_ready(cfg_ready),.cfg_rdata(cfg_rdata),.cfg_error(cfg_error),.cfg_error_code(cfg_error_code),
        .initialized(initialized && tag_active && lock_sync),.phy_busy(!initialized),
        .capture_pulse(capture_pulse && enable),
        .overflow_pulse((capture_pulse && enable && !capture_ready)||over_pulse||(tag_push&&!tag_ready)),
        .timeout_pulse(timeout_pulse),.align_pulse(align_pulse),
        .external_drop_increment(external_drop_increment),.fifo_level(fifo_level),.sync_count(sync_counter),.enable(enable),.raw_enable(raw_enable),
        .soft_reset(soft_reset),.clear_fifo(clear_fifo),.period_ticks(period_ticks),.rate_actual(sample_rate_actual),
        .cnv_ticks(cnv_ticks),.busy_timeout(busy_timeout),.expected_per_cycle(expected_per_cycle),.error_status(error_status));
    integer k;
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin
            clock_count<=0;fc_meta<=0;fc_sync<=0;fc_prev<=0;lock_meta<=0;lock_sync<=0;
            align_meta<=0;align_sync<=0;align_prev<=0;over_meta<=0;over_sync<=0;over_prev<=0;
            go<=0;tag_active<=0;watchdog<=0;sync_counter<=0;timeout_pulse<=0;
            alive_meta<=0;alive_sync<=0;alive_prev<=0;dclk_watchdog<=0;
            cycle_tick<=0;cycle_id<=0;tag_ptr<=0;
            for(k=0;k<8;k=k+1)tag_history[k]<=0;
        end else begin
            clock_count<=clock_count+1'b1;
            fc_meta<=adc_fclk;fc_sync<=fc_meta;fc_prev<=fc_sync;
            lock_meta<=rx_locked;lock_sync<=lock_meta;
            align_meta<=rx_align_toggle;align_sync<=align_meta;align_prev<=align_sync;
            over_meta<=rx_overflow_toggle;over_sync<=over_meta;over_prev<=over_sync;
            timeout_pulse<=0;
            alive_meta<=rx_alive;alive_sync<=alive_meta;alive_prev<=alive_sync;
            if(alive_sync!=alive_prev)dclk_watchdog<=0;
            else if(dclk_watchdog!=255)dclk_watchdog<=dclk_watchdog+1'b1;
            if(wms_scan_start)begin cycle_tick<=timestamp_now;cycle_id<=wms_cycle_id;end
            if(clock_count==7)begin
                tag_history[tag_ptr]<={time_sync_valid,wms_phase_valid,wms_scan_start?timestamp_now:cycle_tick,
                    timestamp_now,wms_sine_phase,wms_scan_start?wms_cycle_id:cycle_id};
                tag_ptr<=tag_ptr+1'b1;
            end
            if(!initialized || !lock_sync || soft_reset || align_pulse || over_pulse || (tag_push&&!tag_ready) || dclk_watchdog>=63)begin
                go<=0;tag_active<=0;watchdog<=0;
                if(initialized && dclk_watchdog==63)timeout_pulse<=1;
            end else begin
                if(fc_edge)begin
                    watchdog<=0;
                    if(fc_sync)begin
                        if(!go)go<=1;
                        else if(!tag_active)begin tag_active<=1;sync_counter<=sync_counter+1'b1;end
                    end
                end else if(watchdog==63)begin
                    timeout_pulse<=go;go<=0;tag_active<=0;watchdog<=0;
                end else watchdog<=watchdog+1'b1;
            end
        end
    end
    always @(posedge sys_clk or negedge rst_sys_n)begin
        if(!rst_sys_n)begin state<=0;timer<=0;adc_reset<=0;initialized<=0;spi_start<=0;init_index<=0;end
        else if(soft_reset)begin state<=0;timer<=0;adc_reset<=0;initialized<=0;spi_start<=0;init_index<=0;end
        else begin
            spi_start<=0;
            case(state)
                0:if(timer==BOOT_TICKS-1)begin timer<=0;adc_reset<=1;state<=1;end else timer<=timer+1'b1;
                1:if(timer==RESET_TICKS-1)begin timer<=0;adc_reset<=0;state<=2;end else timer<=timer+1'b1;
                2:if(timer==CAL_TICKS-1)begin timer<=0;state<=3;end else timer<=timer+1'b1;
                3:begin spi_start<=1;state<=4;end
                4:if(spi_done)begin
                    if(init_index==76)begin initialized<=1;state<=7;end
                    else begin timer<=0;init_index<=init_index+1'b1;state<=5;end
                end
                5:if(timer==(init_index==2?FUSE_TICKS:10))begin state<=3;timer<=0;end else timer<=timer+1'b1;
                7:begin end
                default:state<=0;
            endcase
        end
    end
endmodule


