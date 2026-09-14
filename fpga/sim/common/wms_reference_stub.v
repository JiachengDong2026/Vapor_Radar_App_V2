module wms_reference_stub(
 input wire clk,input wire rst_n,output wire scan_start,output wire phase_valid,
 output wire [31:0] cycle_id,output wire [31:0] phase);
reg scan_start_reg;
reg [31:0] cycle_id_reg,phase_reg;
assign scan_start=scan_start_reg;
assign phase_valid=rst_n;
assign cycle_id=cycle_id_reg;
assign phase=phase_reg;
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin scan_start_reg<=0; cycle_id_reg<=0; phase_reg<=0; end
 else begin
  scan_start_reg<=0; phase_reg<=phase_reg+1'b1;
  if(phase_reg==32'hffff_ffff) begin scan_start_reg<=1; cycle_id_reg<=cycle_id_reg+1'b1; end
 end
end
endmodule
