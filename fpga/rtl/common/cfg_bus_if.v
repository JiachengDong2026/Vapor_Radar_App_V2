module cfg_bus_if #(parameter ADDR0=16'h0000, parameter ADDR1=16'h0004)(input clk,input rst_n,input [15:0] cfg_addr,input cfg_wr_en,input [31:0] cfg_wr_data,input cfg_rd_en,output reg [31:0] cfg_rd_data,output reg cfg_ack,output reg cfg_error,output reg [31:0] reg0,output reg [31:0] reg1);
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin cfg_ack<=0; cfg_error<=0; cfg_rd_data<=0; reg0<=0; reg1<=0; end
 else begin cfg_ack<=cfg_wr_en|cfg_rd_en; cfg_error<=0; cfg_rd_data<=0;
  if(cfg_wr_en) case(cfg_addr) ADDR0:reg0<=cfg_wr_data; ADDR1:reg1<=cfg_wr_data; default:cfg_error<=1; endcase
  if(cfg_rd_en) case(cfg_addr) ADDR0:cfg_rd_data<=reg0; ADDR1:cfg_rd_data<=reg1; default:begin cfg_rd_data<=32'hDEAD_BEEF; cfg_error<=1; end endcase
 end
end
endmodule
