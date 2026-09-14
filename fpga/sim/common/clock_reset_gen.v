`timescale 1ns/1ps
module clock_reset_gen(output reg clk,output reg rst_n); initial begin clk=0; forever #5 clk=~clk; end initial begin rst_n=0; #37 rst_n=1; end endmodule
