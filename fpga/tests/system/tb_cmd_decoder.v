`timescale 1ns/1ps
module tb_cmd_decoder;
    `include "command_sizes.vh"
    reg clk=0;always #5 clk=~clk;
    reg rst=0,rxv=0,txr=0;reg [7:0] rxd=0;
    wire rxr,cv,done;wire [31:0] cs,cseq,clen,prw,prd,pe,ce,rxseq,used;wire [15:0] csrc,cid;
    wire bv,bw,be,br;wire [31:0] ba,bd,brd;wire [3:0] bs;
    wire av,ar;wire [15:0] ac,asrc;wire [127:0] aa;wire [31:0] ast;
    wire mv,mr,ms,ml,seqv;wire [31:0] md,mc,mf,mseq;wire [3:0] mk;wire [15:0] msrc,mid;
    wire [63:0] mt;wire [7:0] ft;
    wire txv,txl;wire [31:0] txd,lastseq,fc,fe;
    reg [7:0] input_bytes[0:INPUT_BYTES-1];reg [31:0] gold[0:EXPECTED_WORDS-1];
    reg [31:0] regs[0:16383];
    integer i,tick=0,got=0,frames=0,bwait=0,awaits=0,writes=0,actions=0;
    reg stalled=0;reg [32:0] held;
    vlp_cmd_rx parser(.sys_clk(clk),.rst_sys_n(rst),.s_valid(rxv),.s_ready(rxr),.s_data(rxd),
      .command_valid(cv),.command_done(done),.command_status(cs),.command_sequence(cseq),.command_payload_bytes(clen),
      .command_source(csrc),.command_id(cid),.payload_read_word(prw),.payload_read_data(prd),
      .protocol_error_count(pe),.crc_error_count(ce),.last_sequence(rxseq),.buffered_bytes(used));
    cmd_decoder dut(.sys_clk(clk),.rst_sys_n(rst),.timestamp_now(64'h123456789abcdef0),
      .command_valid(cv),.command_done(done),.command_status(cs),.command_sequence(cseq),.command_payload_bytes(clen),
      .command_source(csrc),.command_id(cid),.payload_read_word(prw),.payload_read_data(prd),
      .cfg_valid(bv),.cfg_write(bw),.cfg_addr(ba),.cfg_wdata(bd),.cfg_wstrb(bs),.cfg_ready(br),.cfg_error(be),.cfg_error_code(4'd5),.cfg_rdata(brd),
      .action_valid(av),.action_ready(ar),.action_status(ast),.action_code(ac),.action_source(asrc),.action_args(aa),
      .m_valid(mv),.m_ready(mr),.m_data(md),.m_keep(mk),.m_sof(ms),.m_last(ml),.m_source_id(msrc),.m_msg_id(mid),
      .m_timestamp(mt),.m_cycle_id(mc),.m_flags(mf),.m_frame_type(ft),.m_sequence(mseq),.m_sequence_valid(seqv));
    data_packetizer packetizer(.sys_clk(clk),.rst_sys_n(rst),.s_valid(mv),.s_ready(mr),.s_data(md),.s_keep(mk),
      .s_sof(ms),.s_last(ml),.s_source_id(msrc),.s_msg_id(mid),.s_timestamp(mt),.s_cycle_id(mc),.s_flags(mf),
      .s_frame_type(ft),.s_sequence(mseq),.s_sequence_valid(seqv),.m_valid(txv),.m_ready(txr),.m_data(txd),.m_last(txl),
      .last_sequence(lastseq),.frame_count(fc),.format_error_count(fe));
    assign br=bv && bwait==2;
    assign be=ba=='h2ffc;
    assign brd=regs[ba[15:2]];
    assign ar=av && awaits==3;
    assign ast=ac==13?13:0;
    always @(negedge clk)begin tick=tick+1;txr=tick%9<5;end
    always @(posedge clk)if(rst)begin
      if(!bv || br)bwait<=0;else bwait<=bwait+1;
      if(!av || ar)awaits<=0;else awaits<=awaits+1;
    end
    // Sample handshakes independently from the delay model's NBA update.
    always @(posedge clk)if(rst)begin
      if(bv && br && !be && bw)begin regs[ba[15:2]]<=bd;writes=writes+1;if(bs!=15)$fatal(1,"strobe");end
      if(av && ar)begin
        if(ac==5 && asrc==16'h10 && aa==128'h10000)begin
          // Golden fixture models successful coordinated commit side effects.
          regs[32'h2004>>2]<=regs[32'h2004>>2]|4;
        end else if(ac<5 || ac>13 || asrc!=1 || aa[31:0]!=ac || aa[127:32]!=0)$fatal(1,"action arguments");
        actions=actions+1;
      end
      if(stalled && (!txv || {txl,txd}!==held))$fatal(1,"TX stall");
      stalled=txv && !txr;held={txl,txd};
      if(txv && txr)begin
        if(txd!==gold[got])$fatal(1,"golden word %0d frame %0d %h expected %h",got,frames,txd,gold[got]);
        got=got+1;if(txl)frames=frames+1;
      end
    end
    initial begin
      $readmemh("command_input.hex",input_bytes);$readmemh("command_expected.hex",gold);
      for(i=0;i<16384;i=i+1)regs[i]=32'h10000000+i;
      repeat(4)@(negedge clk);rst=1;
      for(i=0;i<INPUT_BYTES;i=i+1)begin
        @(negedge clk);rxv=1;rxd=input_bytes[i];@(posedge clk);while(!rxr)@(posedge clk);@(negedge clk);rxv=0;
      end
      wait(frames==EXPECTED_FRAMES);repeat(8)@(negedge clk);
      if(got!=EXPECTED_WORDS || writes!=4 || actions!=10 || pe!=1 || ce!=1 || fe!=0)$fatal(1,"counts writes=%0d actions=%0d pe=%0d ce=%0d fe=%0d",writes,actions,pe,ce,fe);
      $display("tb_cmd_decoder_PASS frames=%0d cfg_writes=%0d actions=%0d",frames,writes,actions);$finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
