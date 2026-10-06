`default_nettype none
module sensor_hub #(parameter integer N=7)(
    input wire sys_clk,rst_sys_n,
    input wire [N-1:0] s_valid,
    output wire [N-1:0] s_ready,
    input wire [N*32-1:0] s_data,
    input wire [N*4-1:0] s_keep,
    input wire [N*1-1:0] s_sof,
    input wire [N*1-1:0] s_last,
    input wire [N*16-1:0] s_source_id,
    input wire [N*16-1:0] s_msg_id,
    input wire [N*64-1:0] s_timestamp,
    input wire [N*32-1:0] s_cycle_id,
    input wire [N*32-1:0] s_flags,
    output wire [32-1:0] m_data,
    output wire [4-1:0] m_keep,
    output wire m_sof,
    output wire m_last,
    output wire [16-1:0] m_source_id,
    output wire [16-1:0] m_msg_id,
    output wire [64-1:0] m_timestamp,
    output wire [32-1:0] m_cycle_id,
    output wire [32-1:0] m_flags,
    output wire m_valid,
    input wire m_ready,
    output wire [63:0] grant_count,
    output wire [N-1:0] pending_mask
);
    stream_arbiter #(.N(N)) u_arbiter(
        .sys_clk(sys_clk),.rst_sys_n(rst_sys_n),.arb_mode(1'b0),.max_high_burst(32'd4),
        .s_priority({N{2'd0}}),.s_valid(s_valid),.s_ready(s_ready),
        .s_data(s_data),.m_data(m_data),
        .s_keep(s_keep),.m_keep(m_keep),
        .s_sof(s_sof),.m_sof(m_sof),
        .s_last(s_last),.m_last(m_last),
        .s_source_id(s_source_id),.m_source_id(m_source_id),
        .s_msg_id(s_msg_id),.m_msg_id(m_msg_id),
        .s_timestamp(s_timestamp),.m_timestamp(m_timestamp),
        .s_cycle_id(s_cycle_id),.m_cycle_id(m_cycle_id),
        .s_flags(s_flags),.m_flags(m_flags),
        .s_frame_type({N{8'h10}}),.s_sequence({N{32'd0}}),.s_sequence_valid({N{1'b0}}),
        .m_frame_type(),.m_sequence(),.m_sequence_valid(),
        .m_valid(m_valid),.m_ready(m_ready),.grant_count(grant_count),.pending_mask(pending_mask)
    );
endmodule
`default_nettype wire
