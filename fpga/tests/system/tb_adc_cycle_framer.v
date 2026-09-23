`timescale 1ns/1ps
module tb_adc_cycle_framer;
    `include "raw_sizes.vh"
    reg clk=0;always #5 clk=~clk;
    reg rst=0,en=1,flush=0,v=0,pv=1,sv=1,rdy=0,hold_tx=0;
    reg [31:0] data=0,cid=0;reg [63:0] ts=0;reg [7:0] flags=0;
    wire ready,mv,sof,last;wire [31:0] md,mc,mf,drops,cdrops,frames,level;wire [63:0] mt;wire [3:0] keep;wire [15:0] source,msg;
    reg [161:0] gold[0:GOLD_WORDS-1];reg [161:0] held;reg stalled=0;
    integer got=0,tick=0,i;
    adc_cycle_framer #(.MAX_SAMPLES(10),.FRAGMENT_SAMPLES(4),.V1_MAX_SAMPLES(4),.FLUSH_IDLE_TICKS(8)) dut(
      .sys_clk(clk),.rst_sys_n(rst),.enable(en),.flush(flush),.sample_rate_hz(32'd1000),
      .s_valid(v),.s_ready(ready),.s_data(data),.s_flags(flags),.s_capture_cycle_id(cid),.s_cycle_timestamp(ts),
      .s_capture_phase_valid(pv),.s_capture_time_sync_valid(sv),.m_valid(mv),.m_ready(rdy),.m_data(md),.m_keep(keep),
      .m_sof(sof),.m_last(last),.m_source_id(source),.m_msg_id(msg),.m_timestamp(mt),.m_cycle_id(mc),.m_flags(mf),
      .drop_count(drops),.cycle_drop_count(cdrops),.frame_count(frames),.buffered_samples(level));
    task sample;input [31:0] cycle,value;input errorflag,syncflag;begin
      @(negedge clk);v=1;cid=cycle;data=value;ts=cycle*1000;flags=errorflag;sv=syncflag;
      @(posedge clk);if(!ready)$fatal(1,"physical sample backpressured");@(negedge clk);v=0;
    end endtask
    always @(negedge clk)begin tick=tick+1;rdy=!hold_tx && tick%7<5;end
    always @(posedge clk)if(rst)begin
      if(stalled && (!mv || {last,sof,mt,mc,mf,md}!==held))$fatal(1,"RAW stall stability");
      stalled=mv && !rdy;held={last,sof,mt,mc,mf,md};
      if(mv && rdy)begin
        if({last,sof,mt,mc,mf,md}!==gold[got])$fatal(1,"RAW word %0d cycle %0d word=%h flags=%h expected=%h",got,mc,md,mf,gold[got]);
        if(keep!=15 || source!='h20 || msg!='h1000)$fatal(1,"metadata");got=got+1;
      end
    end
    initial begin
      $readmemh("raw_expected.hex",gold);
      repeat(4)@(negedge clk);rst=1;
      pv=0;sample(99,999,0,1);pv=1;
      for(i=0;i<3;i=i+1)sample(100,1000+i,0,1);
      for(i=0;i<9;i=i+1)sample(101,2000+i,i==4,i!=5);
      wait(frames==1);
      for(i=0;i<2;i=i+1)sample(102,3000+i,0,1);
      flush=1;wait(frames==5);@(negedge clk);flush=0;
      for(i=0;i<12;i=i+1)sample(103,4000+i,0,1);
      flush=1;wait(frames==8);@(negedge clk);flush=0;
      hold_tx=1;sample(104,5000,0,1);sample(105,6000,0,1);
      for(i=0;i<4;i=i+1)sample(106,7000+i,0,1);
      repeat(10)@(negedge clk);hold_tx=0;wait(frames==10);
      for(i=0;i<2;i=i+1)sample(107,8000+i,0,1);
      flush=1;wait(frames==11);@(negedge clk);flush=0;
      en=0;for(i=0;i<3;i=i+1)sample(108,9000+i,0,1);
      en=1;for(i=3;i<5;i=i+1)sample(108,9000+i,0,1);
      sample(109,10000,0,1);flush=1;wait(frames==12);repeat(5)@(negedge clk);
      if(got!=GOLD_WORDS || drops!=8 || cdrops!=1 || level!=0)$fatal(1,"RAW counts drops=%0d cycles=%0d words=%0d level=%0d",drops,cdrops,got,level);
      $display("tb_adc_cycle_framer_PASS fragments=%0d samples_dropped=%0d",frames,drops);$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
