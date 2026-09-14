`timescale 1ns/1ps
module wms_reference_stub #(
    parameter integer SCAN_PERIOD_CYCLES = 64,
    parameter [31:0] PHASE_INC = 32'h0400_0000
)(
    input  wire        clk,
    input  wire        rst_n,
    output reg         scan_start,
    output wire        phase_valid,
    output reg  [31:0] cycle_id,
    output reg  [31:0] sine_phase,
    output wire        wms_running
);
    integer scan_count;
    assign phase_valid = rst_n;
    assign wms_running = rst_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scan_start <= 1'b0;
            cycle_id   <= 32'd0;
            sine_phase <= 32'd0;
            scan_count <= 0;
        end else begin
            scan_start <= 1'b0;
            sine_phase <= sine_phase + PHASE_INC;
            if (scan_count == SCAN_PERIOD_CYCLES-1) begin
                scan_count <= 0;
                cycle_id   <= cycle_id + 1'b1;
                scan_start <= 1'b1;
            end else begin
                scan_count <= scan_count + 1;
            end
        end
    end
endmodule
