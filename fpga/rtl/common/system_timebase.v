module system_timebase(input clk,input rst_n,output reg [63:0] timestamp);
always @(posedge clk or negedge rst_n) if(!rst_n) timestamp<=64'd0; else timestamp<=timestamp+1'b1;
endmodule
