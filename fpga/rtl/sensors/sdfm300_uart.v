`timescale 1ns/1ps
`include "sensor_cfg_codes.vh"
`include "project_defs.vh"
`include "register_map.vh"
`include "error_codes.vh"
// SDFM300 streams on power-up. CONTROL gates local reception only; no device commands.
module sdfm300_uart #(
    parameter integer SYS_CLK_HZ=100_000_000,
    parameter integer FIFO_DEPTH=256
)(
    input wire sys_clk, rst_sys_n,
    input wire uart_rxd, output wire uart_txd,
    input wire [63:0] timestamp_now,
    input wire time_sync_valid, input wire [31:0] time_sync_seq,
    input wire cfg_valid, cfg_write,
    input wire [31:0] cfg_addr, cfg_wdata, input wire [3:0] cfg_wstrb,
    output wire cfg_ready, output reg [31:0] cfg_rdata, output reg cfg_error,
    output wire m_valid, input wire m_ready,
    output wire [31:0] m_data, output wire [3:0] m_keep,
    output wire m_sof, m_last,
    output wire [15:0] m_source_id, m_msg_id,
    output wire [63:0] m_timestamp,
    output wire [31:0] m_cycle_id, m_flags,
    output wire monitor_online,
    output wire [31:0] monitor_errors,monitor_drop_count,monitor_fifo_level,
    output reg [3:0] cfg_error_code
);
    reg enabled;
    reg [31:0] baud, timeout_ticks, gap_ticks;
    reg [31:0] errors, frames, checksums, invalids, drops, timeouts, formats;
    reg [31:0] last_distance, offline_count;
    reg distance_valid, online, offline_latched, overflow_pending;
    wire selected=(cfg_addr[31:8]==(`REG_BASE_SDFM300 >> 8));
    wire [7:0] offset=cfg_addr[7:0];
    wire write_access=cfg_valid && cfg_ready && cfg_write && !cfg_error;
    reg soft_reset, clear_fifo;
    always @(posedge sys_clk) begin
        if (!rst_sys_n) begin soft_reset<=0; clear_fifo<=0; end
        else begin
            soft_reset<=write_access && offset==`REG_OFS_CONTROL && cfg_wstrb[0] && cfg_wdata[1];
            clear_fifo<=write_access && offset==`REG_OFS_CONTROL && cfg_wstrb[0] && cfg_wdata[3];
        end
    end
    wire local_rst_n=rst_sys_n && !soft_reset;
    assign cfg_ready=cfg_valid && selected;
    assign uart_txd=1'b1;
    wire rx_valid,rx_start,rx_error,rx_parity,rx_busy;
    wire [7:0] rx_data;
    uart_rx #(.SYS_CLK_HZ(SYS_CLK_HZ)) u_rx(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.enable(enabled),.baud_hz(baud),
        .data_bits(4'd8),.parity_mode(2'd0),.stop_bits(2'd1),.rxd(uart_rxd),
        .byte_valid(rx_valid),.byte_ready(1'b1),.byte_data(rx_data),.byte_start_pulse(rx_start),
        .framing_error_pulse(rx_error),.parity_error_pulse(rx_parity),.busy(rx_busy));
    wire frame_event,distance_event,checksum_event,invalid_event,format_event,timeout_event;
    wire [31:0] parsed_distance;
    wire [63:0] parsed_timestamp;
    wire parsed_sync;
    sdfm300_parser u_parser(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.enable(enabled),
        .byte_data(rx_data),.byte_valid(rx_valid),.byte_start(rx_start),.byte_error(rx_error|rx_parity),
        .timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),.gap_ticks(gap_ticks),
        .frame_pulse(frame_event),.distance_pulse(distance_event),.checksum_pulse(checksum_event),
        .invalid_pulse(invalid_event),.format_pulse(format_event),.timeout_pulse(timeout_event),
        .distance_mm(parsed_distance),.frame_timestamp(parsed_timestamp),.frame_sync(parsed_sync));
    reg [1:0] pack_beat;
    reg pack_valid;
    reg [31:0] pack_distance, pack_flags;
    reg [63:0] pack_timestamp;
    wire fifo_ready,fifo_full,fifo_afull,fifo_stall;
    wire [31:0] fifo_level;
    assign monitor_online=online;
    assign monitor_errors=errors;
    assign monitor_drop_count=drops;
    assign monitor_fifo_level=fifo_level;
    wire [31:0] pack_data=(pack_beat==0) ? 32'h00010001 :
        (pack_beat==1) ? {8'd4,`TLV_TYPE_U32,`TLV_TAG_DISTANCE_MM} : pack_distance;
    msg_stream_fifo #(.DEPTH(FIFO_DEPTH),.ALMOST_FULL_THRESHOLD(FIFO_DEPTH-3)) u_fifo(
        .clk(sys_clk),.rst_n(local_rst_n && !clear_fifo),
        .s_valid(pack_valid),.s_ready(fifo_ready),.s_data(pack_data),.s_keep(4'hf),
        .s_sof(pack_beat==0),.s_last(pack_beat==2),.s_source_id(`SRC_SDFM300),
        .s_msg_id(`MSG_SENSOR_TLV_RECORD),.s_timestamp(pack_timestamp),
        .s_cycle_id(`CYCLE_ID_NONE),.s_flags(pack_flags),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),
        .m_sof(m_sof),.m_last(m_last),.m_source_id(m_source_id),.m_msg_id(m_msg_id),
        .m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags),
        .full(fifo_full),.almost_full(fifo_afull),.level(fifo_level),.full_stall_pulse(fifo_stall));
    wire dropping=distance_event && (pack_valid || fifo_level>FIFO_DEPTH-3 || clear_fifo);
    wire offline_event=enabled && !offline_latched && offline_count>=timeout_ticks-1;
    reg [31:0] error_events;
    always @* begin
        error_events=0;
        if(checksum_event) error_events=error_events|`ERR_PROTOCOL_OR_CRC;
        if(format_event) error_events=error_events|`ERR_DATA_FORMAT;
        if(invalid_event) error_events=error_events|`ERR_DEVICE_REPORTED_ERROR;
        if(dropping) error_events=error_events|`ERR_FIFO_OVERFLOW;
        if(timeout_event || offline_event) error_events=error_events|`ERR_TIMEOUT;
        if(cfg_valid && cfg_ready && cfg_write && cfg_error) error_events=error_events|`ERR_CONFIG_RANGE;
    end
    integer integer_index;
    reg [31:0] write_mask;
    always @* begin
        write_mask=0;
        for(integer_index=0;integer_index<4;integer_index=integer_index+1)
            write_mask[integer_index*8+:8]={8{cfg_wstrb[integer_index]}};
    end

    reg [31:0] merged;
    reg known, writable, range_bad, busy_bad;
    integer k;
    always @* begin
        cfg_rdata=0; known=1; writable=0; range_bad=0; busy_bad=0;
        case(offset)
            `REG_OFS_ID_VERSION: cfg_rdata={`SRC_SDFM300,16'h0200};
            `REG_OFS_CONTROL: begin cfg_rdata={31'd0,enabled}; writable=1; end
            `REG_OFS_STATUS: begin
                cfg_rdata[`STATUS_BIT_ENABLED]=enabled;
                cfg_rdata[`STATUS_BIT_READY]=1;
                cfg_rdata[`STATUS_BIT_ONLINE]=online;
                cfg_rdata[`STATUS_BIT_FIFO_AFULL]=fifo_afull;
                cfg_rdata[`STATUS_BIT_OVERFLOW]=errors[`ERR_BIT_FIFO_OVERFLOW];
                cfg_rdata[`STATUS_BIT_ERROR]=|errors;
                cfg_rdata[`STATUS_BIT_TIME_SYNC]=time_sync_valid;
            end
            `REG_OFS_ERROR: begin cfg_rdata=errors; writable=1; end
            `REG_SDFM300_BAUD: begin cfg_rdata=baud; writable=1; end
            `REG_SDFM300_LAST_DISTANCE_MM: cfg_rdata=last_distance;
            `REG_SDFM300_DISTANCE_VALID: cfg_rdata={31'd0,distance_valid};
            `REG_SDFM300_RX_FRAME_COUNT: cfg_rdata=frames;
            `REG_SDFM300_CHECKSUM_ERR_COUNT: cfg_rdata=checksums;
            `REG_SDFM300_INVALID_COUNT: cfg_rdata=invalids;
            `REG_SDFM300_FIFO_LEVEL: cfg_rdata=fifo_level;
            `REG_SDFM300_DROP_COUNT: cfg_rdata=drops;
            8'h3c: begin cfg_rdata=timeout_ticks; writable=1; end
            8'h40: cfg_rdata=timeouts;
            8'h48: begin cfg_rdata=gap_ticks; writable=1; end
            8'h5c: cfg_rdata=formats;
            default: known=0;
        endcase
        merged=cfg_rdata;
        for(k=0;k<4;k=k+1) if(cfg_wstrb[k]) merged[k*8+:8]=cfg_wdata[k*8+:8];
        case(offset)
            `REG_OFS_CONTROL: range_bad=(merged & 32'hfffffff4)!=0;
            `REG_SDFM300_BAUD: begin
                range_bad=!(merged==9600 || merged==19200 || merged==38400 || merged==115200 ||
                    merged==230400 || merged==256000 || merged==460800) || merged>SYS_CLK_HZ/16;
                busy_bad=enabled;
            end
            8'h3c,8'h48: range_bad=merged==0;
            default: ;
        endcase
        cfg_error_code=`SENSOR_CFG_OK;
        if(cfg_valid && selected) begin
            if(!known || cfg_addr[1:0]!=0) cfg_error_code=`SENSOR_CFG_BAD_ADDRESS;
            else if(cfg_write && !writable) cfg_error_code=`SENSOR_CFG_READ_ONLY;
            else if(cfg_write && range_bad) cfg_error_code=`SENSOR_CFG_RANGE;
            else if(cfg_write && busy_bad) cfg_error_code=`SENSOR_CFG_BUSY;
        end
        cfg_error=(cfg_error_code!=`SENSOR_CFG_OK);
    end
    always @(posedge sys_clk) begin
        if(!local_rst_n) begin
            enabled<=0; baud<=460800; timeout_ticks<=SYS_CLK_HZ; gap_ticks<=SYS_CLK_HZ/100;
            errors<=0; frames<=0; checksums<=0; invalids<=0; drops<=0; timeouts<=0; formats<=0;
            last_distance<=0; distance_valid<=0; online<=0; offline_latched<=0;
            offline_count<=0; overflow_pending<=0;
            pack_beat<=0; pack_valid<=0; pack_distance<=0; pack_flags<=0; pack_timestamp<=0;
        end else begin
            errors<=errors|error_events;
            if(write_access) begin
                case(offset)
                    `REG_OFS_CONTROL: if(cfg_wstrb[0]) enabled<=cfg_wdata[0];
                    `REG_OFS_ERROR: errors<=(errors & ~(cfg_wdata & write_mask))|error_events;
                    `REG_SDFM300_BAUD: baud<=merged;
                    8'h3c: timeout_ticks<=merged;
                    8'h48: gap_ticks<=merged;
                    default: ;
                endcase
            end
            if(!enabled || (write_access && offset==`REG_OFS_CONTROL && cfg_wstrb[0] && !cfg_wdata[0])) begin
                offline_count<=0; offline_latched<=0; online<=0; distance_valid<=0;
            end else if(frame_event) begin offline_count<=0; offline_latched<=0; online<=1; end
            else if(offline_event) begin online<=0; distance_valid<=0; offline_latched<=1; end
            else if(!offline_latched) offline_count<=offline_count+1'b1;
            if(timeout_event || offline_event) timeouts<=timeouts+1'b1;
            if(frame_event) frames<=frames+1'b1;
            if(checksum_event) checksums<=checksums+1'b1;
            if(format_event) formats<=formats+1'b1;
            if(invalid_event) begin invalids<=invalids+1'b1; distance_valid<=0; end
            if(pack_valid && fifo_ready) begin
                if(pack_beat==2) begin pack_valid<=0; pack_beat<=0; end
                else pack_beat<=pack_beat+1'b1;
            end
            if(clear_fifo) begin pack_valid<=0; pack_beat<=0; end
            if(distance_event) begin
                last_distance<=parsed_distance; distance_valid<=1;
                if(dropping) begin drops<=drops+1'b1; overflow_pending<=1; end
                else begin
                    pack_valid<=1; pack_beat<=0; pack_distance<=parsed_distance;
                    pack_timestamp<=parsed_timestamp;
                    pack_flags<=32'd1 | (parsed_sync ? 32'd4 : 0) | (overflow_pending ? 32'd8 : 0);
                    overflow_pending<=0;
                end
            end
        end
    end
endmodule
