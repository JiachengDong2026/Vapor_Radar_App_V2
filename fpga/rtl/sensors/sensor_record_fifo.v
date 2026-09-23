`include "project_defs.vh"
module sensor_record_fifo #(
    parameter [15:0] SOURCE_ID=16'h0044,
    parameter integer FIFO_DEPTH=256,
    parameter integer MAX_BYTES=272
)(
    input wire sys_clk,rst_sys_n,clear_fifo,
    input wire record_valid,
    input wire [MAX_BYTES*8-1:0] record_data,
    input wire [8:0] record_length,
    input wire [15:0] record_msg_id,
    input wire [63:0] record_timestamp,
    input wire [31:0] record_flags,
    output reg accepted,drop_pulse,
    output reg [31:0] drop_count,
    output wire [31:0] fifo_level,
    output wire fifo_almost_full,
    output wire m_valid,input wire m_ready,
    output wire [31:0] m_data,output wire [3:0] m_keep,
    output wire m_sof,m_last,
    output wire [15:0] m_source_id,m_msg_id,
    output wire [63:0] m_timestamp,
    output wire [31:0] m_cycle_id,m_flags
);
    reg [MAX_BYTES*8-1:0] payload;
    reg [8:0] length,index;
    reg active,overflow_pending;
    reg [63:0] timestamp;
    reg [31:0] flags;
    reg [15:0] msg_id;
    wire ready,full,stall;
    wire last=index+4>=length;
    wire [8:0] remaining=length-index;
    wire [3:0] keep=remaining>=4?4'hf:remaining==3?4'h7:remaining==2?4'h3:4'h1;
    wire [9:0] required_beats=({1'b0,record_length}+3)>>2;
    msg_stream_fifo #(.DEPTH(FIFO_DEPTH),.ALMOST_FULL_THRESHOLD(FIFO_DEPTH-16)) u_fifo(
        .clk(sys_clk),.rst_n(rst_sys_n&&!clear_fifo),
        .s_valid(active),.s_ready(ready),.s_data(payload[31:0]),.s_keep(keep),
        .s_sof(index==0),.s_last(last),.s_source_id(SOURCE_ID),.s_msg_id(msg_id),
        .s_timestamp(timestamp),.s_cycle_id(`CYCLE_ID_NONE),.s_flags(flags),
        .m_valid(m_valid),.m_ready(m_ready),.m_data(m_data),.m_keep(m_keep),
        .m_sof(m_sof),.m_last(m_last),.m_source_id(m_source_id),.m_msg_id(m_msg_id),
        .m_timestamp(m_timestamp),.m_cycle_id(m_cycle_id),.m_flags(m_flags),
        .full(full),.almost_full(fifo_almost_full),.level(fifo_level),.full_stall_pulse(stall));
    always @(posedge sys_clk) begin
        if(!rst_sys_n) begin
            payload<=0;length<=0;index<=0;active<=0;overflow_pending<=0;
            timestamp<=0;flags<=0;msg_id<=0;drop_count<=0;accepted<=0;drop_pulse<=0;
        end else begin
            accepted<=0;drop_pulse<=0;
            if(active&&ready) begin
                if(last) active<=0;
                else begin payload<=payload>>32;index<=index+4;end
            end
            if(clear_fifo) begin active<=0;index<=0;end
            if(record_valid) begin
                if(active || clear_fifo || record_length==0 || record_length>MAX_BYTES ||
                    fifo_level+required_beats>FIFO_DEPTH) begin
                    drop_count<=drop_count+1'b1;drop_pulse<=1;overflow_pending<=1;
                end else begin
                    payload<=record_data;length<=record_length;index<=0;active<=1;
                    timestamp<=record_timestamp;flags<=record_flags|(overflow_pending?32'd8:0);
                    msg_id<=record_msg_id;accepted<=1;overflow_pending<=0;
                end
            end
        end
    end
endmodule
