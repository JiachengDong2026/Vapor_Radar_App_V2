`include "stream_defs.vh"
module bulk_stream_sink #(parameter DATA_WIDTH=`BULK_STREAM_DATA_W)(
 input wire clk,input wire rst_n,input wire valid,output wire ready,input wire [DATA_WIDTH-1:0] data,
 input wire frame_start,input wire frame_end,input wire [`STREAM_SOURCE_W-1:0] source_id,
 input wire [`STREAM_MSG_ID_W-1:0] msg_id,input wire [`STREAM_TIMESTAMP_W-1:0] timestamp,
 input wire [`STREAM_CYCLE_ID_W-1:0] cycle_id,input wire [31:0] fragment_index,
 input wire [31:0] fragment_count,output reg [31:0] frame_count,output reg [31:0] sample_count);
reg in_frame;
reg [`STREAM_SOURCE_W-1:0] frame_source_id;
reg [`STREAM_MSG_ID_W-1:0] frame_msg_id;
reg [`STREAM_TIMESTAMP_W-1:0] frame_timestamp;
reg [`STREAM_CYCLE_ID_W-1:0] frame_cycle_id;
reg [31:0] frame_fragment_index,frame_fragment_count,expected_fragment_index;
assign ready=1'b1;
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
  in_frame<=0; frame_count<=0; sample_count<=0; frame_source_id<=0; frame_msg_id<=0;
  frame_timestamp<=0; frame_cycle_id<=0; frame_fragment_index<=0;
  frame_fragment_count<=0; expected_fragment_index<=0;
 end else if(valid&&ready) begin
  if(frame_start) begin
   if(in_frame) $error("BULK_NESTED_FRAME");
   if(fragment_count==0) $error("BULK_FRAGMENT_COUNT_ZERO");
   if(fragment_index>=fragment_count) $error("BULK_FRAGMENT_INDEX_RANGE index=%0d count=%0d",fragment_index,fragment_count);
   if(fragment_index!=expected_fragment_index) $error("BULK_FRAGMENT_DISCONTINUITY expected=%0d actual=%0d",expected_fragment_index,fragment_index);
   in_frame<=1; frame_count<=frame_count+1'b1; frame_source_id<=source_id; frame_msg_id<=msg_id;
   frame_timestamp<=timestamp; frame_cycle_id<=cycle_id; frame_fragment_index<=fragment_index;
   frame_fragment_count<=fragment_count;
  end else begin
   if(!in_frame) $error("BULK_DATA_OUTSIDE_FRAME");
   if(source_id!=frame_source_id||msg_id!=frame_msg_id||timestamp!=frame_timestamp||
      cycle_id!=frame_cycle_id||fragment_index!=frame_fragment_index||fragment_count!=frame_fragment_count)
    $error("BULK_METADATA_CHANGED_WITHIN_FRAME");
  end
  sample_count<=sample_count+1'b1;
  if(frame_end) begin
   if(!in_frame&&!frame_start) $error("BULK_FRAME_END_WITHOUT_START");
   in_frame<=0;
   if((fragment_index+1'b1)==fragment_count) expected_fragment_index<=0;
   else expected_fragment_index<=fragment_index+1'b1;
  end
  $display("BULK: source=0x%04h msg=0x%04h cycle=%0d fragment=%0d/%0d timestamp=%0d data=%h",source_id,msg_id,cycle_id,fragment_index,fragment_count,timestamp,data);
 end
end
endmodule
