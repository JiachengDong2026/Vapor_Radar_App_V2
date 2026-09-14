module clk_rst_mgr #(parameter INIT_CYCLES=4)(input clk_in,input rst_in_n,output sys_clk,output sys_rst_n,output init_done);
assign sys_clk=clk_in;
reg [31:0] cnt; reg rst_sync1,rst_sync2;
always @(posedge clk_in or negedge rst_in_n) begin
 if(!rst_in_n) begin rst_sync1<=0; rst_sync2<=0; cnt<=0; end
 else begin rst_sync1<=1; rst_sync2<=rst_sync1; if(cnt<INIT_CYCLES) cnt<=cnt+1'b1; end
end
assign sys_rst_n=rst_sync2;
assign init_done=sys_rst_n && (cnt>=INIT_CYCLES);
endmodule
