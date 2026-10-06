`timescale 1ns/1ps
module tb_vlp_cmd_rx;
    `include "cmd_rx_sizes.vh"
    reg clk=0;always #5 clk=~clk;
    reg rst=0,v=0,done=0;
    reg [7:0] b=0;
    reg [31:0] read_word=0;
    wire ready,cv;wire [31:0] status,seq,n,read_data,pe,ce,ls,used;
    wire [15:0] src,mid;
    reg [7:0] bytes[0:INPUT_BYTES-1];
    reg [31:0] expected[0:EXPECTED_WORDS-1];
    integer i,j,event_count=0,index=0,len,k;
    reg [31:0] mask;
    vlp_cmd_rx #(.RX_TIMEOUT_TICKS(100)) dut(.sys_clk(clk),.rst_sys_n(rst),.s_valid(v),.s_ready(ready),.s_data(b),
      .command_valid(cv),.command_done(done),.command_status(status),.command_sequence(seq),.command_payload_bytes(n),
      .command_source(src),.command_id(mid),.payload_read_word(read_word),.payload_read_data(read_data),
      .protocol_error_count(pe),.crc_error_count(ce),.last_sequence(ls),.buffered_bytes(used));
    initial begin
      $readmemh("cmd_rx_bytes.hex",bytes);
      $readmemh("cmd_rx_expected.hex",expected);
      repeat(4)@(negedge clk);rst=1;
      for(i=0;i<INPUT_BYTES;i=i+1)begin
        @(negedge clk);v=1;b=bytes[i];
        @(posedge clk);while(!ready)@(posedge clk);
        @(negedge clk);v=0;
        if(i%17==0)repeat(3)@(negedge clk);
      end
      wait(event_count==5);repeat(30)@(negedge clk);
      if(pe!=2 || ce!=1 || ls!=5 || used!=0)$fatal(1,"parser stats errors=%0d CRC=%0d buffered=%0d",pe,ce,used);
      // Truncated frame must time out and recover to accept further traffic.
      for(i=9;i<29;i=i+1)begin
        @(negedge clk);v=1;b=bytes[i];@(posedge clk);while(!ready)@(posedge clk);@(negedge clk);v=0;
      end
      wait(cv);if(status!=9)$fatal(1,"timeout expected");
      @(negedge clk);done=1;@(negedge clk);done=0;
      repeat(50)@(negedge clk);
      if(pe!=3 || used!=0)$fatal(1,"timeout recovery");
      $display("tb_vlp_cmd_rx_PASS events=%0d",event_count);$finish;
    end
    initial begin
      wait(rst);
      for(j=0;j<5;j=j+1)begin
        wait(cv);
        if(status!==expected[index] || seq!==expected[index+1])$fatal(1,"event %0d got status=%0d seq=%0d",j,status,seq);
        len=expected[index+2];index=index+3;
        if(status==0)begin
          if(n!=len || src!=1 || mid!='hfe)$fatal(1,"metadata");
          for(k=0;k<(len+3)/4;k=k+1)begin
            @(negedge clk);read_word=k;@(posedge clk);#1;
            mask=32'hffffffff;if(k*4+4>len)mask=(64'h1<<((len-k*4)*8))-1;
            if((read_data & mask)!==expected[index])$fatal(1,"payload word %0d %h != %h",k,read_data,expected[index]);
            index=index+1;
          end
        end
        repeat(7)@(negedge clk);done=1;@(negedge clk);done=0;event_count=event_count+1;
      end
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
