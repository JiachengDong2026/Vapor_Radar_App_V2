`include "sensor_cfg_codes.vh"
`timescale 1ns/1ps
`include "project_defs.vh"
`include "register_map.vh"
`include "error_codes.vh"
module tfa1500_uart #(
    parameter integer SYS_CLK_HZ=100_000_000,
    parameter integer FIFO_DEPTH=256
)(
    input wire sys_clk, rst_sys_n,
    input wire hf_rxd, lf_rxd, output wire uart_txd,
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
    localparam [2:0] RUN=0, SEND=1, DRAIN=2, QUIET=3, APPLY=4;
    reg [2:0] state, return_state;
    reg enabled;
    reg [1:0] requested_mode, active_mode;
    reg [31:0] baud, active_baud, timeout_ticks, silence_ticks, gap_ticks;
    reg [15:0] lf_scale;
    reg [7:0] lf_mask, version_cmd;
    reg [31:0] errors, frames, checksums, invalids, drops, timeouts, formats;
    reg [31:0] last_distance;
    reg distance_valid, online, offline_latched, overflow_pending;
    reg [31:0] quiet_count, offline_count;
    reg [63:0] tx_word;
    reg [3:0] tx_len, tx_index;
    wire tx_ready, tx_busy, tx_done;
    wire [1:0] target_mode=enabled ? requested_mode : 2'd0;
    wire changing=(active_mode!=target_mode || active_baud!=baud);
    wire selected=(cfg_addr[31:8]==(`REG_BASE_TFA1500 >> 8));
    wire [7:0] offset=cfg_addr[7:0];
    wire write_access=cfg_valid && cfg_ready && cfg_write && !cfg_error;
    // Register command pulses before using them in local reset trees.
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
    wire hf_valid,lf_valid,hf_start,lf_start,hf_error,lf_error,hf_busy,lf_busy;
    wire [7:0] hf_data,lf_data;
    wire hf_parity,lf_parity;
    uart_rx #(.SYS_CLK_HZ(SYS_CLK_HZ)) u_hf_rx(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.enable(1'b1),.baud_hz(active_baud),
        .data_bits(4'd8),.parity_mode(2'd0),.stop_bits(2'd1),.rxd(hf_rxd),
        .byte_valid(hf_valid),.byte_ready(1'b1),.byte_data(hf_data),.byte_start_pulse(hf_start),
        .framing_error_pulse(hf_error),.parity_error_pulse(hf_parity),.busy(hf_busy));
    uart_rx #(.SYS_CLK_HZ(SYS_CLK_HZ)) u_lf_rx(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.enable(1'b1),.baud_hz(active_baud),
        .data_bits(4'd8),.parity_mode(2'd0),.stop_bits(2'd1),.rxd(lf_rxd),
        .byte_valid(lf_valid),.byte_ready(1'b1),.byte_data(lf_data),.byte_start_pulse(lf_start),
        .framing_error_pulse(lf_error),.parity_error_pulse(lf_parity),.busy(lf_busy));
    uart_tx #(.SYS_CLK_HZ(SYS_CLK_HZ)) u_tx(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.enable(1'b1),.baud_hz(active_baud),
        .data_bits(4'd8),.parity_mode(2'd0),.stop_bits(2'd1),
        .byte_valid(state==SEND),.byte_ready(tx_ready),.byte_data(tx_word[63:56]),
        .txd(uart_txd),.busy(tx_busy),.frame_done_pulse(tx_done));
    wire frame_event, distance_event, checksum_event, invalid_event, format_event, timeout_event;
    wire [31:0] parsed_distance;
    wire [7:0] apd_temp,device_status;
    wire [63:0] parsed_timestamp;
    wire parsed_sync;
    tfa1500_parser u_parser(
        .sys_clk(sys_clk),.rst_sys_n(local_rst_n),.enable(active_mode!=0 && state==RUN && !changing),
        .high_mode(active_mode==2),.byte_data(active_mode==2 ? hf_data : lf_data),
        .byte_valid(active_mode==2 ? hf_valid : lf_valid),
        .byte_start(active_mode==2 ? hf_start : lf_start),
        .byte_error(active_mode==2 ? hf_error : lf_error),
        .timestamp_now(timestamp_now),.time_sync_valid(time_sync_valid),.gap_ticks(gap_ticks),
        .lf_mm_per_count(lf_scale),.lf_invalid_mask(lf_mask),
        .frame_pulse(frame_event),.distance_pulse(distance_event),.checksum_pulse(checksum_event),
        .invalid_pulse(invalid_event),.format_pulse(format_event),.timeout_pulse(timeout_event),
        .distance_mm(parsed_distance),.apd_temp(apd_temp),.device_status(device_status),
        .frame_timestamp(parsed_timestamp),.frame_sync(parsed_sync));
    function [63:0] lf_command;
        input [7:0] command;
        reg [7:0] data_hi;
        begin
            data_hi=(command==1 || command==2) ? 8'h20 : 0;
            lf_command={8'h55,command,8'h02,data_hi,8'h00,(8'h55^command^8'h02^data_hi),16'h0000};
        end
    endfunction
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
        .s_sof(pack_beat==0),.s_last(pack_beat==2),.s_source_id(`SRC_TFA1500),
        .s_msg_id(`MSG_SENSOR_TLV_RECORD),.s_timestamp(pack_timestamp),
        .s_cycle_id(`CYCLE_ID_NONE),.s_flags(pack_flags),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),
        .m_sof(m_sof),.m_last(m_last),.m_source_id(m_source_id),.m_msg_id(m_msg_id),
        .m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags),
        .full(fifo_full),.almost_full(fifo_afull),.level(fifo_level),.full_stall_pulse(fifo_stall));
    wire dropping=distance_event && (pack_valid || fifo_level>FIFO_DEPTH-3 || clear_fifo);
    wire offline_event=active_mode!=0 && state==RUN && !offline_latched && offline_count>=timeout_ticks-1;
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
    integer k;
    always @* begin
        cfg_rdata=0; cfg_error=0;
        case(offset)
            `REG_OFS_ID_VERSION: cfg_rdata={`SRC_TFA1500,16'h0100};
            `REG_OFS_CONTROL: cfg_rdata={31'd0,enabled};
            `REG_OFS_STATUS: begin
                cfg_rdata[`STATUS_BIT_ENABLED]=enabled;
                cfg_rdata[`STATUS_BIT_READY]=(state==RUN);
                cfg_rdata[`STATUS_BIT_CFG_PENDING]=changing;
                cfg_rdata[`STATUS_BIT_BUSY]=(state!=RUN);
                cfg_rdata[`STATUS_BIT_ONLINE]=online;
                cfg_rdata[`STATUS_BIT_FIFO_AFULL]=fifo_afull;
                cfg_rdata[`STATUS_BIT_OVERFLOW]=errors[`ERR_BIT_FIFO_OVERFLOW];
                cfg_rdata[`STATUS_BIT_ERROR]=|errors;
                cfg_rdata[`STATUS_BIT_TIME_SYNC]=time_sync_valid;
            end
            `REG_OFS_ERROR: cfg_rdata=errors;
            `REG_TFA_BAUD: cfg_rdata=baud;
            `REG_TFA_RANGE_MODE: cfg_rdata={30'd0,requested_mode};
            `REG_TFA_COMMAND: cfg_rdata=0;
            `REG_TFA_LAST_DISTANCE_MM: cfg_rdata=last_distance;
            `REG_TFA_DISTANCE_VALID: cfg_rdata={31'd0,distance_valid};
            `REG_TFA_APD_TEMP_RAW: cfg_rdata={24'd0,apd_temp};
            `REG_TFA_RX_FRAME_COUNT: cfg_rdata=frames;
            `REG_TFA_CHECKSUM_ERR_COUNT: cfg_rdata=checksums;
            `REG_TFA_HF_INVALID_COUNT: cfg_rdata=invalids;
            `REG_TFA_FIFO_LEVEL: cfg_rdata=fifo_level;
            `REG_TFA_DROP_COUNT: cfg_rdata=drops;
            8'h3c: cfg_rdata=timeout_ticks;
            8'h40: cfg_rdata=timeouts;
            8'h44: cfg_rdata=silence_ticks;
            8'h48: cfg_rdata=gap_ticks;
            8'h4c: cfg_rdata={16'd0,lf_scale};
            8'h50: cfg_rdata={24'd0,lf_mask};
            8'h54: cfg_rdata={24'd0,device_status};
            8'h58: cfg_rdata={24'd0,version_cmd};
            8'h5c: cfg_rdata=formats;
            default: cfg_error=1;
        endcase
        // Keep write validation independent of the wide read-only status mux.
        merged=0;
        case(offset)
            `REG_OFS_CONTROL: merged={31'd0,enabled};
            `REG_TFA_BAUD: merged=baud;
            `REG_TFA_RANGE_MODE: merged={30'd0,requested_mode};
            8'h3c: merged=timeout_ticks;
            8'h44: merged=silence_ticks;
            8'h48: merged=gap_ticks;
            8'h4c: merged={16'd0,lf_scale};
            8'h50: merged={24'd0,lf_mask};
            8'h58: merged={24'd0,version_cmd};
            default: merged=0;
        endcase
        for(k=0;k<4;k=k+1) if(cfg_wstrb[k]) merged[k*8+:8]=cfg_wdata[k*8+:8];
        if(cfg_addr[1:0]!=0) cfg_error=1;
        if(cfg_write) begin
            case(offset)
                `REG_OFS_CONTROL: if ((merged & 32'hfffffff0)!=0) cfg_error=1;
                `REG_OFS_ERROR: ;
                `REG_TFA_BAUD: if(merged<115200 || merged>SYS_CLK_HZ/16 ||
                    (requested_mode==2 && merged<500000)) cfg_error=1;
                `REG_TFA_RANGE_MODE: if(merged>2 || (merged==2 && baud<500000)) cfg_error=1;
                `REG_TFA_COMMAND: if(state!=RUN || changing || active_mode!=1 ||
                    !(merged==1 || merged==2 || merged==3 || merged==4) || !cfg_wstrb[0]) cfg_error=1;
                8'h3c,8'h44,8'h48: if(merged==0) cfg_error=1;
                8'h4c: if(merged==0 || merged>1000 || enabled || state!=RUN) cfg_error=1;
                8'h50,8'h58: if(merged>255 || enabled || state!=RUN) cfg_error=1;
                default: cfg_error=1;
            endcase
        end
        if(!cfg_valid || !selected) cfg_error=0;
    end
    always @(posedge sys_clk) begin
        if(!local_rst_n) begin
            enabled<=0; requested_mode<=2; active_mode<=0; baud<=500000; active_baud<=500000;
            state<=RUN; return_state<=RUN; tx_word<=0; tx_len<=0; tx_index<=0;
            timeout_ticks<=SYS_CLK_HZ; silence_ticks<=SYS_CLK_HZ/100; gap_ticks<=SYS_CLK_HZ/100;
            lf_scale<=10; lf_mask<=0; version_cmd<=8'hcb;
            errors<=0; frames<=0; checksums<=0; invalids<=0; drops<=0; timeouts<=0; formats<=0;
            last_distance<=0; distance_valid<=0; online<=0; offline_latched<=0;
            quiet_count<=0; offline_count<=0; overflow_pending<=0;
            pack_beat<=0; pack_valid<=0; pack_distance<=0; pack_flags<=0; pack_timestamp<=0;
        end else begin
            errors<=errors|error_events;
            if(write_access) begin
                case(offset)
                    `REG_OFS_CONTROL: if(cfg_wstrb[0]) enabled<=cfg_wdata[0];
                    `REG_OFS_ERROR: errors<=(errors & ~(cfg_wdata & write_mask))|error_events;
                    `REG_TFA_BAUD: baud<=merged;
                    `REG_TFA_RANGE_MODE: requested_mode<=merged[1:0];
                    8'h3c: timeout_ticks<=merged;
                    8'h44: silence_ticks<=merged;
                    8'h48: gap_ticks<=merged;
                    8'h4c: lf_scale<=merged[15:0];
                    8'h50: lf_mask<=merged[7:0];
                    8'h58: version_cmd<=merged[7:0];
                    default: ;
                endcase
            end
            case(state)
                RUN: begin
                    if(changing) begin
                        distance_valid<=0; online<=0;
                        if(active_mode!=0) begin
                            tx_word<=active_mode==2 ? 64'h55aaccccccccccfc : lf_command(0);
                            tx_len<=active_mode==2 ? 8 : 6; tx_index<=0;
                            state<=SEND; return_state<=QUIET;
                        end else begin state<=QUIET; quiet_count<=0; end
                    end else if(write_access && offset==`REG_TFA_COMMAND) begin
                        tx_word<=lf_command(merged==4 ? version_cmd : merged[7:0]);
                        tx_len<=6; tx_index<=0; state<=SEND; return_state<=RUN;
                    end
                end
                SEND: if(tx_ready) begin
                    if(tx_index==tx_len-1) state<=DRAIN;
                    else begin tx_index<=tx_index+1'b1; tx_word<={tx_word[55:0],8'd0}; end
                end
                DRAIN: if(tx_done) begin state<=return_state; quiet_count<=0; end
                QUIET: begin
                    if(hf_busy || lf_busy || hf_start || lf_start || hf_valid || lf_valid)
                        quiet_count<=0;
                    else if(quiet_count>=silence_ticks-1) state<=APPLY;
                    else quiet_count<=quiet_count+1'b1;
                end
                APPLY: begin
                    active_mode<=target_mode; active_baud<=baud;
                    if(target_mode!=0) begin
                        tx_word<=target_mode==2 ? 64'h55aacbccccccccfb : lf_command(2);
                        tx_len<=target_mode==2 ? 8 : 6; tx_index<=0;
                        state<=SEND; return_state<=RUN;
                    end else state<=RUN;
                end
                default: state<=RUN;
            endcase
            if(state!=RUN || changing || active_mode==0) begin offline_count<=0; offline_latched<=0; end
            else if(frame_event) begin offline_count<=0; offline_latched<=0; online<=1; end
            else if(offline_event) begin
                online<=0; distance_valid<=0; offline_latched<=1;
            end else if(!offline_latched) offline_count<=offline_count+1'b1;
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
    always @* begin
        cfg_error_code=`SENSOR_CFG_OK;
        if(cfg_ready && cfg_error)begin
            cfg_error_code=`SENSOR_CFG_RANGE;
            if(cfg_addr[1:0]!=0 || offset>8'h5c)cfg_error_code=`SENSOR_CFG_BAD_ADDRESS;
            else if(cfg_write)case(offset)
                8'h04,8'h0c,8'h10,8'h14,8'h3c,8'h44,8'h48:;
                8'h18:if((state!=RUN || changing || active_mode!=1) &&
                    (merged==1 || merged==2 || merged==3 || merged==4) && cfg_wstrb[0])
                    cfg_error_code=`SENSOR_CFG_BUSY;
                8'h4c:if((enabled || state!=RUN) && merged!=0 && merged<=1000)cfg_error_code=`SENSOR_CFG_BUSY;
                8'h50,8'h58:if((enabled || state!=RUN) && merged<=255)cfg_error_code=`SENSOR_CFG_BUSY;
                default:cfg_error_code=`SENSOR_CFG_READ_ONLY;
            endcase
        end
    end

endmodule

