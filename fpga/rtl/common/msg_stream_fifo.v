`include "stream_defs.vh"

module msg_stream_fifo #(
    parameter integer DEPTH = 256,
    parameter integer ALMOST_FULL_THRESHOLD = DEPTH-16
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        s_valid,
    output wire        s_ready,
    input  wire [`MSG_STREAM_DATA_W-1:0] s_data,
    input  wire [`MSG_STREAM_KEEP_W-1:0] s_keep,
    input  wire        s_sof,
    input  wire        s_last,
    input  wire [`STREAM_SOURCE_W-1:0] s_source_id,
    input  wire [`STREAM_MSG_ID_W-1:0] s_msg_id,
    input  wire [`STREAM_TIMESTAMP_W-1:0] s_timestamp,
    input  wire [`STREAM_CYCLE_ID_W-1:0] s_cycle_id,
    input  wire [`STREAM_FLAGS_W-1:0] s_flags,

    output wire        m_valid,
    input  wire        m_ready,
    output wire [`MSG_STREAM_DATA_W-1:0] m_data,
    output wire [`MSG_STREAM_KEEP_W-1:0] m_keep,
    output wire        m_sof,
    output wire        m_last,
    output wire [`STREAM_SOURCE_W-1:0] m_source_id,
    output wire [`STREAM_MSG_ID_W-1:0] m_msg_id,
    output wire [`STREAM_TIMESTAMP_W-1:0] m_timestamp,
    output wire [`STREAM_CYCLE_ID_W-1:0] m_cycle_id,
    output wire [`STREAM_FLAGS_W-1:0] m_flags,

    output wire        full,
    output wire        almost_full,
    output wire [31:0] level,
    output wire        full_stall_pulse
);
    localparam integer PACK_W =
        `MSG_STREAM_DATA_W + `MSG_STREAM_KEEP_W + 1 + 1 +
        `STREAM_SOURCE_W + `STREAM_MSG_ID_W + `STREAM_TIMESTAMP_W +
        `STREAM_CYCLE_ID_W + `STREAM_FLAGS_W;

    wire [PACK_W-1:0] s_pack = {
        s_flags, s_cycle_id, s_timestamp, s_msg_id, s_source_id,
        s_last, s_sof, s_keep, s_data
    };
    wire [PACK_W-1:0] m_pack;
    wire fifo_empty;
    
    sync_fifo #(
        .WIDTH(PACK_W),
        .DEPTH(DEPTH),
        .ALMOST_FULL_THRESHOLD(ALMOST_FULL_THRESHOLD)
    ) u_fifo (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_pack),
        .m_valid(m_valid), .m_ready(m_ready), .m_data(m_pack),
        .full(full), .empty(fifo_empty), .almost_full(almost_full),
        .level(level), .full_stall_pulse(full_stall_pulse)
    );

    assign {m_flags, m_cycle_id, m_timestamp, m_msg_id, m_source_id,
            m_last, m_sof, m_keep, m_data} = m_pack;
endmodule
