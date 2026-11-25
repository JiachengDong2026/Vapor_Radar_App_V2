`include "project_defs.vh"
// Observation only: rising edges coincide with the sampled source events.
// Retriggers while a pulse is high do not extend it or queue another pulse.
module measurement_start_outputs #(
    parameter integer SYS_CLK_HZ = 100000000,
    parameter integer PULSE_US = `MEASUREMENT_START_PULSE_US
)(
    input wire clk,
    input wire rst_n,
    input wire [2:0] start_event,
    output reg [2:0] start_pulse
);
    localparam integer PULSE_TICKS = (SYS_CLK_HZ * 64'd1 * PULSE_US + 999999) / 1000000;
    function integer clog2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            for (clog2 = 0; v > 0; clog2 = clog2 + 1)
                v = v >> 1;
        end
    endfunction
    localparam integer COUNT_WIDTH = PULSE_TICKS < 2 ? 1 : clog2(PULSE_TICKS + 1);
    genvar channel;
    generate for (channel = 0; channel < 3; channel = channel + 1) begin : outputs
        reg [COUNT_WIDTH-1:0] remaining;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                remaining <= 0;
                start_pulse[channel] <= 0;
            end else if (remaining != 0) begin
                remaining <= remaining - 1'b1;
                if (remaining == 1)
                    start_pulse[channel] <= 0;
            end else if (start_event[channel]) begin
                remaining <= PULSE_TICKS;
                start_pulse[channel] <= 1;
            end
        end
    end endgenerate
endmodule
