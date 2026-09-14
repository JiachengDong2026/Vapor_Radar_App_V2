`include "stream_defs.vh"

module sample_stream_fifo #(
    parameter integer DEPTH = 256,
    parameter integer ALMOST_FULL_THRESHOLD = DEPTH-16
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire        s_valid,
    output wire        s_ready,
    input  wire [`SAMPLE_STREAM_DATA_W-1:0] s_data,
    input  wire [`SAMPLE_STREAM_FLAGS_W-1:0] s_flags,

    output wire        m_valid,
    input  wire        m_ready,
    output wire [`SAMPLE_STREAM_DATA_W-1:0] m_data,
    output wire [`SAMPLE_STREAM_FLAGS_W-1:0] m_flags,

    output wire        full,
    output wire        almost_full,
    output wire [31:0] level,
    output wire        full_stall_pulse
);
    localparam integer PACK_W = `SAMPLE_STREAM_DATA_W + `SAMPLE_STREAM_FLAGS_W;
    wire [PACK_W-1:0] s_pack = {s_flags, s_data};
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

    assign {m_flags, m_data} = m_pack;
endmodule
