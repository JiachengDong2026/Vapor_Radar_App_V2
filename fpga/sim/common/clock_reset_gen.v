`timescale 1ns/1ps
module clock_reset_gen #(
    parameter integer CLK_PERIOD_NS = 10,
    parameter integer RESET_CYCLES = 8
)(
    output reg clk,
    output reg rst_n
);
    integer i;
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end
    initial begin
        rst_n = 1'b0;
        for (i = 0; i < RESET_CYCLES; i = i + 1)
            @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
    end
endmodule
