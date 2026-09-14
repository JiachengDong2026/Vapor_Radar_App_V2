`timescale 1ns/1ps
module tb_predev_common; reg clk=0,rst_n=0; reg [63:0] t0; always #5 clk=~clk;
wire [63:0] timestamp; wire sys_clk,sys_rst_n,init_done; clk_rst_mgr u_mgr(clk,rst_n,sys_clk,sys_rst_n,init_done); system_timebase u_tb(clk,sys_rst_n,timestamp);
reg [15:0] cfg_addr; reg cfg_wr_en,cfg_rd_en; reg [31:0] cfg_wr_data; wire [31:0] cfg_rd_data,reg0,reg1; wire cfg_ack,cfg_error; cfg_bus_if u_cfg(clk,sys_rst_n,cfg_addr,cfg_wr_en,cfg_wr_data,cfg_rd_en,cfg_rd_data,cfg_ack,cfg_error,reg0,reg1);
wire cycle_start,sample_enable; wire [31:0] cycle_id,phase; wms_reference_stub #(.SCAN_PERIOD(8)) u_wms(clk,sys_rst_n,cycle_start,sample_enable,cycle_id,phase);
initial begin #30 rst_n=1; wait(init_done); t0=timestamp; repeat(1000) @(posedge clk); if(timestamp-t0!==1000) $fatal("timebase delta %0d",timestamp-t0); cfg_addr=0;cfg_wr_data=32'h1234;cfg_wr_en=1;cfg_rd_en=0; @(posedge clk); cfg_wr_en=0; @(posedge clk); cfg_addr=0;cfg_rd_en=1; @(posedge clk); if(cfg_rd_data!==32'h1234) $fatal("cfg"); cfg_rd_en=0; cfg_addr=16'h99;cfg_rd_en=1; @(posedge clk); if(!cfg_error) $fatal("error"); $display("PREDEV_COMMON_TEST_PASS"); $finish; end
endmodule
