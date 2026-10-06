`timescale 1ns/1ps
module tb_gpif_transport_buffers;
    reg sc=0,gc=0;always #5 sc=~sc;always #3.5 gc=~gc;
    reg rst=0,reset_done=0;
    reg tv=0,grv=0,gtr=0,br=0;
    reg [31:0] td=0,grd=0;reg tl=0;
    wire tr,rv,rr,gtv,gtl,grr,bv;wire [31:0] rd,gtd,stl,srl,gtlevel,grfree;wire [7:0] bd;
    integer tx_sent=0,tx_received=0,rx_sent=0,rx_bytes=0,st=0,gt=0;
    reg tx_stalled=0,byte_stalled=0;reg [32:0] held_tx;reg [7:0] held_byte;
    gpif_transport_buffers #(.DEPTH(16)) dut(.reset_n(rst),.sys_clk(sc),.gpif_clk(gc),.tx_valid(tv),.tx_ready(tr),
      .tx_data(td),.tx_last(tl),.rx_valid(rv),.rx_ready(rr),.rx_data(rd),.gpif_tx_valid(gtv),.gpif_tx_ready(gtr),
      .gpif_tx_data(gtd),.gpif_tx_last(gtl),.gpif_rx_valid(grv),.gpif_rx_ready(grr),.gpif_rx_data(grd),
      .sys_tx_level(stl),.sys_rx_level(srl),.gpif_tx_level(gtlevel),.gpif_rx_free(grfree));
    word_to_byte_stream bytes(.sys_clk(sc),.rst_sys_n(rst),.s_valid(rv),.s_ready(rr),.s_data(rd),.m_valid(bv),.m_ready(br),.m_data(bd));
    always @(negedge sc)begin
      if(!rst)begin tv=0;br=0;end
      else begin tv=tx_sent<200;td=32'h12345600+tx_sent*4;tl=tx_sent%13==12;br=st>40 && st%11<7;end
    end
    always @(negedge gc)begin
      if(!rst)begin grv=0;gtr=0;end
      else begin grv=rx_sent<200;grd=32'h55660000+rx_sent;gtr=gt>40 && gt%9<5;end
    end
    always @(posedge sc or negedge rst)begin
      if(!rst)begin tx_sent<=0;rx_bytes<=0;st<=0;byte_stalled<=0;end
      else begin
        st<=st+1;if(tv && tr)tx_sent<=tx_sent+1;
        if(byte_stalled && (!bv || bd!==held_byte))$fatal(1,"byte stall");
        byte_stalled<=bv&&!br;held_byte<=bd;
        if(bv && br)begin
          if(bd!==(((32'h55660000+rx_bytes/4)>>((rx_bytes%4)*8))&255))$fatal(1,"RX byte order %0d data %h",rx_bytes,bd);
          rx_bytes<=rx_bytes+1;
        end
        if(stl>16 || srl>16)$fatal(1,"sys occupancy");
      end
    end
    always @(posedge gc or negedge rst)begin
      if(!rst)begin tx_received<=0;rx_sent<=0;gt<=0;tx_stalled<=0;end
      else begin
        gt<=gt+1;if(grv && grr)rx_sent<=rx_sent+1;
        if(tx_stalled && (!gtv || {gtl,gtd}!==held_tx))$fatal(1,"GPIF TX stall");
        tx_stalled<=gtv&&!gtr;held_tx<={gtl,gtd};
        if(gtv && gtr)begin
          if(gtd!==32'h12345600+tx_received*4 || gtl!==(tx_received%13==12))$fatal(1,"GPIF TX order %0d",tx_received);
          tx_received<=tx_received+1;
        end
        if(gtlevel>16 || grfree>16)$fatal(1,"GPIF occupancy");
      end
    end
    initial begin
      repeat(5)@(negedge sc);rst=1;
      wait(tx_received>=60 && rx_bytes>=60);@(negedge sc);rst=0;
      repeat(7)@(negedge sc);rst=1;reset_done=1;
      wait(tx_received==200 && rx_bytes==800);repeat(15)@(negedge sc);
      if(tx_sent!=200 || rx_sent!=200 || stl!=0 || srl!=0 || gtlevel!=0 || grfree!=16)$fatal(1,"final count/empty");
      $display("tb_gpif_transport_buffers_PASS TX=%0d RX_bytes=%0d reset_recovery=%0d",tx_received,rx_bytes,reset_done);$finish;
    end
    initial begin #100000;$fatal(1,"timeout");end
endmodule
