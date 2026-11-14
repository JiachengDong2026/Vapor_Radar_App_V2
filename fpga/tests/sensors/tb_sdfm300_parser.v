`timescale 1ns/1ps
module tb_sdfm300_parser;
    reg clk=0; always #5 clk=~clk;
    reg rst=0,en=1,bv=0,bs=0,be=0;
    reg [7:0] bd=0;
    reg [63:0] now=0,expected_stamp;
    reg sv=1;
    always @(posedge clk) now<=now+1;
    wire f,d,c,i,e,t;wire [31:0] mm;wire [63:0] stamp;wire sync;
    integer nf=0,nd=0,nc=0,ni=0,ne=0,nt=0;
    sdfm300_parser dut(.sys_clk(clk),.rst_sys_n(rst),.enable(en),
        .byte_data(bd),.byte_valid(bv),.byte_start(bs),.byte_error(be),
        .timestamp_now(now),.time_sync_valid(sv),.gap_ticks(32'd100),
        .frame_pulse(f),.distance_pulse(d),.checksum_pulse(c),.invalid_pulse(i),
        .format_pulse(e),.timeout_pulse(t),.distance_mm(mm),
        .frame_timestamp(stamp),.frame_sync(sync));
    always @(posedge clk) begin
        if(f) nf=nf+1;if(d) nd=nd+1;if(c) nc=nc+1;
        if(i) ni=ni+1;if(e) ne=ne+1;if(t) nt=nt+1;
    end
    task byte_in;input [7:0] b;begin
        @(negedge clk);bs=1;if(b==8'h5c)expected_stamp=now;
        @(negedge clk);bs=0;repeat(2)@(negedge clk);bd=b;bv=1;
        @(negedge clk);bv=0;repeat(2)@(negedge clk);
    end endtask
    task frame;input [15:0] cm;input bad;reg [7:0] sum;begin
        sum=cm[7:0]+cm[15:8];byte_in('h5c);byte_in(cm[7:0]);byte_in(cm[15:8]);byte_in((~sum)^bad);
    end endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;
        byte_in(8'h55);byte_in(8'haa);
        frame(4354,0);if(nd!=1||mm!=43540||!sync||stamp!=expected_stamp)$fatal(1,"manual 5C 02 11 EC and start timestamp");
        frame(5,0);if(mm!=50)$fatal(1,"minimum 0.05m");
        frame(30000,0);if(mm!=300000)$fatal(1,"maximum 300m");
        frame(0,0);frame(4,0);frame(30001,0);frame(16'hffff,0);
        if(ni!=4||nd!=3||nf!=7)$fatal(1,"range and no echo 5C FF FF 01");
        frame(209,1);if(nc!=1||nd!=3)$fatal(1,"checksum excludes header");
        frame(16'h5c5c,0);if(mm!=236440||nd!=4)$fatal(1,"header as payload");
        byte_in('h5c);byte_in(1);repeat(110)@(negedge clk);
        if(nt!=1)$fatal(1,"truncated timeout");
        byte_in('h5c);@(negedge clk);be=1;@(negedge clk);be=0;
        repeat(4)@(negedge clk);if(ne!=1)$fatal(1,"framing error");
        // Byte loss: next header occupies checksum slot and is reused.
        byte_in('h5c);byte_in(1);byte_in(2);byte_in('h5c);byte_in(2);byte_in('h11);byte_in('hec);
        if(nd!=5||mm!=43540||nc!=2)$fatal(1,"header recovery");
        en=0;frame(209,0);if(nd!=5)$fatal(1,"disabled");
        en=1;sv=0;frame(209,0);if(nd!=6||sync||mm!=2090)$fatal(1,"reenable unsynced");
        byte_in('h5c);rst=0;repeat(4)@(negedge clk);rst=1;
        frame(4354,0);if(nd!=7)$fatal(1,"reset recovery");
        $display("TB_SDFM300_PARSER_PASS manual/bounds/noecho/checksum/timestamp/gap/framing/recovery/reset");$finish;
    end
    initial begin #1000000;$fatal(1,"watchdog");end
endmodule
