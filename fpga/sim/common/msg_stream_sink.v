`include "stream_defs.vh"
module msg_stream_sink #(parameter DATA_WIDTH=`MSG_STREAM_DATA_W)(
 input wire clk,input wire rst_n,input wire valid,output wire ready,
 input wire [DATA_WIDTH-1:0] data,input wire [`STREAM_SOURCE_W-1:0] source_id,
 input wire [`STREAM_MSG_ID_W-1:0] msg_id,input wire [`STREAM_TIMESTAMP_W-1:0] timestamp,
 input wire [`STREAM_FLAGS_W-1:0] flags,output reg [31:0] msg_count);
reg [`STREAM_TIMESTAMP_W-1:0] last_timestamp;
reg [`STREAM_SOURCE_W-1:0] last_source_id;
reg [`STREAM_MSG_ID_W-1:0] last_msg_id;
assign ready=1'b1;
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin msg_count<=0; last_timestamp<=0; last_source_id<=0; last_msg_id<=0; end
 else if(valid&&ready) begin
  if(msg_count!=0&&timestamp<last_timestamp)
   $error("MSG_TIMESTAMP_DECREASE previous=%0d current=%0d",last_timestamp,timestamp);
  msg_count<=msg_count+1'b1; last_timestamp<=timestamp;
  last_source_id<=source_id; last_msg_id<=msg_id;
  $display("MSG: source=0x%04h msg=0x%04h timestamp=%0d flags=0x%08h data=%h",source_id,msg_id,timestamp,flags,data);
 end
end
endmodule
