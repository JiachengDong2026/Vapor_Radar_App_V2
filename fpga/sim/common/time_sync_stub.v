`timescale 1ns/1ps
module time_sync_stub #(
    parameter integer SYNC_PERIOD_CYCLES = 1000
)(
    input  wire        clk,
    input  wire        rst_n,
    output reg  [63:0] timestamp_now,
    output reg         time_sync_valid,
    output reg  [31:0] time_sync_seq,
    output reg         sync_event_pulse
);
    integer sync_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timestamp_now   <= 64'd0;
            time_sync_valid  <= 1'b0;
            time_sync_seq    <= 32'd0;
            sync_event_pulse <= 1'b0;
            sync_count       <= 0;
        end else begin
            timestamp_now   <= timestamp_now + 1'b1;
            time_sync_valid  <= 1'b1;
            sync_event_pulse <= 1'b0;
            if (sync_count == SYNC_PERIOD_CYCLES-1) begin
                sync_count       <= 0;
                time_sync_seq    <= time_sync_seq + 1'b1;
                sync_event_pulse <= 1'b1;
            end else begin
                sync_count <= sync_count + 1;
            end
        end
    end
endmodule
