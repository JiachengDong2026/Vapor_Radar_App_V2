`timescale 1ns/1ps
`include "stream_defs.vh"
module tb_predev_common;
reg clk,rst_n;
wire sys_clk,sys_rst_n,init_done;
wire [63:0] timestamp;
reg [63:0] timestamp_start;
wire [15:0] cfg_addr; wire cfg_wr_en,cfg_rd_en,cfg_ack,cfg_error;
wire [31:0] cfg_wr_data,cfg_rd_data,cfg_reg0,cfg_reg1;
reg [31:0] cfg_readback;
reg sample_valid; reg [31:0] sample_data; reg [63:0] sample_timestamp; reg [7:0] sample_channel_id;
wire sample_ready; wire [31:0] sample_count;
reg msg_valid; reg [31:0] msg_data; reg [15:0] msg_source_id,msg_id;
reg [63:0] msg_timestamp; reg [31:0] msg_flags; wire msg_ready; wire [31:0] msg_count;
reg bulk_valid,bulk_frame_start,bulk_frame_end; reg [63:0] bulk_data,bulk_timestamp;
reg [15:0] bulk_source_id,bulk_msg_id; reg [31:0] bulk_cycle_id,bulk_fragment_index,bulk_fragment_count;
wire bulk_ready; wire [31:0] bulk_frame_count,bulk_sample_count;
wire scan_start,phase_valid; wire [31:0] wms_cycle_id,phase;
integer i;
always #5 clk=~clk;

clk_rst_mgr u_clk_rst_mgr(.clk_in(clk),.rst_in_n(rst_n),.sys_clk(sys_clk),.sys_rst_n(sys_rst_n),.init_done(init_done));
system_timebase u_timebase(.clk(sys_clk),.rst_n(sys_rst_n),.timestamp(timestamp));
cfg_bus_master_bfm #(.TIMEOUT_CYCLES(20)) u_cfg_master(
 .clk(sys_clk),.rst_n(sys_rst_n),.cfg_addr(cfg_addr),.cfg_wr_en(cfg_wr_en),.cfg_wr_data(cfg_wr_data),
 .cfg_rd_en(cfg_rd_en),.cfg_rd_data(cfg_rd_data),.cfg_ack(cfg_ack),.cfg_error(cfg_error));
cfg_bus_if u_cfg_slave(.clk(sys_clk),.rst_n(sys_rst_n),.cfg_addr(cfg_addr),.cfg_wr_en(cfg_wr_en),
 .cfg_wr_data(cfg_wr_data),.cfg_rd_en(cfg_rd_en),.cfg_rd_data(cfg_rd_data),.cfg_ack(cfg_ack),
 .cfg_error(cfg_error),.reg0(cfg_reg0),.reg1(cfg_reg1));
sample_stream_sink u_sample_sink(.clk(sys_clk),.rst_n(sys_rst_n),.valid(sample_valid),.ready(sample_ready),
 .data(sample_data),.timestamp(sample_timestamp),.channel_id(sample_channel_id),.sample_count(sample_count));
msg_stream_sink u_msg_sink(.clk(sys_clk),.rst_n(sys_rst_n),.valid(msg_valid),.ready(msg_ready),
 .data(msg_data),.source_id(msg_source_id),.msg_id(msg_id),.timestamp(msg_timestamp),.flags(msg_flags),.msg_count(msg_count));
bulk_stream_sink u_bulk_sink(.clk(sys_clk),.rst_n(sys_rst_n),.valid(bulk_valid),.ready(bulk_ready),
 .data(bulk_data),.frame_start(bulk_frame_start),.frame_end(bulk_frame_end),.source_id(bulk_source_id),
 .msg_id(bulk_msg_id),.timestamp(bulk_timestamp),.cycle_id(bulk_cycle_id),
 .fragment_index(bulk_fragment_index),.fragment_count(bulk_fragment_count),
 .frame_count(bulk_frame_count),.sample_count(bulk_sample_count));
wms_reference_stub u_wms_reference(.clk(sys_clk),.rst_n(sys_rst_n),.scan_start(scan_start),
 .phase_valid(phase_valid),.cycle_id(wms_cycle_id),.phase(phase));

task send_sample; input [31:0] value; input [63:0] sample_time; begin
 @(negedge sys_clk); sample_valid=1; sample_data=value; sample_timestamp=sample_time;
 @(negedge sys_clk); sample_valid=0;
end endtask
task send_message; input [15:0] source; input [15:0] message; input [63:0] message_time; input [31:0] value; begin
 @(negedge sys_clk); msg_valid=1; msg_source_id=source; msg_id=message;
 msg_timestamp=message_time; msg_data=value; msg_flags=0;
 @(negedge sys_clk); msg_valid=0;
end endtask
task send_bulk_fragment; input [31:0] index; begin
 @(negedge sys_clk); bulk_valid=1; bulk_frame_start=1; bulk_frame_end=1;
 bulk_fragment_index=index; bulk_data={32'hd11a_0000,index};
 @(negedge sys_clk); bulk_valid=0; bulk_frame_start=0; bulk_frame_end=0;
end endtask

initial begin
 clk=0; rst_n=0; sample_valid=0; sample_data=0; sample_timestamp=0; sample_channel_id=0;
 msg_valid=0; msg_data=0; msg_source_id=0; msg_id=0; msg_timestamp=0; msg_flags=0;
 bulk_valid=0; bulk_data=0; bulk_frame_start=0; bulk_frame_end=0;
 bulk_source_id=16'h0030; bulk_msg_id=16'h2000; bulk_timestamp=5000;
 bulk_cycle_id=100; bulk_fragment_index=0; bulk_fragment_count=4;
 repeat(3) @(posedge clk); rst_n=1; wait(init_done); @(negedge sys_clk);

 timestamp_start=timestamp; repeat(1000) @(posedge sys_clk); @(negedge sys_clk);
 if(timestamp-timestamp_start!==64'd1000) $fatal(1,"TIMEBASE_TEST_FAIL delta=%0d",timestamp-timestamp_start);

 u_cfg_master.cfg_write(16'h0000,32'h1234_abcd);
 u_cfg_master.cfg_read(16'h0000,cfg_readback);
 if(cfg_readback!==32'h1234_abcd) $fatal(1,"CFG_READBACK_TEST_FAIL actual=0x%08h",cfg_readback);
 u_cfg_master.cfg_read(16'h0099,cfg_readback);
 if(!cfg_error||cfg_readback!==32'hdead_beef)
  $fatal(1,"CFG_INVALID_ADDRESS_TEST_FAIL error=%b data=0x%08h",cfg_error,cfg_readback);

 for(i=0;i<100;i=i+1) send_sample(i,64'd2000+i);
 @(posedge sys_clk);
 if(sample_count!==100||u_sample_sink.last_timestamp!==2099)
  $fatal(1,"SAMPLE_STREAM_TEST_FAIL count=%0d timestamp=%0d",sample_count,u_sample_sink.last_timestamp);

 send_message(16'h0020,16'h1100,3000,32'h484d_5000);
 if(u_msg_sink.last_source_id!==16'h0020||u_msg_sink.last_msg_id!==16'h1100)
  $fatal(1,"HMP_MESSAGE_ID_TEST_FAIL source=0x%04h msg=0x%04h",u_msg_sink.last_source_id,u_msg_sink.last_msg_id);
 send_message(16'h0021,16'h1200,3001,32'he051_1000);
 @(posedge sys_clk);
 if(msg_count!==2||u_msg_sink.last_timestamp!==3001||u_msg_sink.last_source_id!==16'h0021||u_msg_sink.last_msg_id!==16'h1200)
  $fatal(1,"EPSILON_MESSAGE_TEST_FAIL count=%0d source=0x%04h msg=0x%04h",msg_count,u_msg_sink.last_source_id,u_msg_sink.last_msg_id);

 for(i=0;i<4;i=i+1) send_bulk_fragment(i);
 @(posedge sys_clk);
 if(bulk_frame_count!==4||bulk_sample_count!==4||u_bulk_sink.expected_fragment_index!==0||u_bulk_sink.in_frame!==0)
  $fatal(1,"BULK_STREAM_TEST_FAIL frames=%0d samples=%0d next=%0d",bulk_frame_count,bulk_sample_count,u_bulk_sink.expected_fragment_index);
 if(!phase_valid) $fatal(1,"WMS_REFERENCE_TEST_FAIL phase_valid=0");
 $display("PREDEV_INTERFACE_TEST_PASS"); $finish;
end
endmodule
