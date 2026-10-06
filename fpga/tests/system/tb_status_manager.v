`timescale 1ns/1ps
module tb_status_manager;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,sp=0,mdone=0,release_queues=0;
    reg [63:0] tick=0,st=0,tag=0;reg [31:0] seq=0;reg gv=0;
    reg [95:0] statuses=0,errors=0;
    wire [31:0] summary,irq,drops;
    wire [2:0] v,sof,last;reg [2:0] r=0;
    wire [95:0] data,cycle,flags,level;wire [11:0] keep;wire [47:0] source,msg;wire [191:0] ts;wire [23:0] kind;
    integer word_index[0:2];integer frames[0:2];integer i,j,motor_frames=0;
    reg [319:0] held[0:2];reg [2:0] stalled=0;
    reg [31:0] time_seq;
    status_manager #(.N(3),.STATUS_INTERVAL_TICKS(32),.QUEUE_DEPTH(4),.PAGE_MAP(24'h401000)) dut(
      .sys_clk(clk),.rst_sys_n(rst),.timestamp_now(tick),.time_sync_valid(1'b1),.module_status(statuses),.module_errors(errors),
      .module_present(3'b111),.system_status(32'd7),.total_drop_count(32'd9),.reset_reason(32'd1),
      .sync_event_pulse(sp),.sync_seq(seq),.sync_event_tick(st),.sync_event_gnss_tag(tag),.sync_event_gnss_valid(gv),
      .motor_done(mdone),.motion_id(32'd3),.motor_position(-32'd7),.motor_remaining(32'd12),.motor_errors(32'd0),
      .error_summary(summary),.module_irq(irq),.event_drop_count(drops),.m_valid(v),.m_ready(r),.m_data(data),.m_keep(keep),
      .m_sof(sof),.m_last(last),.m_source_id(source),.m_msg_id(msg),.m_timestamp(ts),.m_cycle_id(cycle),.m_flags(flags),
      .m_frame_type(kind),.queue_level(level));
    always @(posedge clk)if(rst)tick<=tick+1;
    always @(negedge clk)begin r[0]=tick%5!=0;r[1]=release_queues && tick%7<5;r[2]=release_queues && tick%9<6;end
    always @(posedge clk)if(rst)begin
      for(j=0;j<3;j=j+1)begin
        if(stalled[j] && (!v[j] || {last[j],sof[j],ts[j*64 +: 64],cycle[j*32 +: 32],flags[j*32 +: 32],source[j*16 +: 16],msg[j*16 +: 16],kind[j*8 +: 8],data[j*32 +: 32]}!==held[j]))$fatal(1,"status stall %0d",j);
        stalled[j]=v[j]&&!r[j];held[j]={last[j],sof[j],ts[j*64 +: 64],cycle[j*32 +: 32],flags[j*32 +: 32],source[j*16 +: 16],msg[j*16 +: 16],kind[j*8 +: 8],data[j*32 +: 32]};
        if(v[j] && r[j])begin
          if(sof[j]!=(word_index[j]==0) || last[j]!=(word_index[j]==7) || keep[j*4 +: 4]!=15)$fatal(1,"record boundaries");
          if(word_index[j]==0 && data[j*32 +: 32]!=1)$fatal(1,"schema");
          if(j==0)begin
            if(msg[15:0]!='h1402 || source[15:0]!=2 || !flags[8])$fatal(1,"error metadata");
            if(word_index[j]==3 && data[31:0]!=(frames[0]==1?4:2))$fatal(1,"error rising bits");
          end
          if(j==1)begin
            if(word_index[j]==1)begin time_seq=data[63:32];if(time_seq!=100+frames[1])$fatal(1,"time ordering");end
            if(word_index[j]==2 && data[63:32]!=time_seq*100)$fatal(1,"time tick");
            if(word_index[j]==4 && data[63:32]!=1000000+time_seq)$fatal(1,"UTC tag");
            if(word_index[j]==6 && data[63:32]!=(time_seq%2==0))$fatal(1,"UTC valid");
            if(ts[127:64]!=(100+frames[1])*100)$fatal(1,"event timestamp");
          end
          if(j==2 && msg[47:32]=='h1300)begin
            if(word_index[j]==2 && data[95:64]!==-32'd7)$fatal(1,"motor position");
            if(last[j])motor_frames=motor_frames+1;
          end
          if(last[j])begin word_index[j]=0;frames[j]=frames[j]+1;end else word_index[j]=word_index[j]+1;
        end
      end
    end
    initial begin
      for(i=0;i<3;i=i+1)begin word_index[i]=0;frames[i]=0;end
      repeat(4)@(negedge clk);rst=1;statuses={3{32'h13}};errors[31:0]=32'hdeadbeef;errors[63:32]=2;
      repeat(40)@(negedge clk);if(summary!=2 || frames[0]!=1)$fatal(1,"summary self feedback / duplicate error");
      errors[63:32]=6;repeat(30)@(negedge clk);errors[63:32]=0;repeat(8)@(negedge clk);errors[63:32]=2;
      for(i=0;i<6;i=i+1)begin @(negedge clk);sp=1;seq=100+i;st=(100+i)*100;tag=1000100+i;gv=i%2==0;@(negedge clk);sp=0;end
      repeat(100)@(negedge clk);release_queues=1;repeat(150)@(negedge clk);
      if(frames[0]!=3 || frames[1]!=4 || drops<2)$fatal(1,"queue counts error=%0d time=%0d drop=%0d",frames[0],frames[1],drops);
      mdone=1;@(negedge clk);mdone=0;wait(motor_frames==1);
      $display("tb_status_manager_PASS error_events=%0d time_events=%0d drops=%0d",frames[0],frames[1],drops);$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
