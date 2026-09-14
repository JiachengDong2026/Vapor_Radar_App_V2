`timescale 1ns/1ps
module clock_reset_gen #(parameter integer CLK_PERIOD_NS=10, parameter integer RESET_DURATION_NS=37)(output reg clk,output reg rst_n); initial begin clk=0; forever #(CLK_PERIOD_NS/2) clk=~clk; end initial begin rst_n=0; #(RESET_DURATION_NS) rst_n=1; end endmodule
