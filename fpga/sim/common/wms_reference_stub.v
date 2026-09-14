module wms_reference_stub #(parameter integer SCAN_PERIOD=16)(input clk,input rst_n,output reg cycle_start,output reg sample_enable,output reg [31:0] cycle_id,output reg [31:0] phase); reg [31:0] cnt;
always @(posedge clk or negedge rst_n) if(!rst_n) begin cnt<=0;cycle_id<=0;phase<=0;cycle_start<=0;sample_enable<=0; end else begin cycle_start<=0;sample_enable<=1;phase<=phase+32'h01000000; if(cnt==SCAN_PERIOD-1) begin cnt<=0;cycle_start<=1;cycle_id<=cycle_id+1'b1;phase<=0; end else cnt<=cnt+1'b1; end
endmodule
