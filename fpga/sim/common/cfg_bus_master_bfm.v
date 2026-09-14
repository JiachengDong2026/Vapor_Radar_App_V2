task automatic cfg_write(input [15:0] a,input [31:0] d); begin @(posedge clk); cfg_addr<=a; cfg_wr_data<=d; cfg_wr_en<=1; cfg_rd_en<=0; @(posedge clk); cfg_wr_en<=0; end endtask
task automatic cfg_read(input [15:0] a,output [31:0] d); begin @(posedge clk); cfg_addr<=a; cfg_rd_en<=1; cfg_wr_en<=0; @(posedge clk); d=cfg_rd_data; cfg_rd_en<=0; end endtask
