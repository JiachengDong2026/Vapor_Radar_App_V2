module cfg_bus_master_bfm #(parameter integer TIMEOUT_CYCLES=1000)(
 input wire clk,input wire rst_n,output reg [15:0] cfg_addr,output reg cfg_wr_en,
 output reg [31:0] cfg_wr_data,output reg cfg_rd_en,input wire [31:0] cfg_rd_data,
 input wire cfg_ack,input wire cfg_error);
integer wait_cycles;
initial begin cfg_addr=0; cfg_wr_en=0; cfg_wr_data=0; cfg_rd_en=0; end
task automatic wait_for_ack;
 begin : wait_block
  wait_cycles=0;
  while(!cfg_ack) begin
   @(posedge clk); wait_cycles=wait_cycles+1;
   if(wait_cycles>=TIMEOUT_CYCLES) begin
    $display("CFG_BUS_TIMEOUT addr=0x%04h",cfg_addr); $fatal(1); disable wait_block;
   end
  end
 end
endtask
task automatic cfg_write;
 input [15:0] addr; input [31:0] data;
 begin
  @(negedge clk); cfg_addr=addr; cfg_wr_data=data; cfg_wr_en=1; cfg_rd_en=0;
  wait_for_ack; @(negedge clk); cfg_wr_en=0;
 end
endtask
task automatic cfg_read;
 input [15:0] addr; output [31:0] data;
 begin
  @(negedge clk); cfg_addr=addr; cfg_wr_en=0; cfg_rd_en=1;
  wait_for_ack; data=cfg_rd_data; @(negedge clk); cfg_rd_en=0;
 end
endtask
endmodule
