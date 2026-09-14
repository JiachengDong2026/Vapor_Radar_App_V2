`timescale 1ns/1ps
`include "stream_defs.vh"

module sample_stream_sink #(
    parameter integer STALL_EVERY = 0,
    parameter integer STALL_CYCLES = 1
)(
    input  wire clk,
    input  wire rst_n,
    input  wire valid,
    output wire ready,
    input  wire [`SAMPLE_STREAM_DATA_W-1:0] data,
    input  wire [`SAMPLE_STREAM_FLAGS_W-1:0] flags,
    output reg  [31:0] sample_count
);
    reg ready_r;
    integer accepted_since_stall;
    integer stall_left;

    reg hold_active;
    reg [`SAMPLE_STREAM_DATA_W-1:0] hold_data;
    reg [`SAMPLE_STREAM_FLAGS_W-1:0] hold_flags;

    assign ready = ready_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ready_r <= 1'b1;
            accepted_since_stall <= 0;
            stall_left <= 0;
            hold_active <= 1'b0;
            hold_data <= 0;
            hold_flags <= 0;
            sample_count <= 0;
        end else begin
            // Backpressure generator.
            if (stall_left > 0) begin
                ready_r <= 1'b0;
                stall_left <= stall_left - 1;
            end else begin
                ready_r <= 1'b1;
                if (valid && ready_r && STALL_EVERY > 0) begin
                    if (accepted_since_stall == STALL_EVERY-1) begin
                        accepted_since_stall <= 0;
                        stall_left <= STALL_CYCLES;
                    end else begin
                        accepted_since_stall <= accepted_since_stall + 1;
                    end
                end
            end

            // Producer must hold valid/data/flags until a stalled beat is accepted.
            if (hold_active) begin
                if (!valid)
                    $fatal(1, "SAMPLE_VALID_DROPPED_DURING_STALL");
                if (data !== hold_data || flags !== hold_flags)
                    $fatal(1, "SAMPLE_CHANGED_DURING_STALL");
            end

            if (valid && !ready) begin
                if (!hold_active) begin
                    hold_data  <= data;
                    hold_flags <= flags;
                end
                hold_active <= 1'b1;
            end else if (valid && ready) begin
                hold_active <= 1'b0;
            end else if (!valid) begin
                hold_active <= 1'b0;
            end

            if (valid && ready) begin
                sample_count <= sample_count + 1'b1;
                $display("SAMPLE beat=%0d data=%h flags=%h", sample_count, data, flags);
            end
        end
    end
endmodule
