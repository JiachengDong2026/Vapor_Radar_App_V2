`timescale 1ns/1ps
// Independent branch queues. Physical capture never waits for either consumer.
// pack = {sync_valid,phase_valid,cycle_timestamp,capture_timestamp,phase,cycle,flags,data}
module adc_stream_fanout #(
    parameter integer DEPTH = 256,
    parameter integer WIDTH = 234
)(
    input wire clk, input wire rst_n, input wire raw_enable,
    input wire clear_raw,input wire clear_dila,
    input wire s_valid, output wire s_ready, input wire [WIDTH-1:0] s_data,
    output wire raw_valid, input wire raw_ready, output wire [WIDTH-1:0] raw_data,
    output wire dila_valid, input wire dila_ready, output wire [WIDTH-1:0] dila_data,
    output reg [31:0] raw_drop_count, output reg [31:0] dila_drop_count,
    output wire [31:0] raw_fifo_level,output wire [31:0] dila_fifo_level,
    output wire [1:0] drop_increment,output wire dila_drop_pulse
);
    wire rr, dr;
    wire [31:0] unused_rl, unused_dl;
    assign raw_fifo_level=unused_rl;assign dila_fifo_level=unused_dl;
    assign s_ready = 1'b1;
    assign dila_drop_pulse=s_valid && !dr;
    assign drop_increment={1'b0,(s_valid && raw_enable && !rr)}+{1'b0,dila_drop_pulse};
    sync_fifo #(.WIDTH(WIDTH),.DEPTH(DEPTH)) u_raw (
        .clk(clk),.rst_n(rst_n && !clear_raw),.s_valid(s_valid && raw_enable),.s_ready(rr),.s_data(s_data),
        .m_valid(raw_valid),.m_ready(raw_ready),.m_data(raw_data),.level(unused_rl),
        .full(),.empty(),.almost_full(),.full_stall_pulse()
    );
    sync_fifo #(.WIDTH(WIDTH),.DEPTH(DEPTH)) u_dila (
        .clk(clk),.rst_n(rst_n && !clear_dila),.s_valid(s_valid),.s_ready(dr),.s_data(s_data),
        .m_valid(dila_valid),.m_ready(dila_ready),.m_data(dila_data),.level(unused_dl),
        .full(),.empty(),.almost_full(),.full_stall_pulse()
    );
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin raw_drop_count<=0; dila_drop_count<=0; end
        else begin
            if(s_valid && raw_enable && !rr) raw_drop_count<=raw_drop_count+1'b1;
            if(s_valid && !dr) dila_drop_count<=dila_drop_count+1'b1;
        end
    end
endmodule


