`timescale 1ns/1ps
module tb_tfa1500_parser;
    reg clk=0; always #5 clk=~clk;
    reg rst=0,en=1,hf=1,bv=0,bs=0,be=0;
    reg [7:0] bd=0;
    reg [63:0] now=0;
    always @(posedge clk) now<=now+1;
    wire f,d,c,i,e,t;
    wire [31:0] mm;
    wire [7:0] temp,status;
    wire [63:0] stamp;
    wire sync;
    integer nf=0,nd=0,nc=0,ni=0,ne=0,nt=0;
    reg [7:0] mask=0;
    tfa1500_parser dut(.sys_clk(clk),.rst_sys_n(rst),.enable(en),.high_mode(hf),
        .byte_data(bd),.byte_valid(bv),.byte_start(bs),.byte_error(be),
        .timestamp_now(now),.time_sync_valid(1'b1),.gap_ticks(32'd100),
        .lf_mm_per_count(16'd10),.lf_invalid_mask(mask),
        .frame_pulse(f),.distance_pulse(d),.checksum_pulse(c),.invalid_pulse(i),
        .format_pulse(e),.timeout_pulse(t),.distance_mm(mm),.apd_temp(temp),
        .device_status(status),.frame_timestamp(stamp),.frame_sync(sync));
    always @(posedge clk) begin
        if(f) nf=nf+1; if(d) nd=nd+1; if(c) nc=nc+1;
        if(i) ni=ni+1; if(e) ne=ne+1; if(t) nt=nt+1;
    end
    task byte_in; input [7:0] b; begin
        @(negedge clk); bs=1; @(negedge clk); bs=0;
        repeat(2) @(negedge clk); bd=b; bv=1;
        @(negedge clk); bv=0; repeat(2) @(negedge clk);
    end endtask
    task high_frame; input [23:0] raw; input bad; reg [7:0] sum; begin
        sum=raw[7:0]+raw[15:8]+raw[23:16];
        byte_in('h5c); byte_in(raw[7:0]); byte_in(raw[15:8]); byte_in(raw[23:16]);
        byte_in((~sum)^bad);
    end endtask
    task low_frame; input [7:0] flag; input bad; reg [7:0] x; begin
        x='h55^2^7^flag^8'h01^8'h23^8'h45^8'h00^8'h80^8'h19;
        byte_in('h55);byte_in(2);byte_in(7);byte_in(flag);
        byte_in('h01);byte_in('h23);byte_in('h45);byte_in(0);byte_in('h80);byte_in('h19);byte_in(x^bad);
    end endtask
    initial begin
        repeat(4) @(negedge clk);rst=1;
        high_frame(209,0); if(nd!=1 || mm!=2090 || !sync) $fatal(1,"Vendor vector");
        high_frame(130000,0); if(mm!=1300000) $fatal(1,"HF boundary");
        high_frame(0,0); if(mm!=0) $fatal(1,"Zero");
        high_frame('h3fffff,0); if(ni!=1 || nd!=3) $fatal(1,"Invalid sentinel");
        high_frame(130001,0); if(ni!=2) $fatal(1,"Range");
        high_frame(209,1); if(nc!=1 || nd!=3) $fatal(1,"Checksum rejection");
        byte_in('h5c);byte_in(1);repeat(110) @(negedge clk);
        if(nt!=1) $fatal(1,"Truncated frame timeout");
        byte_in('h5c); @(negedge clk);be=1;@(negedge clk);be=0;
        repeat(4) @(negedge clk); if(ne!=1) $fatal(1,"UART framing");
        hf=0; low_frame(0,0); if(mm!=745650 || temp!=25 || nd!=4) $fatal(1,"LF endian/scale");
        low_frame(0,1);if(nc!=2) $fatal(1,"LF XOR");
        mask=8'h80;low_frame('h80,0);if(ni!=3 || nd!=4) $fatal(1,"LF mask");
        byte_in('h55);byte_in(2);byte_in(17);if(ne!=2) $fatal(1,"Oversize length");
        en=0;low_frame(0,0);if(nd!=4) $fatal(1,"Disabled");
        en=1;hf=1;high_frame(92,0);if(nd!=5 || mm!=920) $fatal(1,"Re-enable/header in payload");
        $display("TB_TFA1500_PARSER_PASS");$finish;
    end
    initial begin #1000000;$fatal(1,"watchdog");end
endmodule
