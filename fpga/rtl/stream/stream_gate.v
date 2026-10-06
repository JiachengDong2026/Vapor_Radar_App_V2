`default_nettype none
// Admission is sampled on first valid, before any possible downstream stall.
// Once selected, enable cannot change the fate of the current message.
module stream_gate(
    input wire sys_clk, rst_sys_n, enable,
    input wire s_valid, output wire s_ready,
    input wire [31:0] s_data, input wire [3:0] s_keep,
    input wire s_sof, s_last,
    input wire [15:0] s_source_id, s_msg_id,
    input wire [63:0] s_timestamp,
    input wire [31:0] s_cycle_id, s_flags,
    output wire m_valid, input wire m_ready,
    output wire [31:0] m_data, output wire [3:0] m_keep,
    output wire m_sof, m_last,
    output wire [15:0] m_source_id, m_msg_id,
    output wire [63:0] m_timestamp,
    output wire [31:0] m_cycle_id, m_flags,
    output reg drop_pulse, output reg [31:0] drop_count
);
    reg active, admitted;
    assign s_ready = active && (!admitted || m_ready);
    assign m_valid = active && admitted && s_valid;
    assign m_data = s_data;
    assign m_keep = s_keep;
    assign m_sof = s_sof;
    assign m_last = s_last;
    assign m_source_id = s_source_id;
    assign m_msg_id = s_msg_id;
    assign m_timestamp = s_timestamp;
    assign m_cycle_id = s_cycle_id;
    assign m_flags = s_flags;
    always @(posedge sys_clk or negedge rst_sys_n) begin
        if (!rst_sys_n) begin
            active <= 0;
            admitted <= 0;
            drop_pulse <= 0;
            drop_count <= 0;
        end else begin
            drop_pulse <= 0;
            if (!active && s_valid) begin
                active <= 1;
                admitted <= enable;
            end
            if (s_valid && s_ready && s_last) begin
                active <= 0;
                if (!admitted) begin
                    drop_pulse <= 1;
                    drop_count <= drop_count + 1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire
