`timescale 1ns/1ps
module tb_data_packetizer;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,v=0,sof=0,last=0,rdy=0,seqv=0;
    reg [31:0] data=0,seq=0;
    reg [7:0] kind='h10;
    reg [3:0] keep=0;
    wire ready,mv,ml;
    wire [31:0] md,ls,frames,errors;
    reg [31:0] gold[0:2205];
    reg stalled=0;reg [32:0] held;
    integer frame=0,got=0,tick=0,i,j,n,off=0,wordno=0;
    integer lengths[0:7];
    data_packetizer dut(.sys_clk(clk),.rst_sys_n(rst),.s_valid(v),.s_ready(ready),.s_data(data),
       .s_keep(keep),.s_sof(sof),.s_last(last),.s_source_id(16'h40),.s_msg_id(16'h1100),
       .s_timestamp(64'h123456789abcdef0),.s_cycle_id(32'h98765432),.s_flags(32'd7),
       .s_frame_type(kind),.s_sequence(seq),.s_sequence_valid(seqv),.m_valid(mv),.m_ready(rdy),
       .m_data(md),.m_last(ml),.last_sequence(ls),.frame_count(frames),.format_error_count(errors));
    always @(negedge clk)begin tick=tick+1;rdy=(tick%7!=0 && tick%11<7);end
    always @(posedge clk)if(rst)begin
       if(stalled && (!mv || {ml,md}!==held))$fatal(1,"unstable TX under stall");
       stalled=mv && !rdy;held={ml,md};
       if(mv && rdy)begin
          if(md!==gold[got])$fatal(1,"golden mismatch word %0d expected %h got %h",got,gold[got],md);
          if(ml!== (wordno==((lengths[frame]+47)/4)-1))$fatal(1,"LAST position");
          got=got+1;wordno=wordno+1;
          if(ml)begin frame=frame+1;wordno=0;end
       end
    end
    task beat;input [31:0] x;input [3:0] k;input f,l;begin
      @(negedge clk);v=1;data=x;keep=k;sof=f;last=l;
      @(posedge clk);while(!ready)@(posedge clk);
      @(negedge clk);v=0;
    end endtask
    initial begin
      lengths[0]=0;lengths[1]=1;lengths[2]=2;lengths[3]=3;lengths[4]=4;lengths[5]=5;lengths[6]=255;lengths[7]=8192;
      $readmemh("packetizer_expected.hex",gold);
      repeat(4)@(negedge clk);rst=1;
      // Partial capture reset cannot leak a frame.
      beat('hbad,15,1,0);@(negedge clk);rst=0;repeat(3)@(negedge clk);rst=1;
      // Invalid KEEP and oversize fragment must drain without TX.
      beat('h1234,5,1,1);
      for(i=0;i<2049;i=i+1)beat(i,15,i==0,i==2048);
      if(errors!=2 || mv)$fatal(1,"format rejection");
      for(i=0;i<8;i=i+1)begin
        n=lengths[i];seqv=i==3;seq=32'haabbccdd;kind=i==3?2:'h10;
        if(n==0)beat(0,0,1,1);
        else for(off=0;off<n;off=off+4)begin
          data=0;keep=0;
          for(j=0;j<4;j=j+1)if(off+j<n)begin data[j*8 +: 8]=(off+j)*73+i*17+9;keep[j]=1;end
          beat(data,keep,off==0,off+4>=n);
        end
        wait(frame==i+1);@(negedge clk);
      end
      if(frames!=8 || ls!=7 || errors!=2)$fatal(1,"statistics");
      $display("tb_data_packetizer_PASS frames=%0d words=%0d",frame,got);$finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
